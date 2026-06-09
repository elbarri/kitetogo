defmodule Kite4rent.Extractors.GearExtractor do
  @moduledoc """
  Extracts gear information from user messages with focus on brand consistency.
  Uses InstructorLite for schema-driven structured outputs with automatic validation and retries.
  """

  require Logger
  alias Kite4rent.Extractors.GearExtraction

  @doc """
  Extract gear information from text with brand consistency validation.

  Returns:
  - {:ok, result} on successful extraction (map with :gear, :extraction_confidence, etc.)
  - {:error, type, message} on failure
  """
  def extract(text, opts \\ []) do
    system_prompt = build_system_prompt(opts)

    params = %{
      messages: [
        %{role: "system", content: system_prompt},
        %{role: "user", content: text}
      ]
    }

    case Kite4rent.LLM.instruct(params, response_model: GearExtraction, max_retries: 1) do
      {:ok, %GearExtraction{} = result} ->
        sanitized = sanitize_result(result)
        enriched = enrich_from_reference(sanitized)
        enriched = infer_bar_brand_from_kites(enriched)
        enriched = maybe_clear_clarification(sanitized, enriched)
        {:ok, enriched}

      {:error, reason} ->
        Logger.error("Gear extraction failed",
          error: :gear_extraction_error,
          reason: inspect(reason),
          text: text
        )

        {:error, :gear_extraction_error, "Gear extraction failed"}
    end
  end

  defp build_system_prompt(opts) do
    language_instruction =
      case Keyword.get(opts, :language) do
        nil ->
          ""

        lang ->
          "The user is communicating in '#{lang}'. Always write clarification_request in this language."
      end

    intent_context =
      case Keyword.get(opts, :intent) do
        "request_gear" -> "The user is looking for gear to RENT, not offering their own."
        _ -> "The user is offering their gear for rent."
      end

    {user_audio_transcription_prompt, brand_pronunciation_prompt} =
      if Keyword.get(opts, :is_audio?) do
        {
          "As kitesurfing brands are pronounced in many ways, if the user has stated a gear's brand name it might happen that the transcript doesn't have a 100% accurate brand name.",
          "Be aware that these are audio transcriptions and brand names are potentially wrongly transcribed"
        }
      else
        {"", ""}
      end

    """
    Your task is to extract the kite gear mentioned in this message, if any.
    #{intent_context}

    When addressing the kitesurfing gear the user mentions in the messages:
    1. Identify the type of gear (kite, bar, board, harness, helmet, vest, leash, wetsuit, other)
    2. ONLY extract the brand if the user EXPLICITLY states it. If the brand is not mentioned, set brand to null. NEVER guess or infer a brand from the model name alone. #{brand_pronunciation_prompt}
    3. Note any specific model names or sizes mentioned
    4. For harnesses and wetsuits: identify gender if mentioned (Male/M/Hombre -> "M", Female/F/Mujer -> "F")
    5. Identify any additional details about the gear's condition or specifications

    #{language_instruction}
    #{user_audio_transcription_prompt}

    Popular kitesurfing brands include:
    Duotone, Eleveight, Reedin, North, Aoua, Cabrinha, F-One, Slingshot, Core, Naish,
    Airush, Ozone, Ocean Rodeo, Peter Lynn, Takoon, Shinn, RRD, Ronix, Rip Curl,
    Ride Engine, Prolimit, O'Neill, Nobile, Mystic, Liquid Force, Lieuwe Boards,
    Lenten, ION, Flysurfer, Dakine, CrazyFly, Brunotti, AXIS, Spleene, Best,
    Gaastra, Kitelement, Woodboard, Zian, Wainman, HQ, Griffin

    Size conventions by gear type:
    - Kites: measured in square meters. People write "9m", "12", "13.5qm" (German for m²) — the size should be just the number, preserving decimals (e.g., "12", "13.5").
    - Bars: expressed as width in cm (e.g., "52cm" or "42-45") & sometimes in letters like S/M/L.
    - Twin tip boards: length x width in cm (e.g., "138x42"). Often just the length (e.g., "138"). Keep the original format
    - Surfboards and foil boards: feet and inches (e.g., "5'2\"") and/or volume in liters (e.g., "23L"). Foilboards sometimes length x width Keep the original format
    - Wetsuits: garment size + thickness (e.g., "M 4/3", "L 3/2")
    - Harnesses: garment size (e.g., "M", "L")

    FULL GEAR DETECTION:
    When the user mentions renting "complete gear", "full gear", "equipo completo", "equipo de kite completo",
    or similar phrases meaning they offer ALL types of kite equipment as a package:
    - Set offers_full_gear to true
    - Set needs_clarification to false
    - Leave gear as an empty array
    Do NOT ask for individual item details in this case — the user is saying they rent everything.

    Important rules:
    1. The "gear" field must be an array of zero or more gear objects
    2. For each gear item, the "model" normally does not contain a number — that would be the size
    3. Skip gear fields when empty/unknown (set them to null)
    4. When needs_clarification is true, set "clarification_request" to a short, friendly, user-facing question in the users language asking for the missing information (e.g. "What brand and size is the kite?"). This message will be sent directly to the user, so it must be conversational, not technical.
    5. If mentioning a "bar" accompanying the kite it means the user is ALSO listing the bar as a SEPARATE gear item. Extract it as type "bar" and set its brand to the same brand as the associated kite. Year and size are not needed for bars.
    """
  end

  @doc false
  def enrich_brands_from_reference(result), do: enrich_from_reference(result)

  @doc """
  Enriches gear items with brand and gear_type from the gear_models reference table.
  """
  def enrich_from_reference(%{gear: gear} = result) do
    enriched_gear = Enum.map(gear, &enrich_item_from_reference/1)
    %{result | gear: enriched_gear}
  end

  defp enrich_item_from_reference(%{model: model} = item) when is_binary(model) and model != "" do
    case Kite4rent.Rental.lookup_model_info(model) do
      {:ok, %{brand: brand, gear_type: gear_type}} ->
        item
        |> maybe_set_brand(brand)
        |> maybe_set_type(gear_type)

      {:ambiguous, _brands} ->
        item

      :not_found ->
        item
    end
  end

  defp enrich_item_from_reference(item), do: item

  # Brand from reference table is ground truth — always overwrite
  defp maybe_set_brand(item, brand), do: %{item | brand: brand}

  defp maybe_set_type(item, gear_type) do
    if item.type in [nil, "", "other"], do: %{item | type: gear_type}, else: item
  end

  # If a bar has no brand but kites in the same extraction do, copy the kite brand.
  defp infer_bar_brand_from_kites(%{gear: gear} = result) do
    kite_brand =
      gear
      |> Enum.find_value(fn
        %{type: "kite", brand: brand} when is_binary(brand) and brand != "" -> brand
        _ -> nil
      end)

    if kite_brand do
      updated_gear =
        Enum.map(gear, fn
          %{type: "bar", brand: brand} = item when is_nil(brand) or brand == "" ->
            %{item | brand: kite_brand}

          item ->
            item
        end)

      %{result | gear: updated_gear}
    else
      result
    end
  end

  # After enrichment, clear clarification if enrichment resolved all missing brands.
  # Compare pre-enrichment (sanitized) and post-enrichment to detect if brands were filled.
  defp maybe_clear_clarification(
         %{needs_clarification: true, gear: before_gear},
         %{needs_clarification: true, gear: after_gear} = enriched
       ) do
    # Check if enrichment actually filled in any nil brands
    brands_were_filled =
      Enum.zip(before_gear, after_gear)
      |> Enum.any?(fn {before, after_item} ->
        (is_nil(before.brand) or before.brand == "") and
          is_binary(after_item.brand) and after_item.brand != ""
      end)

    # Only clear if brands were filled AND no brands are still missing
    still_missing_brand? =
      Enum.any?(after_gear, fn item -> is_nil(item.brand) or item.brand == "" end)

    if brands_were_filled and not still_missing_brand? do
      %{enriched | needs_clarification: false, clarification_request: nil}
    else
      enriched
    end
  end

  defp maybe_clear_clarification(_sanitized, enriched), do: enriched

  defp sanitize_result(%GearExtraction{} = result) do
    sanitized_gear = Enum.map(result.gear, &sanitize_gear_item/1)

    %{
      gear: sanitized_gear,
      extraction_confidence: result.extraction_confidence,
      needs_clarification: result.needs_clarification,
      clarification_request: result.clarification_request,
      offers_full_gear: result.offers_full_gear
    }
  end

  defp sanitize_gear_item(item) do
    %{
      type: sanitize_gear_type(item.type),
      brand: sanitize_brand(item.brand),
      model: sanitize_model(item.model),
      size: sanitize_size(item.size),
      year: sanitize_year(item.year),
      gender: sanitize_gender(item.gender),
      condition: sanitize_condition(item.condition)
    }
  end

  defp sanitize_gear_type(type) when is_binary(type) do
    normalized = String.downcase(String.trim(type))

    case normalized do
      t
      when t in ["kite", "board", "harness", "bar", "wetsuit", "pump", "leash", "helmet", "vest"] ->
        t

      x ->
        Logger.warning("Unexpected gear type to sanitize: #{x}")
        "other"
    end
  end

  defp sanitize_gear_type(_), do: "other"

  defp sanitize_brand(brand) when is_binary(brand) do
    normalized = String.trim(brand)

    case String.downcase(normalized) do
      "null" -> nil
      b when b in ["north", "north kiteboarding"] -> "North"
      b when b in ["duotone"] -> "Duotone"
      b when b in ["ozone"] -> "Ozone"
      b when b in ["cabrinha"] -> "Cabrinha"
      b when b in ["f-one", "fone"] -> "F-One"
      _ -> String.trim(normalized)
    end
  end

  defp sanitize_brand(_), do: nil

  defp sanitize_model(model) when is_binary(model) do
    trimmed = String.trim(model)
    if String.downcase(trimmed) == "null", do: nil, else: trimmed
  end

  defp sanitize_model(_), do: nil

  defp sanitize_size(size) when is_binary(size) do
    cleaned = String.trim(size)

    if String.downcase(cleaned) == "null" do
      nil
    else
      # Normalize wetsuit thickness notation: "4.3" or "4,3" -> "4/3"
      cleaned = normalize_wetsuit_thickness(cleaned)

      # Normalize German "qm" (Quadratmeter) to just the number: "12qm" -> "12"
      cleaned = Regex.replace(~r/^(\d+)\s*qm$/i, cleaned, "\\1")

      cond do
        Regex.match?(~r/^\d+$/, cleaned) ->
          case String.to_integer(cleaned) do
            s when s >= 6 and s <= 20 -> "#{s}m"
            s when s >= 120 and s <= 180 -> "#{s}cm"
            _ -> cleaned
          end

        String.contains?(cleaned, ["m", "cm", "\"", "'"]) ->
          cleaned

        true ->
          cleaned
      end
    end
  end

  defp sanitize_size(_), do: nil

  # Normalize wetsuit thickness notation from "4.3" or "4,3" to "4/3"
  defp normalize_wetsuit_thickness(size) when is_binary(size) do
    # Replace patterns like "4.3" or "4,3" with "4/3" (wetsuit thickness notation)
    size
    |> String.replace(~r/(\d)[.,](\d)/, "\\1/\\2")
  end

  defp normalize_wetsuit_thickness(size), do: size

  defp sanitize_year(year) when is_binary(year) do
    case Integer.parse(year) do
      {y, ""} when y >= 2010 and y <= 2030 -> Integer.to_string(y)
      _ -> nil
    end
  end

  defp sanitize_year(year) when is_integer(year) and year >= 2010 and year <= 2030 do
    Integer.to_string(year)
  end

  defp sanitize_year(_), do: nil

  defp sanitize_gender(gender) when is_binary(gender) do
    normalized = String.downcase(String.trim(gender))

    case normalized do
      g when g in ["m", "male", "masculino", "hombre", "man"] -> "M"
      g when g in ["f", "female", "femenino", "mujer", "woman"] -> "F"
      _ -> nil
    end
  end

  defp sanitize_gender(_), do: nil

  defp sanitize_condition(condition) when is_binary(condition) do
    trimmed = String.trim(condition)
    if String.downcase(trimmed) == "null", do: nil, else: trimmed
  end

  defp sanitize_condition(_), do: nil
end
