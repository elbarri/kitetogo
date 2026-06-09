defmodule Kite4rentWeb.AgreementLive do
  @moduledoc """
  LiveView for displaying and managing rental agreements.
  Provides real-time updates when photos are uploaded via WhatsApp.
  """

  use Kite4rentWeb, :live_view

  alias Kite4rent.Agreements
  alias Kite4rent.Agreements.RentalAgreement
  alias Kite4rent.Deposits
  alias Kite4rent.Users
  require Logger

  @impl true
  def mount(%{"uuid" => uuid} = params, _session, socket) do
    case Agreements.get_by_uuid_with_details(uuid) do
      nil ->
        {:ok, socket |> put_flash(:error, "Agreement not found") |> redirect(to: "/")}

      agreement ->
        # Subscribe to agreement updates for real-time photo updates
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Kite4rent.PubSub, "agreement:#{agreement.id}")
        end

        # Verify access token and determine role
        case verify_access(params, agreement) do
          {:ok, role} ->
            {:ok,
             socket
             |> assign(:agreement, agreement)
             |> assign(:role, role)
             |> assign(:page_title, "Rental Agreement")
             |> assign(:lightbox_open, false)
             |> assign(:lightbox_index, 0)
             |> assign(:terms_accepted, false)}

          {:error, reason} ->
            Logger.warning("Agreement access denied: #{inspect(reason)}")
            {:ok, socket |> put_flash(:error, "Invalid or expired access link") |> redirect(to: "/")}
        end
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_agreement", params, socket) do
    agreement = socket.assigns.agreement

    if RentalAgreement.editable?(agreement) do
      update_attrs = %{
        owner_name: params["owner_name"],
        renter_name: params["renter_name"],
        owner_email: params["owner_email"],
        renter_email: params["renter_email"],
        return_location: params["return_location"],
        return_time: parse_datetime(params["return_time"]),
        condition_notes: params["condition_notes"]
      }

      case Agreements.update_rental_agreement(agreement, update_attrs) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> assign(:agreement, Agreements.get_by_uuid_with_details(updated.uuid))
           |> put_flash(:info, "Agreement updated successfully.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to update agreement.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Agreement cannot be edited in its current state.")}
    end
  end

  @impl true
  def handle_event("update_item_values", params, socket) do
    agreement = socket.assigns.agreement

    if RentalAgreement.editable?(agreement) do
      case params["item_values"] do
        nil ->
          {:noreply, socket}

        item_values when is_map(item_values) ->
          parsed_values =
            item_values
            |> Enum.map(fn {id, value} ->
              item_id = String.to_integer(id)
              value_cents = parse_value_to_cents(value)
              {item_id, value_cents}
            end)
            |> Enum.into(%{})

          case Deposits.update_items_declared_values(agreement.security_deposit.id, parsed_values) do
            {:ok, _} ->
              # Reload the agreement to get updated totals
              updated = Agreements.get_by_uuid_with_details(agreement.uuid)

              {:noreply,
               socket
               |> assign(:agreement, updated)
               |> put_flash(:info, "Item values updated successfully.")}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to update item values.")}
          end
      end
    else
      {:noreply, put_flash(socket, :error, "Agreement cannot be edited in its current state.")}
    end
  end

  @impl true
  def handle_event("send_to_renter", _params, socket) do
    agreement = socket.assigns.agreement

    case Agreements.send_to_renter(agreement.id) do
      {:ok, updated} ->
        # Send WhatsApp notification to renter if renter exists
        deposit = agreement.security_deposit

        if deposit.renter do
          Kite4rent.MessageProcessor.notify_renter_agreement_ready(deposit, deposit.renter)
        else
          Logger.warning("Cannot notify renter - no renter assigned to deposit #{deposit.id}")
        end

        {:noreply,
         socket
         |> assign(:agreement, Agreements.get_by_uuid_with_details(updated.uuid))
         |> put_flash(:info, "Agreement sent to renter for review.")}

      {:error, :invalid_status_transition} ->
        {:noreply, put_flash(socket, :error, "Agreement cannot be sent in its current state.")}
    end
  end

  @impl true
  def handle_event("approve_agreement", _params, socket) do
    agreement = socket.assigns.agreement

    case Agreements.approve_agreement(agreement.id) do
      {:ok, updated} ->
        # Save names and emails to users' last_used fields
        save_last_used_fullnames(agreement)

        # Send payment link to renter
        deposit = agreement.security_deposit |> Kite4rent.Repo.preload([:owner, :renter])
        if deposit.renter do
          Kite4rent.MessageProcessor.notify_renter_payment_ready(deposit, deposit.renter)
        end

        # Notify owner that renter approved and is now waiting for payment
        if deposit.owner do
          Kite4rent.MessageProcessor.notify_owner_renter_approved_agreement(deposit, deposit.owner)
        end

        {:noreply,
         socket
         |> assign(:agreement, Agreements.get_by_uuid_with_details(updated.uuid))
         |> put_flash(:info, "Agreement approved. Please proceed with the security deposit.")}

      {:error, :invalid_status_transition} ->
        {:noreply, put_flash(socket, :error, "Agreement cannot be approved in its current state.")}
    end
  end

  @impl true
  def handle_event("request_changes", _params, socket) do
    agreement = socket.assigns.agreement

    case Agreements.request_changes(agreement.id) do
      {:ok, updated} ->
        # Notify owner that renter requested changes
        deposit = agreement.security_deposit
        owner = deposit.owner
        Kite4rent.MessageProcessor.notify_owner_changes_requested(deposit, owner)

        {:noreply,
         socket
         |> assign(:agreement, Agreements.get_by_uuid_with_details(updated.uuid))
         |> put_flash(:info, "Changes requested. The owner will be notified.")}

      {:error, :invalid_status_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot request changes in the current state.")}
    end
  end

  @impl true
  def handle_event("sign_agreement", _params, socket) do
    agreement = socket.assigns.agreement
    role = socket.assigns.role

    # Get IP from socket - in LiveView, we use assign or session for this
    ip_address = "0.0.0.0"

    result =
      case role do
        :owner -> Agreements.owner_sign(agreement.id, ip_address)
        :renter -> Agreements.renter_sign(agreement.id, ip_address)
        _ -> {:error, :invalid_role}
      end

    case result do
      {:ok, updated} ->
        message =
          if RentalAgreement.fully_signed?(updated) do
            "Agreement signed by both parties!"
          else
            "Agreement signed. Waiting for the other party."
          end

        {:noreply,
         socket
         |> assign(:agreement, Agreements.get_by_uuid_with_details(updated.uuid))
         |> put_flash(:info, message)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Cannot sign the agreement in its current state.")}
    end
  end

  @impl true
  def handle_event("update_duration", %{"duration_hours" => duration_str}, socket) do
    agreement = socket.assigns.agreement

    if socket.assigns.role == :owner && agreement.status in ["draft", "negotiating"] do
      duration_hours = String.to_integer(duration_str)

      case Deposits.set_duration(agreement.security_deposit.id, duration_hours) do
        {:ok, _} ->
          updated = Agreements.get_by_uuid_with_details(agreement.uuid)

          {:noreply,
           socket
           |> assign(:agreement, updated)
           |> put_flash(:info, "Duration updated to #{duration_hours} hours.")}

        {:error, changeset} ->
          error_msg =
            case changeset.errors[:duration_hours] do
              {msg, _} -> msg
              _ -> "Invalid duration"
            end

          {:noreply, put_flash(socket, :error, error_msg)}
      end
    else
      {:noreply, put_flash(socket, :error, "Cannot edit duration in current state.")}
    end
  end

  @impl true
  def handle_event("delete_photo", %{"id" => photo_id}, socket) do
    agreement = socket.assigns.agreement

    # Only allow deletion in draft/negotiating status by owner
    if socket.assigns.role == :owner && agreement.status in ["draft", "negotiating"] do
      case Agreements.delete_photo(String.to_integer(photo_id)) do
        {:ok, _} ->
          updated = Agreements.get_by_uuid_with_details(agreement.uuid)

          {:noreply,
           socket
           |> assign(:agreement, updated)
           |> put_flash(:info, "Photo removed.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to remove photo.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Cannot delete photos in current state.")}
    end
  end

  @impl true
  def handle_event("open_lightbox", %{"index" => index}, socket) do
    {:noreply,
     socket
     |> assign(:lightbox_open, true)
     |> assign(:lightbox_index, String.to_integer(index))}
  end

  @impl true
  def handle_event("close_lightbox", _params, socket) do
    {:noreply, assign(socket, :lightbox_open, false)}
  end

  @impl true
  def handle_event("lightbox_prev", _params, socket) do
    photos_count = length(socket.assigns.agreement.photos)
    current = socket.assigns.lightbox_index
    new_index = if current == 0, do: photos_count - 1, else: current - 1
    {:noreply, assign(socket, :lightbox_index, new_index)}
  end

  @impl true
  def handle_event("lightbox_next", _params, socket) do
    photos_count = length(socket.assigns.agreement.photos)
    current = socket.assigns.lightbox_index
    new_index = if current >= photos_count - 1, do: 0, else: current + 1
    {:noreply, assign(socket, :lightbox_index, new_index)}
  end

  @impl true
  def handle_event("toggle_terms", _params, socket) do
    {:noreply, assign(socket, :terms_accepted, !socket.assigns.terms_accepted)}
  end

  # Handle real-time photo update broadcasts
  @impl true
  def handle_info({:photo_added, _photo}, socket) do
    # Reload the agreement to get updated photos
    updated = Agreements.get_by_uuid_with_details(socket.assigns.agreement.uuid)
    Logger.info("LiveView received photo_added broadcast, reloading agreement")

    {:noreply, assign(socket, :agreement, updated)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Helper functions

  # Verifies the access token and ensures the user has permission to view
  # the agreement in the specified role.
  defp verify_access(%{"token" => token}, agreement) do
    case Kite4rent.AgreementAuth.verify_token(token) do
      {:ok, %{agreement_uuid: token_uuid, user_id: user_id, role: role}} ->
        # Verify the token matches this agreement
        if token_uuid == agreement.uuid do
          # Verify the user_id matches the role
          case role do
            :owner ->
              if agreement.security_deposit.owner_id == user_id do
                {:ok, :owner}
              else
                {:error, :user_mismatch}
              end

            :renter ->
              if agreement.security_deposit.renter_id == user_id do
                {:ok, :renter}
              else
                {:error, :user_mismatch}
              end
          end
        else
          {:error, :agreement_mismatch}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_access(_params, _agreement) do
    # No valid token provided
    {:error, :missing_token}
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string <> ":00Z") do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp parse_value_to_cents(value) when is_binary(value) do
    case Float.parse(value) do
      {float_val, _} -> round(float_val * 100)
      :error -> 0
    end
  end

  defp parse_value_to_cents(value) when is_number(value), do: round(value * 100)

  defp save_last_used_fullnames(agreement) do
    deposit = agreement.security_deposit

    owner_updates =
      %{}
      |> maybe_put(:last_used_fullname, agreement.owner_name)
      |> maybe_put(:last_used_email, agreement.owner_email)

    if owner_updates != %{} do
      Users.update_user(deposit.owner, owner_updates)
    end

    if deposit.renter do
      renter_updates =
        %{}
        |> maybe_put(:last_used_fullname, agreement.renter_name)
        |> maybe_put(:last_used_email, agreement.renter_email)

      if renter_updates != %{} do
        Users.update_user(deposit.renter, renter_updates)
      end
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Display helper functions (also used in template)
  def format_amount(amount, currency) do
    "#{Decimal.to_string(amount)} #{currency}"
  end

  def format_cents(cents, currency) when is_integer(cents) do
    value = cents / 100
    "#{:erlang.float_to_binary(value, decimals: 2)} #{currency}"
  end

  def format_cents(_, currency), do: "? #{currency}"

  def format_datetime(nil), do: "Not specified"

  def format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%B %d, %Y at %H:%M UTC")
  end

  def status_color("draft"), do: "bg-gray-100 text-gray-800"
  def status_color("pending_renter_review"), do: "bg-yellow-100 text-yellow-800"
  def status_color("negotiating"), do: "bg-orange-100 text-orange-800"
  def status_color("approved"), do: "bg-blue-100 text-blue-800"
  def status_color("signed"), do: "bg-green-100 text-green-800"
  def status_color("completed"), do: "bg-green-100 text-green-800"
  def status_color("cancelled"), do: "bg-red-100 text-red-800"
  def status_color(_), do: "bg-gray-100 text-gray-800"

  def status_label("draft"), do: "Draft"
  def status_label("pending_renter_review"), do: "Pending Renter Review"
  def status_label("negotiating"), do: "Negotiating"
  def status_label("approved"), do: "Approved"
  def status_label("signed"), do: "Signed"
  def status_label("completed"), do: "Completed"
  def status_label("cancelled"), do: "Cancelled"
  def status_label(status), do: status

  def format_gear_type("kite"), do: "Kite"
  def format_gear_type("board"), do: "Board"
  def format_gear_type("bar"), do: "Bar + Lines"
  def format_gear_type("harness"), do: "Harness"
  def format_gear_type(type), do: String.capitalize(type || "Item")

  def get_owner_name(agreement) do
    owner = agreement.security_deposit.owner

    cond do
      agreement.owner_name && agreement.owner_name != "" -> agreement.owner_name
      owner.last_used_fullname && owner.last_used_fullname != "" -> owner.last_used_fullname
      owner.name && owner.name != "" -> owner.name
      true -> "Owner"
    end
  end

  def get_renter_name(agreement) do
    case agreement.security_deposit.renter do
      nil ->
        "Not yet assigned"

      renter ->
        cond do
          agreement.renter_name && agreement.renter_name != "" -> agreement.renter_name
          renter.last_used_fullname && renter.last_used_fullname != "" -> renter.last_used_fullname
          renter.name && renter.name != "" -> renter.name
          true -> "Renter"
        end
    end
  end

  def get_owner_email(agreement) do
    owner = agreement.security_deposit.owner

    cond do
      agreement.owner_email && agreement.owner_email != "" -> agreement.owner_email
      owner.last_used_email && owner.last_used_email != "" -> owner.last_used_email
      owner.email && owner.email != "" -> owner.email
      true -> ""
    end
  end

  def get_renter_email(agreement) do
    case agreement.security_deposit.renter do
      nil ->
        ""

      renter ->
        cond do
          agreement.renter_email && agreement.renter_email != "" -> agreement.renter_email
          renter.last_used_email && renter.last_used_email != "" -> renter.last_used_email
          renter.email && renter.email != "" -> renter.email
          true -> ""
        end
    end
  end
end
