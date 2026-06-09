defmodule Kite4rent.ReplyComposer.DepositReplies do
  @moduledoc """
  Compose replies for deposit-related actions.
  """

  alias Kite4rent.ReplyComposer.Helpers
  alias Kite4rent.Repo
  alias Kite4rent.ResponseTemplates
  alias Kite4rent.Users.User
  alias Kite4rent.WhatsappClient

  def compose_reply({:no_gear_to_rent, _nil}, %User{} = user) do
    language = User.get_language(user)
    template = ResponseTemplates.get_template(:deposit_no_gear_to_rent, language)
    {:ok, {:text, template}}
  end

  def compose_reply({:deposit_creation_failed, _nil}, %User{} = user) do
    language = User.get_language(user)
    template = ResponseTemplates.get_template(:generic_error, language)
    {:ok, {:text, template}}
  end

  def compose_reply(
        {:deposit_ask_missing_fields, %{collected: collected, missing: missing}},
        %User{} = user
      ) do
    language = User.get_language(user)
    prompt = build_deposit_fields_prompt(collected, missing, language)
    {:ok, {:text, prompt}}
  end

  def compose_reply({:deposit_created_request_contact, deposit}, %User{} = user) do
    language = User.get_language(user)
    duration_text = Helpers.format_duration_hours(deposit.duration_hours, language)
    amount_formatted = "#{deposit.amount} #{deposit.currency}"

    template =
      ResponseTemplates.get_template(:deposit_created_request_contact, language, %{
        amount: amount_formatted,
        duration: duration_text
      })

    {:ok, {:text, template}}
  end

  def compose_reply({:deposit_released, deposit}, %User{} = user) do
    language = User.get_language(user)
    amount_formatted = "#{deposit.amount} #{deposit.currency}"

    template =
      ResponseTemplates.get_template(:deposit_released, language, %{
        amount: amount_formatted
      })

    {:ok, {:text, template}}
  end

  def compose_reply({:renter_attached, deposit}, %User{} = user) do
    deposit = Repo.preload(deposit, [:owner, :renter])
    language = User.get_language(user)
    renter_name = deposit.renter.name || "the renter"

    owner_template =
      ResponseTemplates.get_template(
        :deposit_renter_attached_owner_notification,
        language,
        %{renter_name: renter_name}
      )

    send_renter_checkout_link(deposit)

    {:ok, {:text, owner_template}}
  end

  def compose_reply({:contact_not_registered, contact_name, _phone}, %User{} = user) do
    language = User.get_language(user)

    template =
      ResponseTemplates.get_template(
        :deposit_contact_not_registered,
        language,
        %{contact_name: contact_name}
      )

    {:ok, {:text, template}}
  end

  # =============================================================================
  # Deposit Item Selection Flow Compose Replies
  # =============================================================================

  def compose_reply(
        {:deposit_select_gear, %{gear_list: gear_list, total_count: total_gear_count}},
        %User{} = user
      ) do
    language = User.get_language(user)

    body_text = ResponseTemplates.get_template(:deposit_select_gear_prompt, language)
    button_text = ResponseTemplates.get_template(:deposit_show_gear_button, language)

    body_text =
      if length(gear_list) < total_gear_count do
        note =
          ResponseTemplates.get_template(:deposit_showing_partial, language, %{
            shown: length(gear_list),
            total: total_gear_count
          })

        "#{body_text}\n\n_#{note}_"
      else
        body_text
      end

    rows =
      gear_list
      |> Enum.take(10)
      |> Enum.map(fn gear ->
        description = Helpers.format_gear_short_description(gear)

        %{
          id: "deposit_gear_#{gear.id}",
          title: Helpers.truncate_string("#{gear.brand} #{gear.type}", 24),
          description: Helpers.truncate_string(description, 72)
        }
      end)

    sections = [%{rows: rows}]

    {:ok, {:interactive_list, body_text, button_text, sections}}
  end

  def compose_reply({:deposit_ask_currency, item}, %User{} = user) do
    language = User.get_language(user)
    description = item["description"]

    supported_currencies =
      Application.get_env(:kite4rent, :supported_currencies, ["EUR", "USD", "GBP"])

    body_text =
      ResponseTemplates.get_template(:deposit_ask_currency, language, %{item: description})

    buttons =
      supported_currencies
      |> Enum.take(3)
      |> Enum.map(fn currency ->
        %{id: "deposit_currency_#{currency}", title: currency}
      end)

    {:ok, {:interactive_reply_buttons, body_text, buttons}}
  end

  def compose_reply({:deposit_ask_value, item, suggested_value, currency}, %User{} = user) do
    language = User.get_language(user)
    description = item["description"]

    template =
      if suggested_value && suggested_value > 0 do
        formatted_value = Helpers.format_cents_as_currency(suggested_value, currency)

        ResponseTemplates.get_template(:deposit_ask_value_with_hint, language, %{
          item: description,
          currency: currency,
          suggested_value: formatted_value
        })
      else
        ResponseTemplates.get_template(:deposit_ask_value, language, %{
          item: description,
          currency: currency
        })
      end

    {:ok, {:text, template}}
  end

  def compose_reply({:deposit_item_added, item, total_cents, currency}, %User{} = user) do
    language = User.get_language(user)
    description = item["description"]
    item_value = Helpers.format_cents_as_currency(item["value"], currency)
    total_formatted = Helpers.format_cents_as_currency(total_cents, currency)

    body_text =
      ResponseTemplates.get_template(:deposit_item_added, language, %{
        item: description,
        value: item_value,
        total: total_formatted
      })

    buttons = [
      %{
        id: "deposit_add_more_yes",
        title: ResponseTemplates.get_template(:deposit_add_more_yes_btn, language)
      },
      %{
        id: "deposit_add_more_no",
        title: ResponseTemplates.get_template(:deposit_add_more_no_btn, language)
      }
    ]

    {:ok, {:interactive_reply_buttons, body_text, buttons}}
  end

  def compose_reply(
        {:deposit_ask_duration, total_cents, selected_items, currency},
        %User{} = user
      ) do
    language = User.get_language(user)
    total_formatted = Helpers.format_cents_as_currency(total_cents, currency)
    item_count = length(selected_items)

    body_text =
      ResponseTemplates.get_template(:deposit_ask_duration, language, %{
        total: total_formatted,
        item_count: item_count
      })

    {:ok, {:text, body_text}}
  end

  def compose_reply(
        {:deposit_request_contact, total_cents, selected_items, duration_hours, currency},
        %User{} = user
      ) do
    language = User.get_language(user)
    total_formatted = Helpers.format_cents_as_currency(total_cents, currency)
    duration_text = Helpers.format_duration_hours(duration_hours, language)
    item_count = length(selected_items)

    items_summary =
      selected_items
      |> Enum.map(fn item ->
        value = Helpers.format_cents_as_currency(item["value"], currency)
        "• #{item["description"]} - #{value}"
      end)
      |> Enum.join("\n")

    template =
      ResponseTemplates.get_template(:deposit_request_contact, language, %{
        items_summary: items_summary,
        total: total_formatted,
        duration: duration_text,
        item_count: item_count
      })

    {:ok, {:text, template}}
  end

  def compose_reply({:deposit_created_with_items, deposit, contact_name}, %User{} = user) do
    language = User.get_language(user)
    amount_formatted = "#{Decimal.to_string(deposit.amount)} #{deposit.currency}"
    items_count = length(deposit.items)

    template =
      ResponseTemplates.get_template(:deposit_created_with_items, language, %{
        contact_name: contact_name,
        amount: amount_formatted,
        items_count: items_count,
        duration_hours: deposit.duration_hours
      })

    {:ok, {:text, template}}
  end

  def compose_reply({:deposit_created_review_agreement, deposit, contact_name}, %User{} = user) do
    language = User.get_language(user)
    amount_formatted = "#{Decimal.to_string(deposit.amount)} #{deposit.currency}"
    items_count = length(deposit.items)

    template =
      ResponseTemplates.get_template(:deposit_created_review_agreement, language, %{
        contact_name: contact_name,
        amount: amount_formatted,
        items_count: items_count,
        duration_hours: deposit.duration_hours
      })

    {:ok, {:text, template}}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp build_deposit_fields_prompt(collected, missing, language) do
    amount_label = ResponseTemplates.get_template(:deposit_field_amount_label, language)
    currency_label = ResponseTemplates.get_template(:deposit_field_currency_label, language)
    duration_label = ResponseTemplates.get_template(:deposit_field_duration_label, language)

    known_info =
      [
        if(collected["amount"], do: "#{amount_label}: #{collected["amount"]}"),
        if(collected["currency"], do: "#{currency_label}: #{collected["currency"]}"),
        if(collected["duration_hours"], do: "#{duration_label}: #{collected["duration_hours"]}")
      ]
      |> Enum.reject(&is_nil/1)

    known_part =
      if Enum.empty?(known_info) do
        ""
      else
        prefix = ResponseTemplates.get_template(:deposit_field_known_prefix, language)
        "#{prefix} #{Enum.join(known_info, ", ")}\n\n"
      end

    question =
      case missing do
        [] ->
          ResponseTemplates.get_template(:deposit_field_confirm, language)

        [single_field] ->
          template_key = String.to_atom("deposit_field_question_#{single_field}")
          ResponseTemplates.get_template(template_key, language)

        fields ->
          missing_labels =
            fields
            |> Enum.map(fn
              :amount -> amount_label
              :currency -> currency_label
              :duration_hours -> duration_label
            end)

          labels_joined = Helpers.join_with_localized_and(missing_labels, language)

          ResponseTemplates.get_template(:deposit_field_question_multiple, language, %{
            fields: labels_joined
          })
      end

    known_part <> question
  end

  defp send_renter_checkout_link(deposit) do
    renter_language = User.get_language(deposit.renter)
    owner_name = deposit.owner.name || "The owner"
    amount_formatted = "#{deposit.amount} #{deposit.currency}"
    duration_text = Helpers.format_duration_hours(deposit.duration_hours, renter_language)

    base_url = Application.get_env(:kite4rent, :base_url)
    checkout_url = "#{base_url}/deposit-checkout/#{deposit.id}"

    body_text =
      ResponseTemplates.get_template(
        :deposit_renter_checkout_invitation,
        renter_language,
        %{owner_name: owner_name, amount: amount_formatted, duration: duration_text}
      )

    button_text = ResponseTemplates.get_template(:deposit_checkout_button, renter_language)

    WhatsappClient.send_interactive_cta_url(
      deposit.renter.whatsapp,
      body_text,
      button_text,
      checkout_url
    )

    test_notice = ResponseTemplates.get_template(:test_mode_payment_notice, renter_language, %{})
    WhatsappClient.send_message(deposit.renter.whatsapp, test_notice)
  end
end
