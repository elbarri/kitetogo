defmodule Kite4rent.MessageProcessor.Flows.GearCompletion do
  @moduledoc """
  Handles the gear completion conversation flow - collecting missing gear fields.
  """
  require Logger

  alias Kite4rent.Conversation.Manager, as: FlowManager
  alias Kite4rent.Conversation.State, as: FlowState
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.MessageProcessor.TextUtils
  alias Kite4rent.Rental
  alias Kite4rent.ReplyComposer
  alias Kite4rent.ResponseTemplates
  alias Kite4rent.Users.User

  @doc "Handle when user sends text with gear fields"
  def handle_gear_completion_response(
        %WhatsappMessage{user: user} = message,
        %FlowState{collected_data: collected_data, missing_fields: missing_fields} = _state
      ) do
    text = TextUtils.extract_text_from_message(message)

    if text && String.length(String.trim(text)) > 0 do
      gear_data = collected_data["gear_data"] || %{}

      case extract_gear_fields_from_text(text, missing_fields, gear_data) do
        {:ok, extracted_fields} ->
          missing_keys = MapSet.new(Enum.map(missing_fields, &to_string/1))
          relevant_fields = Map.filter(extracted_fields, fn {k, _} -> k in missing_keys end)
          updated_gear_data = Map.merge(gear_data, relevant_fields)
          updated_gear_data = maybe_enrich_from_reference(updated_gear_data)
          still_missing = get_still_missing_fields(updated_gear_data, missing_fields)

          if Enum.empty?(still_missing) do
            save_completed_gear_and_continue(user, updated_gear_data, collected_data)
          else
            FlowManager.add_data(user.id, %{"gear_data" => updated_gear_data})
            FlowManager.update_step(user.id, {:awaiting, :gear_fields})

            language = User.get_language(user)
            raw_gear_type = gear_data["type"] || "gear"
            gear_type = ResponseTemplates.translate_gear_type(raw_gear_type, language)
            prompt = build_followup_prompt(updated_gear_data, still_missing, gear_type, language)

            {:handled, {:ok, {:text, prompt}}}
          end

        {:error, _reason} ->
          language = User.get_language(user)
          error_msg = ResponseTemplates.get_template(:gear_field_extraction_error, language)
          {:handled, {:ok, {:text, error_msg}}}
      end
    else
      :not_in_flow
    end
  end

  defp maybe_enrich_from_reference(%{"model" => model} = gear_data)
       when is_binary(model) and model != "" do
    case Kite4rent.Rental.lookup_model_info(model) do
      {:ok, %{brand: brand, gear_type: gear_type}} ->
        gear_data
        |> maybe_put("brand", brand)
        |> maybe_put("type", gear_type)

      {:ambiguous, _brands} ->
        gear_data

      :not_found ->
        gear_data
    end
  end

  defp maybe_enrich_from_reference(gear_data), do: gear_data

  defp maybe_put(data, key, value) do
    current = data[key]
    if is_nil(current) or current == "" or current == "other", do: Map.put(data, key, value), else: data
  end

  # Extract gear fields from user text using LLM
  defp extract_gear_fields_from_text(text, missing_fields, existing_data) do
    missing_str = Enum.map_join(missing_fields, ", ", &to_string/1)
    gear_type = existing_data["type"] || "gear"

    system_prompt = """
    You are extracting kitesurfing gear information from a user message.
    The user is providing details about a #{gear_type}.

    Current known data:
    - Brand: #{existing_data["brand"] || "unknown"}
    - Model: #{existing_data["model"] || "unknown"}
    - Size: #{existing_data["size"] || "unknown"}
    - Year: #{existing_data["year"] || "unknown"}
    - Gender: #{existing_data["gender"] || "unknown"}

    Missing fields that we need: #{missing_str}

    Extract any of the missing fields from the user's message.
    Common kitesurfing brands: Duotone, North, Cabrinha, Core, Slingshot, F-One, Ozone, Naish, Eleveight, Airush.

    Respond with ONLY a JSON object with the extracted fields. Use null for fields not found.
    Example: {"brand": "North", "model": "Orbit", "size": "10m", "year": "2023", "gender": "M"}

    Only include fields that are clearly mentioned. Don't guess.
    For size, include units if mentioned (m, cm, etc).
    For year, extract 4-digit year if mentioned.
    For gender, use "M" for male/masculine and "F" for female/feminine.
    """

    case Kite4rent.LLMProcessor.generate_response(text, system_prompt) do
      {:ok, response} ->
        parse_extracted_fields(response)

      {:error, _type, _reason} ->
        {:error, :llm_failed}

      {:error, _reason} ->
        {:error, :llm_failed}
    end
  end

  defp parse_extracted_fields(response) do
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

  def get_still_missing_fields(gear_data, original_missing) do
    original_missing
    |> Enum.filter(fn field ->
      key = to_string(field)
      value = gear_data[key]
      is_nil(value) or value == "" or value in ["null", "None", "none"]
    end)
  end

  def build_followup_prompt(gear_data, still_missing, gear_type, language) do
    brand_label = ResponseTemplates.get_template(:gear_field_brand_label, language)
    model_label = ResponseTemplates.get_template(:gear_field_model_label, language)
    size_label = ResponseTemplates.get_template(:gear_field_size_label, language)
    year_label = ResponseTemplates.get_template(:gear_field_year_label, language)
    gender_label = ResponseTemplates.get_template(:gear_field_gender_label, language)

    has_value? = fn v -> is_binary(v) and v != "" and v not in ["null", "None", "none"] end

    known_parts =
      [
        if(has_value?.(gear_data["brand"]), do: "#{brand_label}: #{gear_data["brand"]}"),
        if(has_value?.(gear_data["model"]), do: "#{model_label}: #{gear_data["model"]}"),
        if(has_value?.(gear_data["size"]), do: "#{size_label}: #{gear_data["size"]}"),
        if(has_value?.(gear_data["year"]), do: "#{year_label}: #{gear_data["year"]}"),
        if(has_value?.(gear_data["gender"]), do: "#{gender_label}: #{gear_data["gender"]}")
      ]
      |> Enum.reject(&is_nil/1)

    known_str =
      if Enum.empty?(known_parts) do
        ""
      else
        prefix = ResponseTemplates.get_template(:gear_field_known_prefix, language)
        "#{prefix} #{Enum.join(known_parts, ", ")}. "
      end

    question =
      case still_missing do
        [] ->
          ResponseTemplates.get_template(:gear_field_confirm, language, %{gear_type: gear_type})

        [single_field] ->
          template_key = String.to_atom("gear_field_question_#{single_field}")
          ResponseTemplates.get_template(template_key, language, %{gear_type: gear_type})

        fields ->
          missing_labels =
            fields
            |> Enum.map(fn
              :brand -> String.downcase(brand_label)
              :model -> String.downcase(model_label)
              :size -> String.downcase(size_label)
              :year -> String.downcase(year_label)
              :gender -> String.downcase(gender_label)
              other -> to_string(other)
            end)

          fields_text = TextUtils.join_with_localized_and(missing_labels, language)
          ResponseTemplates.get_template(:gear_field_question_multiple, language, %{
            fields: fields_text,
            gear_type: gear_type
          })
      end

    known_str <> question
  end

  defp save_completed_gear_and_continue(user, gear_data, collected_data) do
    gear_attrs =
      gear_data
      |> Map.put("user_id", user.id)

    case Rental.create_gear(gear_attrs) do
      {:ok, saved_gear} ->
        Logger.info("Gear saved via conversation: #{saved_gear.id} for user #{user.id}")

        remaining = collected_data["remaining_incomplete"] || []
        stored_ids = collected_data["stored_gear_ids"] || []
        all_stored_ids = stored_ids ++ [saved_gear.id]

        if Enum.empty?(remaining) do
          FlowManager.clear_flow(user.id)
          all_gears = Rental.get_gears_by_ids(all_stored_ids)
          {:handled, ReplyComposer.compose_reply({:gear_offer_completed, all_gears}, user)}
        else
          remaining = propagate_fields_to_similar_items(gear_data, remaining)

          {auto_saved_ids, still_incomplete} =
            auto_save_complete_items(remaining, user.id)

          all_stored_ids = all_stored_ids ++ auto_saved_ids

          if Enum.empty?(still_incomplete) do
            FlowManager.clear_flow(user.id)
            all_gears = Rental.get_gears_by_ids(all_stored_ids)
            {:handled, ReplyComposer.compose_reply({:gear_offer_completed, all_gears}, user)}
          else
            [next_incomplete | rest] = still_incomplete
            next_gear_data = next_incomplete["data"]
            next_missing = next_incomplete["missing_fields"] |> Enum.map(&safe_to_atom/1)
            next_type = next_incomplete["type"]

            FlowManager.add_data(user.id, %{
              "gear_data" => next_gear_data,
              "stored_gear_ids" => all_stored_ids,
              "remaining_incomplete" => rest
            })
            FlowManager.update_missing_fields(user.id, next_missing)
            FlowManager.update_step(user.id, {:awaiting, :gear_fields})

            language = User.get_language(user)

            auto_saved_msg =
              if auto_saved_ids != [] do
                count = length(auto_saved_ids)
                saved_template = ResponseTemplates.get_template(:gear_auto_saved, language, %{count: count})
                saved_template <> "\n\n"
              else
                ""
              end

            intro = ResponseTemplates.get_template(:gear_next_item_intro, language)
            translated_next_type = ResponseTemplates.translate_gear_type(next_type, language)
            prompt = auto_saved_msg <> intro <> "\n\n" <> build_followup_prompt(next_gear_data, next_missing, translated_next_type, language)

            {:handled, {:ok, {:text, prompt}}}
          end
        end

      {:error, changeset} ->
        Logger.error("Failed to save gear via conversation: #{inspect(changeset.errors)}")
        language = User.get_language(user)
        error_msg = ResponseTemplates.get_template(:gear_save_error, language)
        {:handled, {:ok, {:text, error_msg}}}
    end
  end

  defp propagate_fields_to_similar_items(completed_data, remaining_items) do
    completed_model = completed_data["model"]
    completed_type = completed_data["type"]

    Enum.map(remaining_items, fn item ->
      item_data = item["data"]
      item_model = item_data["model"]
      item_type = item_data["type"]

      if same_value?(completed_type, item_type) and same_value?(completed_model, item_model) do
        propagatable = ["brand", "year", "gender", "condition"]

        updated_data =
          Enum.reduce(propagatable, item_data, fn field, acc ->
            source_val = completed_data[field]
            target_val = acc[field]

            if has_propagatable_value?(source_val) and not has_propagatable_value?(target_val) do
              Map.put(acc, field, source_val)
            else
              acc
            end
          end)

        updated_missing =
          item["missing_fields"]
          |> Enum.map(&to_string/1)
          |> Enum.filter(fn field ->
            not has_propagatable_value?(updated_data[field])
          end)

        %{item | "data" => updated_data, "missing_fields" => updated_missing}
      else
        item
      end
    end)
  end

  defp same_value?(a, b) when is_binary(a) and is_binary(b) do
    String.downcase(String.trim(a)) == String.downcase(String.trim(b))
  end

  defp same_value?(_, _), do: false

  defp has_propagatable_value?(val) do
    is_binary(val) and val != "" and val not in ["null", "None", "none"]
  end

  defp auto_save_complete_items(items, user_id) do
    {complete, incomplete} =
      Enum.split_with(items, fn item -> Enum.empty?(item["missing_fields"]) end)

    saved_ids =
      Enum.flat_map(complete, fn item ->
        gear_attrs = Map.put(item["data"], "user_id", user_id)

        case Rental.create_gear(gear_attrs) do
          {:ok, saved_gear} ->
            Logger.info("Gear auto-saved via propagation: #{saved_gear.id} for user #{user_id}")
            [saved_gear.id]

          {:error, changeset} ->
            Logger.error("Failed to auto-save propagated gear: #{inspect(changeset.errors)}")
            []
        end
      end)

    {saved_ids, incomplete}
  end

  defp safe_to_atom(field) when is_atom(field), do: field

  defp safe_to_atom(field) when is_binary(field) do
    String.to_existing_atom(field)
  rescue
    ArgumentError -> String.to_atom(field)
  end
end
