defmodule Kite4rent.Extractors.IntentClassifierTest do
  use ExUnit.Case, async: true
  use Mimic
  alias Kite4rent.Extractors.IntentClassifier
  alias Kite4rent.Extractors.IntentClassification

  setup :verify_on_exit!

  setup do
    :ok
  end

  describe "classify/2" do
    test "classifies gear offer correctly" do
      message = "Tengo un North Reach 11 2024 para alquilar en Tarifa"

      expect(Kite4rent.LLM, :instruct, fn params, _opts ->
        # System prompt + user message, no history
        assert [%{role: "system"}, %{role: "user", content: ^message}] = params.messages
        {:ok, %IntentClassification{intent: "offer_gear", intent_confidence: 0.9, language: "es", location: "Tarifa"}}
      end)

      {:ok, result} =
        IntentClassifier.classify(message)

      assert result.intent == "offer_gear"
      assert result.language == "es"
      assert result.intent_confidence == 0.9
      assert result.location == "Tarifa"
    end

    test "classifies feedback message correctly" do
      message = "Great service! The kite was in perfect condition"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %IntentClassification{intent: "feedback", intent_confidence: 0.8, language: "en", location: nil}}
      end)

      {:ok, result} =
        IntentClassifier.classify(message)

      assert result.intent == "feedback"
      assert result.language == "en"
    end

    test "handles audio transcription flag" do
      message = "Tengo un kite para alquilar"

      expect(Kite4rent.LLM, :instruct, fn params, _opts ->
        system_prompt = hd(params.messages).content
        assert system_prompt =~ "audio transcription"
        {:ok, %IntentClassification{intent: "offer_gear", intent_confidence: 0.88, language: "es", location: nil}}
      end)

      {:ok, result} =
        IntentClassifier.classify(message,
          is_audio_transcription: true
        )

      assert result.intent == "offer_gear"
      assert result.intent_confidence == 0.88
    end

    test "handles unknown intent gracefully" do
      message = "What's the weather like today?"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %IntentClassification{intent: "other", intent_confidence: 0.75, language: "en", location: nil}}
      end)

      {:ok, result} =
        IntentClassifier.classify(message)

      assert result.intent == "other"
      assert result.intent_confidence == 0.75
      assert result.language == "en"
    end

    test "resolves confirmation to actual intent with location from context" do
      message = "si"

      conversation_history = [
        %{role: "user", content: "hay equipo en Tarifa?", detected_intent: "check_availability"},
        %{role: "assistant", content: "Tarifa es una ubicación. ¿Querés que busque equipo disponible?", asked_confirmation: true}
      ]

      expect(Kite4rent.LLM, :instruct, fn params, _opts ->
        # Should have system + 2 history messages + user message
        assert [
          %{role: "system"},
          %{role: "user", content: history_user},
          %{role: "assistant", content: history_assistant},
          %{role: "user", content: "si"}
        ] = params.messages

        assert history_user =~ "hay equipo en Tarifa?"
        assert history_user =~ "intent: check_availability"
        assert history_assistant =~ "asked_question: true"

        {:ok, %IntentClassification{intent: "request_gear", intent_confidence: 0.95, language: "es", location: "Tarifa"}}
      end)

      {:ok, result} =
        IntentClassifier.classify(message, conversation_history: conversation_history)

      assert result.intent == "request_gear"
      assert result.location == "Tarifa"
    end

    test "resolves negation to other intent" do
      message = "no"

      conversation_history = [
        %{role: "user", content: "hay equipo en Barcelona?"},
        %{role: "assistant", content: "¿Querés que busque equipo disponible en Barcelona?", asked_confirmation: true}
      ]

      expect(Kite4rent.LLM, :instruct, fn params, _opts ->
        # 4 messages: system + 2 history + user
        assert length(params.messages) == 4
        {:ok, %IntentClassification{intent: "other", intent_confidence: 0.9, language: "es", location: nil}}
      end)

      {:ok, result} =
        IntentClassifier.classify(message, conversation_history: conversation_history)

      assert result.intent == "other"
    end

    test "prevents context bleeding for new intents" do
      message = "quiero publicar mi kite duotone"

      conversation_history = [
        %{role: "user", content: "busco equipo en Barcelona", detected_intent: "request_gear"},
        %{role: "assistant", content: "Encontré 3 usuarios con equipo en Barcelona...", showed_search_results: true}
      ]

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %IntentClassification{intent: "offer_gear", intent_confidence: 0.92, language: "es", location: nil}}
      end)

      {:ok, result} =
        IntentClassifier.classify(message, conversation_history: conversation_history)

      assert result.intent == "offer_gear"
      assert result.location == nil
    end

    test "includes shared location metadata in history messages" do
      message = "si, ahi"

      conversation_history = [
        %{role: "user", content: "[User shared location: Tarifa Beach, Cádiz]", shared_location: true},
        %{role: "assistant", content: "¿Querés que busque equipo cerca de Tarifa?", asked_confirmation: true}
      ]

      expect(Kite4rent.LLM, :instruct, fn params, _opts ->
        [_system, location_msg, _assistant, _user] = params.messages
        assert location_msg.content =~ "shared_location: true"
        {:ok, %IntentClassification{intent: "request_gear", intent_confidence: 0.9, language: "es", location: "Tarifa"}}
      end)

      {:ok, result} =
        IntentClassifier.classify(message, conversation_history: conversation_history)

      assert result.intent == "request_gear"
      assert result.location == "Tarifa"
    end
  end

  describe "supported_intents/0" do
    test "returns expected intents" do
      intents = IntentClassifier.supported_intents()

      assert "offer_gear" in intents
      assert "request_gear" in intents
      assert "list_own_inventory" in intents
      assert "feedback" in intents
      refute "confirmation" in intents
      refute "negation" in intents
    end
  end
end
