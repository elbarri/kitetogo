defmodule Kite4rent.MessageProcessor.Flows.DepositItemSelection do
  @moduledoc """
  Handles the deposit item selection conversation flow - gear selection, value input,
  currency selection, duration input, and contact collection for deposits.
  """
  require Logger

  alias Kite4rent.Conversation.Manager, as: FlowManager
  alias Kite4rent.Conversation.State, as: FlowState
  alias Kite4rent.Deposits
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.MessageProcessor.TextUtils
  alias Kite4rent.Rental
  alias Kite4rent.ReplyComposer
  alias Kite4rent.Repo
  alias Kite4rent.ResponseTemplates
  alias Kite4rent.Users
  alias Kite4rent.Users.User

  @doc "Handle currency selection for deposit flow"
  def handle_deposit_currency_selection(user, button_id, collected_data) do
    case String.split(button_id, "_") do
      ["deposit", "currency", currency] ->
        supported = Application.get_env(:kite4rent, :supported_currencies, ["EUR", "USD", "GBP"])

        if currency in supported do
          case Users.update_user(user, %{currency: currency}) do
            {:ok, updated_user} ->
              Logger.info("User #{user.id} selected currency: #{currency}")

              FlowManager.add_data(user.id, %{"currency" => currency})
              FlowManager.update_step(user.id, :awaiting_value)

              current_item = collected_data["current_item"]
              gear = Rental.get_gear!(current_item["gear_id"])
              suggested_value = if gear && gear.value && gear.value > 0, do: gear.value, else: nil

              {:handled, ReplyComposer.compose_reply({:deposit_ask_value, current_item, suggested_value, currency}, updated_user)}

            {:error, reason} ->
              Logger.error("Failed to update user currency: #{inspect(reason)}")
              {:handled, {:error, :currency_update_failed}}
          end
        else
          Logger.error("Invalid currency selected: #{currency}")
          {:handled, {:error, :invalid_currency}}
        end

      _ ->
        Logger.error("Invalid currency button_id format: #{button_id}")
        {:handled, {:error, :invalid_selection}}
    end
  end

  @doc "Handle deposit gear selection from list"
  def handle_deposit_gear_selection(user, selection_id) do
    case String.split(selection_id, "_") do
      ["deposit", "gear", gear_id_str] ->
        case Integer.parse(gear_id_str) do
          {gear_id, ""} ->
            case Rental.get_gear!(gear_id) do
              nil ->
                Logger.error("Gear not found for deposit selection: #{gear_id}")
                {:handled, {:error, :gear_not_found}}

              gear ->
                current_item = %{
                  "gear_id" => gear.id,
                  "description" => format_gear_description(gear)
                }

                FlowManager.add_data(user.id, %{"current_item" => current_item})

                if is_nil(user.currency) or user.currency == "" do
                  FlowManager.update_step(user.id, :awaiting_currency)
                  {:handled, ReplyComposer.compose_reply({:deposit_ask_currency, current_item}, user)}
                else
                  FlowManager.update_step(user.id, :awaiting_value)
                  suggested_value = if gear.value && gear.value > 0, do: gear.value, else: nil
                  {:handled, ReplyComposer.compose_reply({:deposit_ask_value, current_item, suggested_value, user.currency}, user)}
                end
            end

          _ ->
            Logger.error("Invalid gear_id in deposit selection: #{gear_id_str}")
            {:handled, {:error, :invalid_selection}}
        end

      _ ->
        Logger.error("Invalid deposit gear selection_id format: #{selection_id}")
        {:handled, {:error, :invalid_selection}}
    end
  end

  @doc "Handle user entering value for an item"
  def handle_deposit_item_value_input(
        %WhatsappMessage{user: user} = message,
        %FlowState{collected_data: collected_data} = _state
      ) do
    text = TextUtils.extract_text_from_message(message)

    case parse_value_from_text(text) do
      {:ok, value_cents} ->
        current_item = collected_data["current_item"]
        selected_items = collected_data["selected_items"] || []
        total_value = collected_data["total_value"] || 0
        currency = collected_data["currency"] || user.currency || "EUR"

        completed_item = Map.put(current_item, "value", value_cents)
        new_selected_items = selected_items ++ [completed_item]
        new_total = total_value + value_cents

        selected_gear_ids = Enum.map(new_selected_items, & &1["gear_id"])
        {:ok, all_gear} = Rental.list_available_gear_for_user(user.id)
        remaining_gear = Enum.reject(all_gear, &(&1.id in selected_gear_ids))

        FlowManager.add_data(user.id, %{
          "selected_items" => new_selected_items,
          "current_item" => nil,
          "total_value" => new_total,
          "available_gear_ids" => Enum.map(remaining_gear, & &1.id)
        })

        if Enum.empty?(remaining_gear) or length(all_gear) == 1 do
          FlowManager.update_step(user.id, :awaiting_duration)
          {:handled, ReplyComposer.compose_reply({:deposit_ask_duration, new_total, new_selected_items, currency}, user)}
        else
          FlowManager.update_step(user.id, :confirm_add_more)
          {:handled, ReplyComposer.compose_reply({:deposit_item_added, completed_item, new_total, currency}, user)}
        end

      {:error, :invalid_value} ->
        language = User.get_language(user)
        error_msg = ResponseTemplates.get_template(:deposit_invalid_value_format, language)
        {:handled, {:ok, {:text, error_msg}}}
    end
  end

  @doc "Handle user entering duration hours for deposit"
  def handle_deposit_duration_input(user, text, collected_data) do
    case parse_duration_hours(text) do
      {:ok, duration_hours} ->
        FlowManager.add_data(user.id, %{"duration_hours" => duration_hours})
        FlowManager.update_step(user.id, :awaiting_contact)

        selected_items = collected_data["selected_items"] || []
        total_value = collected_data["total_value"] || 0
        currency = collected_data["currency"] || user.currency || "EUR"

        {:handled, ReplyComposer.compose_reply(
          {:deposit_request_contact, total_value, selected_items, duration_hours, currency},
          user
        )}

      {:error, :invalid_duration} ->
        language = User.get_language(user)
        error_msg = ResponseTemplates.get_template(:deposit_field_question_duration_hours, language)
        {:handled, {:ok, {:text, error_msg}}}
    end
  end

  @doc "Handle 'Yes, add more' button"
  def handle_deposit_add_more_item_action(%WhatsappMessage{user: user} = _message) do
    case FlowManager.get_state(user.id) do
      {:ok, %FlowState{current_flow: :deposit_item_selection, collected_data: collected_data}} ->
        selected_items = collected_data["selected_items"] || []
        selected_gear_ids = Enum.map(selected_items, & &1["gear_id"])

        {:ok, all_gear} = Rental.list_available_gear_for_user(user.id)
        remaining_gear = Enum.reject(all_gear, &(&1.id in selected_gear_ids))

        if Enum.empty?(remaining_gear) do
          total_value = collected_data["total_value"] || 0
          currency = collected_data["currency"] || user.currency || "EUR"
          FlowManager.update_step(user.id, :awaiting_duration)
          ReplyComposer.compose_reply({:deposit_ask_duration, total_value, selected_items, currency}, user)
        else
          FlowManager.update_step(user.id, :selecting_item)
          total_gear = length(all_gear)
          ReplyComposer.compose_reply({:deposit_select_gear, %{gear_list: remaining_gear, total_count: total_gear}}, user)
        end

      _ ->
        Logger.warning("deposit_add_more_item called but no active deposit_item_selection flow")
        {:error, :no_active_flow}
    end
  end

  @doc "Handle 'No, continue' button - proceed to duration selection"
  def handle_deposit_proceed_to_duration_action(%WhatsappMessage{user: user} = _message) do
    case FlowManager.get_state(user.id) do
      {:ok, %FlowState{current_flow: :deposit_item_selection, collected_data: collected_data}} ->
        selected_items = collected_data["selected_items"] || []
        total_value = collected_data["total_value"] || 0
        currency = collected_data["currency"] || user.currency || "EUR"

        FlowManager.update_step(user.id, :awaiting_duration)
        ReplyComposer.compose_reply({:deposit_ask_duration, total_value, selected_items, currency}, user)

      _ ->
        Logger.warning("deposit_proceed_to_duration called but no active deposit_item_selection flow")
        {:error, :no_active_flow}
    end
  end

  @doc "Handle contact received in deposit item selection flow - create deposit with items"
  def handle_deposit_item_contact_received(
        %WhatsappMessage{user: user} = message,
        %FlowState{collected_data: collected_data} = _state
      ) do
    contacts = message.content["contacts"] || []

    case contacts do
      [] ->
        Logger.warning("No contacts found in deposit item flow message")
        {:handled, {:error, :no_contacts}}

      [first_contact | _] ->
        phones = get_in(first_contact, ["phones"]) || []
        first_phone = get_in(phones, [Access.at(0), "phone"])
        contact_name = get_in(first_contact, ["name", "formatted_name"])

        if first_phone do
          normalized_phone = String.replace(first_phone, ~r/[^\d]/, "")

          case Users.get_user_by_phone(normalized_phone) do
            {:ok, renter} ->
              create_deposit_with_items_and_notify(user, renter, collected_data, contact_name)

            {:error, :not_found} ->
              Logger.info("Contact #{contact_name} (#{first_phone}) not found in system for deposit")
              FlowManager.clear_flow(user.id)

              {:handled,
               ReplyComposer.compose_reply(
                 {:contact_not_registered, contact_name, first_phone},
                 user
               )}
          end
        else
          Logger.warning("Contact has no phone number in deposit item flow")
          {:handled, {:error, :contact_no_phone}}
        end
    end
  end

  defp create_deposit_with_items_and_notify(owner, renter, collected_data, _contact_name) do
    selected_items = collected_data["selected_items"] || []
    duration_hours = collected_data["duration_hours"] || 2
    currency = collected_data["currency"] || owner.currency || "EUR"
    total_value = collected_data["total_value"] || 0

    deposit_attrs = %{
      owner_id: owner.id,
      renter_id: renter.id,
      currency: currency,
      duration_hours: duration_hours,
      status: "awaiting_renter_confirmation"
    }

    items =
      Enum.map(selected_items, fn item ->
        %{
          gear_id: item["gear_id"],
          declared_value: item["value"]
        }
      end)

    # Clear the flow before the DB write so a crash between commit and clear
    # cannot leave the user in a stale :awaiting_contact state and trigger a
    # duplicate deposit on the next message.
    FlowManager.clear_flow(owner.id)

    case Deposits.create_deposit_with_items(deposit_attrs, items) do
      {:ok, deposit} ->
        Logger.info(
          "Created deposit #{deposit.id} with #{length(items)} items, " <>
            "total: #{total_value} #{currency} cents, for renter #{renter.id}"
        )

        deposit = Repo.preload(deposit, [:owner, :renter, :items])
        Kite4rent.MessageProcessor.Notifications.notify_owner_to_review_agreement(deposit, owner)

        {:handled, {:ok, :ignored}}

      {:error, reason} ->
        Logger.error("Failed to create deposit with items: #{inspect(reason)}")
        language = User.get_language(owner)
        error_msg = ResponseTemplates.get_template(:generic_error, language)
        {:handled, {:ok, {:text, error_msg}}}
    end
  end

  # Parse value from user input (handles various formats: "800", "800 EUR", "€800", etc.)
  defp parse_value_from_text(text) when is_binary(text) do
    cleaned =
      text
      |> String.trim()
      |> String.replace(~r/[€$£]/, "")
      |> String.replace(~r/[,.](\d{2})$/, ".\\1")
      |> String.replace(~r/[^\d.]/, "")

    case Float.parse(cleaned) do
      {value, _} when value > 0 ->
        cents = round(value * 100)
        {:ok, cents}

      _ ->
        {:error, :invalid_value}
    end
  end

  defp parse_value_from_text(_), do: {:error, :invalid_value}

  defp parse_duration_hours(text) when is_binary(text) do
    cleaned = String.replace(text, ~r/[^\d]/, "")

    case Integer.parse(cleaned) do
      {hours, _} when hours >= 2 and hours <= 72 ->
        {:ok, hours}

      _ ->
        {:error, :invalid_duration}
    end
  end

  defp parse_duration_hours(_), do: {:error, :invalid_duration}

  defp format_gear_description(gear) do
    parts = [gear.brand, gear.type, gear.model, gear.size, gear.year]
    parts |> Enum.reject(&is_nil/1) |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
  end
end
