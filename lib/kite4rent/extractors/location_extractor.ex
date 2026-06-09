defmodule Kite4rent.Extractors.LocationExtractor do
  @moduledoc """
  Extracts and validates location information from user messages using InstructorLite
  for schema-driven structured outputs with automatic validation and retries.
  """

  require Logger
  alias Kite4rent.Extractors.LocationExtraction

  @doc """
  Extract location information from a user message.

  Returns:
  - `{:ok, %{location: name, confidence: float}}` on success
  - `{:ok, %{location: nil, confidence: 0.0}}` when no location found
  - `{:error, type, message}` on extraction failure
  """
  def extract(message, _opts \\ []) do
    system_prompt = build_location_prompt()

    params = %{
      messages: [
        %{role: "system", content: system_prompt},
        %{role: "user", content: message}
      ]
    }

    case Kite4rent.LLM.instruct(params, response_model: LocationExtraction, max_retries: 1) do
      {:ok, %LocationExtraction{} = result} ->
        Logger.info("Location extracted successfully",
          extra: %{
            location: result.location,
            confidence: result.confidence
          }
        )

        {:ok, Map.from_struct(result)}

      {:error, reason} ->
        Logger.error("Location extraction failed",
          error: :location_extraction_error,
          reason: inspect(reason),
          message_length: String.length(message)
        )

        {:error, :location_extraction_error, "Location extraction failed"}
    end
  end

  defp build_location_prompt do
    """
    You are a location extractor for a kitesurfing gear rental marketplace.
    Extract specific location names from the user message, focusing on real places that exist.

    IMPORTANT: Common phrases that are NOT real locations:
    - "around here" / "over here" / "por aqui" / "por ahi" (NOT a location)
    - "nearby" / "close by" / "cerca" / "cerquita" (NOT a location)
    - "here" / "there" / "aqui" / "ahi" (NOT a location)
    - "in the area" / "en la zona" (NOT a location)

    Your job:
    1. Identify if the message mentions a SPECIFIC, REAL location (city, beach, spot name)
    2. Ignore vague phrases like "around here", "nearby", "por aqui"
    3. Return confidence based on how specific the location mention is

    Examples:
    - "en Tarifa" → location="Tarifa", confidence=0.9
    - "por aqui" → location=null, confidence=0.0
    - "cerca de Madrid" → location="Madrid", confidence=0.7
    - "I have a kite" → location=null, confidence=0.0
    """
  end
end
