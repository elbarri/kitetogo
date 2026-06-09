defmodule Kite4rent.MessageProcessor.Notifications do
  @moduledoc """
  Handles sending notifications to users via WhatsApp for various events
  (agreement reviews, deposit releases, disputes, etc.)
  """
  require Logger

  alias Kite4rent.Agreements
  alias Kite4rent.Rental
  alias Kite4rent.ResponseTemplates
  alias Kite4rent.Users.User
  alias Kite4rent.WhatsappClient

  def notify_owner_to_review_agreement(deposit, owner) do
    language = User.get_language(owner)
    renter_name = deposit.renter.name || "the renter"
    amount_formatted = "#{Decimal.to_string(deposit.amount)} #{deposit.currency}"

    body_text =
      ResponseTemplates.get_template(:agreement_review_prompt, language, %{
        renter_name: renter_name,
        amount: amount_formatted,
        duration_hours: deposit.duration_hours
      })

    agreement_url = create_agreement_url_for_deposit(deposit, :owner)
    button_text = ResponseTemplates.get_template(:review_agreement_button, language)
    header_text = ResponseTemplates.get_template(:agreement_ready_header, language)

    case WhatsappClient.send_interactive_cta_url(
           owner.whatsapp,
           body_text,
           button_text,
           agreement_url,
           header_text: header_text
         ) do
      {:ok, _} ->
        Logger.info("Sent agreement review link to owner #{owner.id} for deposit #{deposit.id}")

      {:error, reason} ->
        Logger.error("Failed to send agreement review link to owner #{owner.id}: #{inspect(reason)}")
    end
  end

  def notify_renter_agreement_ready(deposit, renter) do
    language = User.get_language(renter)
    owner_name = deposit.owner.name || "The owner"
    amount_formatted = "#{Decimal.to_string(deposit.amount)} #{deposit.currency}"
    items_count = length(deposit.items)

    items_text =
      deposit.items
      |> Enum.map(fn item ->
        gear = Rental.get_gear!(item.gear_id)
        value_formatted = format_cents_for_display(item.declared_value, deposit.currency)
        "• #{format_gear_description(gear)}: #{value_formatted}"
      end)
      |> Enum.join("\n")

    body_text =
      ResponseTemplates.get_template(:agreement_ready_for_renter, language, %{
        owner_name: owner_name,
        amount: amount_formatted,
        items_count: items_count,
        items_text: items_text,
        duration_hours: deposit.duration_hours
      })

    agreement_url = create_agreement_url_for_deposit(deposit, :renter)
    button_text = ResponseTemplates.get_template(:view_agreement_button, language)
    header_text = ResponseTemplates.get_template(:agreement_ready_header, language)

    case WhatsappClient.send_interactive_cta_url(
           renter.whatsapp,
           body_text,
           button_text,
           agreement_url,
           header_text: header_text
         ) do
      {:ok, _} ->
        Logger.info("Sent agreement to renter #{renter.id} for deposit #{deposit.id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to send agreement to renter #{renter.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def notify_owner_changes_requested(deposit, owner) do
    language = User.get_language(owner)
    renter_name = if deposit.renter, do: deposit.renter.name || "The renter", else: "The renter"

    body_text = """
    #{renter_name} has requested changes to the rental agreement.

    Please review and modify the agreement as needed, then submit it again for their review.
    """

    agreement_url = create_agreement_url_for_deposit(deposit, :owner)
    button_text = ResponseTemplates.get_template(:view_agreement_button, language)
    header_text = "Changes Requested"

    case WhatsappClient.send_interactive_cta_url(
           owner.whatsapp,
           body_text,
           button_text,
           agreement_url,
           header_text: header_text
         ) do
      {:ok, _} ->
        Logger.info("Notified owner #{owner.id} about changes requested for deposit #{deposit.id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to notify owner #{owner.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def notify_owner_renter_approved_agreement(deposit, owner) do
    language = User.get_language(owner)
    renter_name = if deposit.renter, do: deposit.renter.name || "the renter", else: "the renter"
    amount_formatted = "#{deposit.amount} #{deposit.currency}"

    message = ResponseTemplates.get_template(:agreement_approved_owner_notification, language, %{
      renter_name: renter_name,
      amount: amount_formatted
    })

    WhatsappClient.send_message(owner.whatsapp, message)
    Logger.info("Owner #{owner.id} notified that renter approved agreement for deposit #{deposit.id}")
  end

  def notify_renter_payment_ready(deposit, renter) do
    language = User.get_language(renter)
    owner_name = deposit.owner.name || "The owner"
    amount_formatted = "#{Decimal.to_string(deposit.amount)} #{deposit.currency}"

    substitutions = %{
      owner_name: owner_name,
      amount: amount_formatted,
      duration: deposit.duration_hours
    }

    body_text = ResponseTemplates.get_template(:renter_payment_ready_body, language, substitutions)
    button_text = ResponseTemplates.get_template(:renter_payment_ready_button, language)
    header_text = ResponseTemplates.get_template(:renter_payment_ready_header, language)

    base_url = Application.get_env(:kite4rent, :base_url, "https://kite4rent.com")
    payment_url = "#{base_url}/deposit-checkout/#{deposit.id}"

    case WhatsappClient.send_interactive_cta_url(
           renter.whatsapp,
           body_text,
           button_text,
           payment_url,
           header_text: header_text
         ) do
      {:ok, _} ->
        Logger.info("Sent payment link to renter #{renter.id} for deposit #{deposit.id}")
        send_test_mode_payment_notice(renter)
        :ok

      {:error, reason} ->
        Logger.error("Failed to send payment link to renter #{renter.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper functions

  defp send_test_mode_payment_notice(user) do
    language = User.get_language(user)
    message = ResponseTemplates.get_template(:test_mode_payment_notice, language, %{})
    WhatsappClient.send_message(user.whatsapp, message)
  end

  defp create_agreement_url_for_deposit(deposit, role) do
    base_url = Application.get_env(:kite4rent, :base_url, "https://kite4rent.com")

    case Agreements.get_by_security_deposit(deposit.id) do
      nil ->
        "#{base_url}/deposit-checkout/#{deposit.id}"

      agreement ->
        user_id = if role == :owner, do: deposit.owner_id, else: deposit.renter_id
        Kite4rent.AgreementAuth.generate_agreement_url(base_url, agreement.uuid, user_id, role)
    end
  end

  defp format_cents_for_display(cents, currency) when is_integer(cents) do
    value = cents / 100
    "#{:erlang.float_to_binary(value, decimals: 2)} #{currency}"
  end

  defp format_cents_for_display(_, currency), do: "? #{currency}"

  defp format_gear_description(gear) do
    parts = [gear.brand, gear.type, gear.model, gear.size, gear.year]
    parts |> Enum.reject(&is_nil/1) |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
  end
end
