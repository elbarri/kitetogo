defmodule Kite4rent.Extractors.IntentClassifier do
  @moduledoc """
  Classifies user intent and language from messages using InstructorLite for
  schema-driven structured outputs with automatic validation and retries.
  """

  require Logger
  alias Kite4rent.Extractors.IntentClassification

  @doc """
  Classify the intent and language of a user message.

  Returns:
  - `{:ok, result}` where result is a map with intent, intent_confidence, language, location
  - `{:error, type, message}` if classification fails
  """
  def classify(message, opts \\ []) do
    is_audio = Keyword.get(opts, :is_audio_transcription, false)
    conversation_history = Keyword.get(opts, :conversation_history, [])

    system_prompt = build_system_prompt(is_audio)
    history_messages = build_history_messages(conversation_history)

    params = %{
      messages:
        [%{role: "system", content: system_prompt}] ++
          history_messages ++
          [%{role: "user", content: message}]
    }

    case Kite4rent.LLM.instruct(params, response_model: IntentClassification, max_retries: 1) do
      {:ok, %IntentClassification{} = result} ->
        Logger.info("Intent classified: #{result.intent}",
          extra: %{
            intent: result.intent,
            confidence: result.intent_confidence,
            language: result.language
          }
        )

        {:ok, Map.from_struct(result)}

      {:error, reason} ->
        Logger.error("Intent classification failed: #{inspect(reason)} (message_length: #{String.length(message)})",
          error: :intent_classification_error
        )

        {:error, :intent_classification_error, "Intent classification failed"}
    end
  end

  @doc """
  Builds the system prompt for intent classification.
  Public for debugging/testing purposes (e.g. mix test_llm --print-prompt).
  """
  def build_system_prompt(is_audio, conversation_history \\ []) do
    audio_context =
      if is_audio do
        "Note: This message is from audio transcription, so brand names might have spelling errors."
      else
        ""
      end

    history_note =
      if length(conversation_history) > 0 do
        "The conversation history is provided as prior messages for context."
      else
        ""
      end

    """
    You are a classifier for a p2p kitesurfing gear rental marketplace (WhatsApp).
    #{history_note}
    #{audio_context}
    INTENTS:
    - offer_gear: Publish gear for rent
    - request_gear: Rent gear in a location
    - list_own_inventory: SEE/VIEW their listings
    - edit_gear: Edit, change, or DELETE gear items (specific items OR all). Examples: "borrame el kite de 12m", "borra todo mi equipo", "cambiar marca"
    - request_security_deposit: Request a security deposit
    - check_availability: WHERE gear is available (country/region level)
    - feedback: Feedback about the service
    - other: ONLY greetings, off-topic, or truly unclear messages

    Be action-oriented. Prefer actionable intents over "other".

    AMBIGUITY between offer_gear and request_gear:
    Words like "alquilar", "rentar", "rent" are inherently ambiguous — they can mean PUBLISH gear or FIND gear.
    - Clear offer signals: "tengo", "mi kite", "publico", "pongo en alquiler" → high confidence offer_gear
    - Clear request signals: "busco", "necesito", "donde hay", "looking for" → high confidence request_gear
    - Ambiguous (no ownership/seeking signal): lower intent_confidence (< 0.7) so the system can ask

    CONTEXT RULES:
    - Confirmations/follow-ups: resolve to the ACTUAL intent from context with its entities
      "si" after "¿Busco equipo en Tarifa?" → intent="request_gear", location="Tarifa"
    - New actions: extract entities ONLY from current message, don't inherit from context
      Searched Barcelona, now "quiero publicar mi kite" → intent="offer_gear", location=null

    LABELS (independent of intent — extract from any message):
    - is_school: true if the user identifies as a kite school, surf school, or kitesurfing school.
      Signals: "soy/somos una escuela", "kite school", "we are a school", "escuela de kite"
    This label is orthogonal to intent. A school saying "alquilo equipo en Tarifa" is offer_gear intent WITH is_school=true.

    DOUBT DETECTION (doubt_asked_likelihood):
    Orthogonal to intent. Measures whether the user wants the system to ACT vs wants to UNDERSTAND.
    Key distinction: "do it / tell me the data" (low) vs "can I? / how do I?" (high).

    - Low (<0.3) — user wants the system to EXECUTE or FETCH data, even if phrased as question:
      "quiero alquilar un kite en Tarifa", "borra mi anuncio", "busco kite 12m"
      "donde puedo alquilar?", "que hay en Argentina?", "que hay ahi?", "en que paises hay equipo?"
      "si" (confirming a previous action), "cualquier pais", "dale"
    - High (>0.7) — user is asking about HOW things work, questioning results, or unsure if feature exists:
      "cómo hago para publicar?", "se puede alquilar acá?", "y chaleco no tiene?"
      "tiene tabla core?", "eso incluye neopreno?", "cómo funciona el depósito?"
    """
  end

  @doc """
  Converts conversation history entries into structured message maps for the LLM.
  Metadata annotations are appended to the content text.
  """
  def build_history_messages(conversation_history) do
    Enum.map(conversation_history, fn msg ->
      role = msg[:role] || msg["role"]
      content = msg[:content] || msg["content"]

      metadata = build_metadata(msg)
      annotated_content = if metadata != "", do: "#{content} [#{metadata}]", else: content

      %{role: role, content: annotated_content}
    end)
  end

  defp build_metadata(msg) do
    [
      if(msg[:detected_intent], do: "intent: #{msg[:detected_intent]}"),
      if(msg[:showed_search_results], do: "showed_results: true"),
      if(msg[:asked_confirmation], do: "asked_question: true"),
      if(msg[:shared_location], do: "shared_location: true")
    ]
    |> Enum.filter(& &1)
    |> Enum.join(", ")
  end

  @doc """
  Get supported intents list.
  """
  def supported_intents, do: IntentClassification.supported_intents()
end
