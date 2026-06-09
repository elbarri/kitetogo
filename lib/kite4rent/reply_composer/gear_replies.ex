defmodule Kite4rent.ReplyComposer.GearReplies do
  @moduledoc """
  Compose replies for gear-related actions (offer, request, inventory, completion).
  """
  require Logger

  alias Kite4rent.Conversation.Manager, as: FlowManager
  alias Kite4rent.Countries
  alias Kite4rent.GearFormatter
  alias Kite4rent.IntentionHandler.RequestGear
  alias Kite4rent.Rental
  alias Kite4rent.ReplyComposer.Helpers
  alias Kite4rent.ResponseTemplates
  alias Kite4rent.Translations
  alias Kite4rent.Users
  alias Kite4rent.Users.User

  @users_with_gear_limit Application.compile_env(:kite4rent, :display)[:users_with_gear_limit]

  def compose_reply({:full_gear_registered, _}, %User{} = user) do
    language = User.get_language(user)
    substitutions = Helpers.build_substitutions(user)
    message = ResponseTemplates.get_template(:full_gear_registered, language, substitutions)
    {:ok, {:text, message}}
  end

  def compose_reply({:offer_gear, gear}, %User{} = user) do
    language = User.get_language(user)
    substitutions = Helpers.build_substitutions(user)

    formatted_message =
      :gear_offer_success
      |> ResponseTemplates.get_template(language, substitutions)
      |> append_gear_details(gear, language)
      |> maybe_append_complement_suggestion(user, language)

    {:ok, {:text, formatted_message}}
  end

  def compose_reply(
        {:offer_gear_incomplete, %{stored: stored, incomplete: incomplete}},
        %User{} = user
      ) do
    start_gear_completion_conversation(user, stored, incomplete)
  end

  def compose_reply({:gear_offer_completed, gears}, %User{} = user) when is_list(gears) do
    if user.contact_sharing_consent do
      compose_reply({:offer_gear, gears}, user)
    else
      compose_reply({:contact_sharing_consent, gears}, user)
    end
  end

  def compose_reply({:contact_sharing_consent, _gear}, %User{} = user) do
    language = User.get_language(user)

    formatted_message = ResponseTemplates.get_template(:contact_sharing_consent_request, language)

    {:ok, {:text, formatted_message}, %{intent: "contact_sharing_consent_request"}}
  end

  def compose_reply({:list_own_inventory, gear}, %User{} = user)
      when gear != nil and length(gear) > 0 do
    language = User.get_language(user)
    formatted_gear = GearFormatter.format_gear_list(gear, aggregate: true)

    formatted_template =
      Helpers.build_substitutions(user)
      |> Map.put(:gear_list, formatted_gear)
      |> then(&ResponseTemplates.get_template(:list_own_inventory_success, language, &1))

    {:ok, {:text, formatted_template}}
  end

  def compose_reply({:list_own_inventory, _gear}, %User{} = user) do
    language = User.get_language(user)

    template =
      ResponseTemplates.get_template(
        :list_own_inventory_empty,
        language,
        Helpers.build_substitutions(user)
      )

    {:ok, {:text, template}}
  end

  def compose_reply(%RequestGear{users_with_gear: users_with_gear}, %User{} = user)
      when length(users_with_gear) > 0 do
    language = User.get_language(user)

    limited_users_with_gear = Enum.take(users_with_gear, @users_with_gear_limit)

    owners_list =
      limited_users_with_gear
      |> Enum.with_index(1)
      |> Enum.map(&format_owner_with_gear/1)
      |> Enum.join("\n\n")

    instruction = ResponseTemplates.get_template(:contact_selection_instruction, language)
    base_message = "#{owners_list}\n\n#{instruction}"

    listed_users_with_gear =
      limited_users_with_gear
      |> Enum.with_index(1)
      |> Enum.into(%{}, fn {%{user: user}, index} -> {index, user.id} end)

    {:ok, translated_message} = translate_response(base_message, language)
    {:ok, {:text, translated_message}, %{listed_users_with_gear: listed_users_with_gear}}
  end

  def compose_reply(%RequestGear{users_with_gear: []} = request_gear, %User{} = user) do
    language = User.get_language(user)

    case Users.find_closest_location_with_gear(%Kite4rent.Location{
           name: request_gear.location_name,
           latitude: request_gear.latitude,
           longitude: request_gear.longitude
         }) do
      nil ->
        substitutions =
          Helpers.build_substitutions(user)
          |> Map.put(:location_name, request_gear.location_name)
          |> Map.put(:closest_location_info, "")

        template =
          ResponseTemplates.get_template(:gear_request_no_results, language, substitutions)

        {:ok, {:text, template}}

      %{
        location_name: closest_name,
        country_code: country_code,
        latitude: lat,
        longitude: lng,
        distance_km: distance
      } ->
        formatted_location = "#{closest_name} (#{Countries.get_name(country_code, language)})"

        closest_location_text =
          ResponseTemplates.get_template(:gear_request_closest_location, language, %{
            closest_location_name: formatted_location,
            distance: trunc(distance)
          })

        substitutions =
          Helpers.build_substitutions(user)
          |> Map.put(:location_name, request_gear.location_name)
          |> Map.put(:closest_location_info, closest_location_text)

        body_text =
          ResponseTemplates.get_template(:gear_request_no_results, language, substitutions)

        button_text =
          ResponseTemplates.get_template(:i_am_interested, language)

        buttons = [
          %{
            id: "search_in_closest_location",
            title: button_text
          }
        ]

        extra_content = %{
          closest_location_name: closest_name,
          closest_location_country_code: country_code,
          closest_location_latitude: lat,
          closest_location_longitude: lng
        }

        {:ok, {:interactive_reply_buttons, body_text, buttons}, extra_content}
    end
  end

  def compose_reply({:availability_countries, countries}, %User{} = user) do
    language = User.get_language(user)
    header = ResponseTemplates.get_template(:availability_countries_header, language)

    country_list =
      countries
      |> Enum.map(fn %{country_code: cc, location_count: count} ->
        location_word = get_location_word(count, language)
        "• #{Countries.get_name(cc, language)} (#{count} #{location_word})"
      end)
      |> Enum.join("\n")

    {:ok, {:text, "#{header}\n#{country_list}"}}
  end

  def compose_reply(
        {:availability_locations, %{country_name: country_name, locations: locations}},
        %User{} = user
      ) do
    language = User.get_language(user)

    header =
      ResponseTemplates.get_template(:availability_locations_header, language, %{
        country: country_name
      })

    location_list =
      locations
      |> Enum.map(&"• #{&1}")
      |> Enum.join("\n")

    {:ok, {:text, "#{header}\n#{location_list}"}}
  end

  def compose_reply({:availability_no_gear, _}, %User{} = user) do
    language = User.get_language(user)
    message = ResponseTemplates.get_template(:availability_no_gear, language)
    {:ok, {:text, message}}
  end

  def compose_reply(
        {:availability_no_gear_in_country, %{country_name: country_name}},
        %User{} = user
      ) do
    language = User.get_language(user)

    message =
      ResponseTemplates.get_template(:availability_no_gear_in_country, language, %{
        country: country_name
      })

    {:ok, {:text, message}}
  end

  # ============================================================================
  # Gear Edit replies
  # ============================================================================

  def compose_reply({:edit_gear_active_deposit, gear}, %User{} = user) do
    language = User.get_language(user)
    formatted = GearFormatter.format_gear(gear)
    substitutions = %{gear: formatted}
    template = ResponseTemplates.get_template(:edit_gear_active_deposit, language, substitutions)
    {:ok, {:text, template}}
  end

  def compose_reply({:edit_gear_no_items, _}, %User{} = user) do
    language = User.get_language(user)
    template = ResponseTemplates.get_template(:edit_gear_no_items, language)
    {:ok, {:text, template}}
  end

  def compose_reply({:edit_gear_select_item, gear_list}, %User{} = user) do
    language = User.get_language(user)

    body_text = ResponseTemplates.get_template(:edit_gear_select_prompt, language)
    button_text = ResponseTemplates.get_template(:edit_gear_show_list_button, language)

    delete_all_label = ResponseTemplates.get_template(:edit_gear_delete_all_button, language)

    gear_rows =
      gear_list
      |> Enum.take(9)
      |> Enum.map(fn gear ->
        description = Helpers.format_gear_short_description(gear)

        %{
          id: "edit_gear_#{gear.id}",
          title: Helpers.truncate_string("#{gear.brand} #{gear.type}", 24),
          description: Helpers.truncate_string(description, 72)
        }
      end)

    delete_all_row = %{
      id: "edit_gear_delete_all",
      title: Helpers.truncate_string(delete_all_label, 24),
      description: ""
    }

    sections = [%{rows: gear_rows ++ [delete_all_row]}]
    {:ok, {:interactive_list, body_text, button_text, sections}}
  end

  def compose_reply({:edit_gear_select_field, gear}, %User{} = user) do
    language = User.get_language(user)

    formatted = GearFormatter.format_gear(gear)
    body_text = ResponseTemplates.get_template(:edit_gear_which_field, language, %{gear: formatted})

    buttons = [
      %{id: "edit_field_brand", title: ResponseTemplates.get_template(:gear_field_brand_label, language)},
      %{id: "edit_field_model", title: ResponseTemplates.get_template(:gear_field_model_label, language)},
      %{id: "edit_field_delete", title: ResponseTemplates.get_template(:edit_gear_delete_button, language)}
    ]

    {:ok, {:interactive_reply_buttons, body_text, buttons}}
  end

  def compose_reply({:edit_gear_ask_value, %{field: field, current_value: current_value}}, %User{} = user) do
    language = User.get_language(user)

    field_label =
      case field do
        "brand" -> ResponseTemplates.get_template(:gear_field_brand_label, language)
        "model" -> ResponseTemplates.get_template(:gear_field_model_label, language)
      end

    template =
      ResponseTemplates.get_template(:edit_gear_enter_value, language, %{
        field: field_label,
        current_value: current_value || "—"
      })

    {:ok, {:text, template}}
  end

  def compose_reply({:edit_gear_success, gear}, %User{} = user) do
    language = User.get_language(user)
    formatted = GearFormatter.format_gear(gear)
    template = ResponseTemplates.get_template(:edit_gear_updated, language, %{gear: formatted})
    {:ok, {:text, template}}
  end

  # 3-arity for ambiguous location in offer
  def compose_reply(
        {:error, {:ambiguous_location_in_offer, location_name, _countries_data}},
        %User{} = user,
        llm_response
      ) do
    language = User.get_language(user)
    substitutions = %{location_name: location_name}

    ambiguity_message =
      ResponseTemplates.get_template(:ambiguous_location_in_offer, language, substitutions)

    location_request_message =
      ResponseTemplates.get_template(:gear_offer_missing_location, language)

    extra_content = %{"llm_response" => llm_response}

    {:ok,
     [{:text, ambiguity_message}, {:location_request, location_request_message, extra_content}]}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @complement_types ~w(harness bar leash)

  defp maybe_append_complement_suggestion(message, %User{id: nil}, _language), do: message

  defp maybe_append_complement_suggestion(message, %User{} = user, language) do
    case Rental.list_available_gear_for_user(user.id) do
      {:ok, all_gear} ->
        existing_types = all_gear |> Enum.map(& &1.type) |> MapSet.new()
        has_kite? = MapSet.member?(existing_types, "kite")

        missing = Enum.reject(@complement_types, &MapSet.member?(existing_types, &1))

        if has_kite? and missing != [] do
          missing_labels =
            Enum.map(missing, &ResponseTemplates.translate_gear_type(&1, language))

          missing_text = Helpers.join_with_localized_and(missing_labels, language)

          suggestion =
            ResponseTemplates.get_template(:gear_complement_suggestion, language, %{
              missing_gear_types: missing_text
            })

          message <> "\n" <> String.trim(suggestion)
        else
          message
        end

      _ ->
        message
    end
  end

  defp start_gear_completion_conversation(%User{} = user, stored, incomplete) do
    language = User.get_language(user)

    stored_message =
      if Enum.empty?(stored) do
        ""
      else
        stored_summary = format_stored_gear_summary(stored, language)

        ResponseTemplates.get_template(:gear_stored_partial, language, %{gear: stored_summary}) <>
          "\n\n"
      end

    [first_incomplete | rest] = incomplete
    gear_data = first_incomplete.data
    missing_fields = first_incomplete.missing_fields
    gear_type = first_incomplete.type

    total_items = length(incomplete)

    multi_item_intro =
      if total_items > 1 do
        ResponseTemplates.get_template(:gear_multiple_items_intro, language, %{count: total_items}) <>
          "\n\n"
      else
        ""
      end

    rest_with_string_keys =
      Enum.map(rest, fn item ->
        %{
          "data" => item.data,
          "missing_fields" => item.missing_fields,
          "type" => item.type
        }
      end)

    FlowManager.start_flow(
      user.id,
      :gear_completion,
      {:awaiting, :gear_fields},
      initial_data: %{
        "gear_data" => gear_data,
        "stored_gear_ids" => Enum.map(stored, & &1.id),
        "remaining_incomplete" => rest_with_string_keys
      },
      missing_fields: missing_fields
    )

    translated_gear_type = ResponseTemplates.translate_gear_type(gear_type, language)
    prompt = build_gear_fields_prompt(translated_gear_type, gear_data, missing_fields, language)

    {:ok, {:text, stored_message <> multi_item_intro <> prompt}}
  end

  defp build_gear_fields_prompt(gear_type, gear_data, missing_fields, language) do
    brand_label = ResponseTemplates.get_template(:gear_field_brand_label, language)
    model_label = ResponseTemplates.get_template(:gear_field_model_label, language)
    size_label = ResponseTemplates.get_template(:gear_field_size_label, language)
    year_label = ResponseTemplates.get_template(:gear_field_year_label, language)
    gender_label = ResponseTemplates.get_template(:gear_field_gender_label, language)

    has_value? = fn v -> is_binary(v) and v != "" and v not in ["null", "None", "none"] end

    known_info =
      [
        if(has_value?.(gear_data["brand"]), do: "#{brand_label}: #{gear_data["brand"]}"),
        if(has_value?.(gear_data["model"]), do: "#{model_label}: #{gear_data["model"]}"),
        if(has_value?.(gear_data["size"]), do: "#{size_label}: #{gear_data["size"]}"),
        if(has_value?.(gear_data["year"]), do: "#{year_label}: #{gear_data["year"]}"),
        if(has_value?.(gear_data["gender"]), do: "#{gender_label}: #{gear_data["gender"]}")
      ]
      |> Enum.reject(&is_nil/1)

    known_part =
      if Enum.empty?(known_info) do
        ""
      else
        prefix = ResponseTemplates.get_template(:gear_field_known_prefix, language)
        "#{prefix} #{Enum.join(known_info, ", ")}\n\n"
      end

    question =
      case missing_fields do
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

          fields_text = Helpers.join_with_localized_and(missing_labels, language)

          ResponseTemplates.get_template(:gear_field_question_multiple, language, %{
            fields: fields_text,
            gear_type: gear_type
          })
      end

    known_part <> question
  end

  defp format_stored_gear_summary(stored, language) do
    {kites, others} = Enum.split_with(stored, fn g -> g.type == "kite" end)

    sorted_kites =
      Enum.sort_by(kites, fn g ->
        case g.size && Regex.run(~r/(\d+(?:\.\d+)?)/, g.size) do
          [_, num] -> elem(Float.parse(num), 0)
          _ -> 0.0
        end
      end)

    kite_lines = Enum.map(sorted_kites, &format_stored_item_short(&1, language))
    other_lines = Enum.map(others, &format_stored_item_short(&1, language))

    (kite_lines ++ other_lines)
    |> Enum.join("\n")
  end

  defp format_stored_item_short(gear, language) do
    type = gear.type

    if type in ["kite", "board"] do
      parts = [gear.model, gear.size, gear.year] |> Enum.filter(& &1) |> Enum.filter(&(&1 != ""))
      Enum.join(parts, " ")
    else
      translated_type = ResponseTemplates.translate_gear_type(type, language)
      parts = [translated_type, gear.brand, gear.model] |> Enum.filter(& &1) |> Enum.filter(&(&1 != ""))
      Enum.join(parts, " ")
    end
  end

  defp append_gear_details(base_message, gear_list, language)
       when is_list(gear_list) and length(gear_list) > 0 do
    Logger.info("Composing gear details for #{length(gear_list)} items")
    gear_summary = GearFormatter.format_gear_list(gear_list, aggregate: true)

    newly_listed_label =
      ResponseTemplates.get_template(:newly_listed_gear_label, language)

    "#{base_message}\n\n#{newly_listed_label}\n#{gear_summary}"
  end

  defp append_gear_details(base_message, _, _language), do: base_message

  defp format_owner_with_gear({%{user: user, gear: gear}, index}) do
    user_name = user.name || "Owner"

    is_school = Map.get(user, :is_school, false)
    is_renting_full_gear = Map.get(user, :is_renting_full_gear, false)

    location_label =
      if is_school do
        school_label = ResponseTemplates.get_template(:school_location_label, "en", %{location: user.location_name || ""})
        " (#{school_label})"
      else
        if user.location_name, do: " (#{user.location_name})", else: ""
      end

    full_gear_line =
      if is_renting_full_gear do
        ResponseTemplates.get_template(:full_gear_rental_label, "en")
      end

    aggregated = GearFormatter.aggregate_gear(gear)
    has_leash? = Enum.any?(aggregated, &(gear_item_type(&1) == "leash"))

    gear_list =
      aggregated
      |> Enum.reject(&(has_leash? and gear_item_type(&1) == "leash"))
      |> Enum.map(fn g ->
        formatted = GearFormatter.format_gear(g, listing: true, include_emoticon: false)
        if has_leash? and gear_item_type(g) == "harness", do: formatted <> " + leash", else: formatted
      end)
      |> Enum.join("\n")

    lines =
      ["#{index} - #{user_name}#{location_label}", full_gear_line, gear_list]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join("\n")

    lines
  end

  defp gear_item_type(gear), do: Map.get(gear, :type) || Map.get(gear, "type")

  defp translate_response(text, "en"), do: {:ok, text}

  defp translate_response(text, target_language) do
    case Translations.translate(text, "en", target_language) do
      {:ok, translated_text} ->
        {:ok, translated_text}

      {:error, reason} ->
        Logger.warning("Translation failed from en to #{target_language}: #{inspect(reason)}")
        {:ok, text}
    end
  end

  defp get_location_word(1, language),
    do: ResponseTemplates.get_template(:availability_location_singular, language)

  defp get_location_word(_, language),
    do: ResponseTemplates.get_template(:availability_location_plural, language)
end
