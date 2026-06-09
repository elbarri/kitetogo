defmodule Kite4rent.MessageProcessor.Flows.DepositCollection do
  @moduledoc """
  Handles the deposit collection conversation flow - collecting deposit fields conversationally.
  """
  require Logger

  alias Kite4rent.Conversation.Manager, as: FlowManager
  alias Kite4rent.Conversation.State, as: FlowState
  alias Kite4rent.Deposits
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.MessageProcessor.TextUtils
  alias Kite4rent.ReplyComposer
  alias Kite4rent.ResponseTemplates
  alias Kite4rent.Users.User

  @doc "Handle when user sends text with deposit fields"
  def handle_deposit_collection_response(
        %WhatsappMessage{user: user} = message,
        %FlowState{collected_data: collected_data, missing_fields: missing_fields} = _state
      ) do
    text = TextUtils.extract_text_from_message(message)

    if text && String.length(String.trim(text)) > 0 do
      deposit_data = collected_data["deposit_data"] || %{}

      case extract_deposit_fields_from_text(text, missing_fields, deposit_data) do
        {:ok, extracted_fields} ->
          updated_deposit_data = Map.merge(deposit_data, extracted_fields)
          still_missing = get_still_missing_deposit_fields(updated_deposit_data, missing_fields)

          if Enum.empty?(still_missing) do
            complete_deposit_and_request_contact(user, updated_deposit_data)
          else
            FlowManager.add_data(user.id, %{"deposit_data" => updated_deposit_data})
            FlowManager.update_step(user.id, {:awaiting, :deposit_fields})

            language = User.get_language(user)
            prompt = build_deposit_followup_prompt(updated_deposit_data, still_missing, language)

            {:handled, {:ok, {:text, prompt}}}
          end

        {:error, _reason} ->
          language = User.get_language(user)
          error_msg = ResponseTemplates.get_template(:deposit_field_extraction_error, language)
          {:handled, {:ok, {:text, error_msg}}}
      end
    else
      :not_in_flow
    end
  end

  defp extract_deposit_fields_from_text(text, missing_fields, existing_data) do
    missing_str = Enum.map_join(missing_fields, ", ", &to_string/1)

    system_prompt = """
    You are extracting security deposit information from a user message.

    Current known data:
    - Amount: #{existing_data["amount"] || "unknown"}
    - Currency: #{existing_data["currency"] || "unknown"}
    - Duration (hours): #{existing_data["duration_hours"] || "unknown"}

    Missing fields that we need: #{missing_str}

    Extract any of the missing fields from the user's message.
    Valid currencies: EUR, USD, GBP
    Valid durations: 2 to 72 hours

    Respond with ONLY a JSON object with the extracted fields. Use null for fields not found.
    Example: {"amount": 500, "currency": "EUR", "duration_hours": 24}

    For amount, extract numeric value only (no currency symbols).
    For currency, normalize to uppercase (EUR, USD, GBP).
    For duration_hours, extract as integer (2 to 72).
    """

    case Kite4rent.LLMProcessor.generate_response(text, system_prompt) do
      {:ok, response} ->
        parse_deposit_extracted_fields(response)

      {:error, _type, _reason} ->
        {:error, :llm_failed}

      {:error, _reason} ->
        {:error, :llm_failed}
    end
  end

  defp parse_deposit_extracted_fields(response) do
    cleaned =
      response
      |> String.trim()
      |> String.replace(~r/^```json\s*/, "")
      |> String.replace(~r/\s*```$/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, fields} when is_map(fields) ->
        extracted =
          fields
          |> Enum.reject(fn {_k, v} -> is_nil(v) or v in ["null", "None", "none", ""] end)
          |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)

        {:ok, extracted}

      {:error, _} ->
        {:error, :parse_failed}
    end
  end

  defp get_still_missing_deposit_fields(deposit_data, original_missing) do
    original_missing
    |> Enum.filter(fn field ->
      key = to_string(field)
      value = deposit_data[key]
      is_nil(value) or value == ""
    end)
  end

  defp build_deposit_followup_prompt(deposit_data, still_missing, language) do
    amount_label = ResponseTemplates.get_template(:deposit_field_amount_label, language)
    currency_label = ResponseTemplates.get_template(:deposit_field_currency_label, language)
    duration_label = ResponseTemplates.get_template(:deposit_field_duration_label, language)

    known_parts =
      [
        if(deposit_data["amount"], do: "#{amount_label}: #{deposit_data["amount"]}"),
        if(deposit_data["currency"], do: "#{currency_label}: #{deposit_data["currency"]}"),
        if(deposit_data["duration_hours"], do: "#{duration_label}: #{deposit_data["duration_hours"]}")
      ]
      |> Enum.reject(&is_nil/1)

    known_str =
      if Enum.empty?(known_parts) do
        ""
      else
        prefix = ResponseTemplates.get_template(:deposit_field_known_prefix, language)
        "#{prefix} #{Enum.join(known_parts, ", ")}.\n\n"
      end

    question =
      case still_missing do
        [] ->
          ResponseTemplates.get_template(:deposit_field_confirm, language)

        [single_field] ->
          template_key = String.to_atom("deposit_field_question_#{single_field}")
          ResponseTemplates.get_template(template_key, language)

        fields ->
          missing_labels =
            fields
            |> Enum.map(fn
              :amount -> String.downcase(amount_label)
              :currency -> String.downcase(currency_label)
              :duration_hours -> String.downcase(duration_label)
              other -> to_string(other)
            end)

          fields_text = TextUtils.join_with_localized_and(missing_labels, language)
          ResponseTemplates.get_template(:deposit_field_question_multiple, language, %{fields: fields_text})
      end

    known_str <> question
  end

  defp complete_deposit_and_request_contact(user, deposit_data) do
    FlowManager.clear_flow(user.id)

    attrs = %{
      owner_id: user.id,
      amount: deposit_data["amount"],
      currency: String.upcase(to_string(deposit_data["currency"])),
      duration_hours: parse_deposit_duration(deposit_data["duration_hours"]),
      status: "pending"
    }

    case Deposits.create_security_deposit(attrs) do
      {:ok, deposit} ->
        Logger.info(
          "Created security deposit #{deposit.id} via conversation for user #{user.id}: " <>
            "#{deposit.amount} #{deposit.currency} for #{deposit.duration_hours} hours"
        )

        {:handled, ReplyComposer.compose_reply({:deposit_created_request_contact, deposit}, user)}

      {:error, changeset} ->
        Logger.error("Failed to create deposit via conversation: #{inspect(changeset.errors)}")
        language = User.get_language(user)
        error_msg = ResponseTemplates.get_template(:generic_error, language)
        {:handled, {:ok, {:text, error_msg}}}
    end
  end

  defp parse_deposit_duration(value) when is_integer(value), do: value
  defp parse_deposit_duration(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 2
    end
  end
  defp parse_deposit_duration(_), do: 2
end
