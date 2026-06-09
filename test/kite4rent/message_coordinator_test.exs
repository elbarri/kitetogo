defmodule Kite4rent.MessageCoordinatorTest do
  use ExUnit.Case, async: false
  use Mimic
  alias Kite4rent.MessageCoordinator

  setup :verify_on_exit!

  setup do
    :ok
  end

  describe "process_text/2" do
    test "uses intent classifier when feature flag enabled" do
      message = "Hello world"

      # Mock IntentClassifier
      mock_classification = %{
        intent: "other",
        intent_confidence: 0.9,
        doubt_asked_likelihood: 0.1,
        language: "en",
        security_deposit: nil
      }

      expect(Kite4rent.Extractors.IntentClassifier, :classify, fn ^message, _opts ->
        {:ok, mock_classification}
      end)

      result =
        MessageCoordinator.process_text(message,
          feature_flags: %{use_intent_classifier: true},
          provider: :openrouter,
          model: "meta-llama/llama-3.3-70b-instruct:free"
        )

      # Should return LLMResponse format for backward compatibility
      assert {:ok, response} = result
      assert response.intention == "other"
      assert response.language == "en"
    end

    # Note: Legacy fallback to LLMProcessor.process_text/2 has been removed
    # The MessageCoordinator now always uses IntentClassifier
    test "always uses intent classifier (feature flag ignored)" do
      message = "Hello world"

      mock_classification = %{
        intent: "other",
        intent_confidence: 0.9,
        doubt_asked_likelihood: 0.1,
        language: "en",
        security_deposit: nil
      }

      expect(Kite4rent.Extractors.IntentClassifier, :classify, fn ^message, _opts ->
        {:ok, mock_classification}
      end)

      result =
        MessageCoordinator.process_text(message,
          feature_flags: %{use_intent_classifier: false}
        )

      # Should still use IntentClassifier regardless of flag
      assert {:ok, response} = result
      assert response.intention == "other"
    end

    test "handles gear intent with parallel extraction flags" do
      message = "Tengo un North Reach 11 para alquilar en Tarifa"

      # Mock IntentClassifier
      mock_classification = %{
        intent: "offer_gear",
        intent_confidence: 0.9,
        doubt_asked_likelihood: 0.1,
        language: "es",
        security_deposit: nil
      }

      expect(Kite4rent.Extractors.IntentClassifier, :classify, fn ^message, _opts ->
        {:ok, mock_classification}
      end)

      # Mock LocationExtractor
      mock_location_result = %{
        location: "Tarifa",
        confidence: 0.95,
        needs_clarification: false,
        reasoning: "Clear location mentioned"
      }

      expect(Kite4rent.Extractors.LocationExtractor, :extract, fn ^message, _opts ->
        {:ok, mock_location_result}
      end)

      # Mock GearExtractor
      mock_gear_result = %{
        gear: [
          %{
            type: "kite",
            brand: "North",
            model: "Reach",
            size: "11m",
            year: nil,
            condition: nil
          }
        ],
        extraction_confidence: 0.9,
        needs_clarification: false,
        clarification_request: nil
      }

      expect(Kite4rent.Extractors.GearExtractor, :extract, fn ^message, _opts ->
        {:ok, mock_gear_result}
      end)

      result =
        MessageCoordinator.process_text(message,
          feature_flags: %{
            use_intent_classifier: true,
            # Now implemented
            use_location_extractor: true,
            # Now implemented
            use_gear_extractor: true
          },
          provider: :openrouter,
          model: "meta-llama/llama-3.3-70b-instruct:free"
        )

      assert {:ok, response} = result
      assert response.intention == "offer_gear"
      assert response.language == "es"
      assert response.location == "Tarifa"

      # Should extract gear correctly
      assert length(response.gear) > 0
      gear = hd(response.gear)
      assert gear["brand"] == "North"
      assert gear["model"] == "Reach"
      assert gear["size"] == "11m"
    end

    test "backward compatibility - same interface as LLMProcessor" do
      message = "Test message"

      # Mock IntentClassifier
      mock_classification = %{
        intent: "other",
        intent_confidence: 0.9,
        doubt_asked_likelihood: 0.1,
        language: "en",
        security_deposit: nil
      }

      expect(Kite4rent.Extractors.IntentClassifier, :classify, fn ^message, _opts ->
        {:ok, mock_classification}
      end)

      # Should accept same opts as LLMProcessor.process_text/2
      result =
        MessageCoordinator.process_text(message,
          language: "en",
          feature_flags: %{
            use_intent_classifier: true,
            use_location_extractor: false,
            use_gear_extractor: false
          }
        )

      assert {:ok, _response} = result
    end

    test "handles list_own_inventory intent without entity extraction" do
      message = "Show my listings"

      # Mock IntentClassifier
      mock_classification = %{
        intent: "list_own_inventory",
        intent_confidence: 0.95,
        doubt_asked_likelihood: 0.1,
        language: "en",
        security_deposit: nil
      }

      expect(Kite4rent.Extractors.IntentClassifier, :classify, fn ^message, _opts ->
        {:ok, mock_classification}
      end)

      result =
        MessageCoordinator.process_text(message,
          feature_flags: %{
            use_intent_classifier: true,
            use_location_extractor: false,
            use_gear_extractor: false,
            use_price_extractor: false
          },
          provider: :openrouter,
          model: "meta-llama/llama-3.3-70b-instruct:free"
        )

      assert {:ok, response} = result
      assert response.intention == "list_own_inventory"
      assert response.language == "en"
      assert response.gear == []
      assert response.location == nil
      assert response.prices == nil
    end

    test "full extraction with all extractors enabled" do
      message = "Tengo un North Reach 11 para alquilar en Tarifa"

      # Mock IntentClassifier
      mock_classification = %{
        intent: "offer_gear",
        intent_confidence: 0.95,
        doubt_asked_likelihood: 0.1,
        language: "es",
        security_deposit: nil
      }

      expect(Kite4rent.Extractors.IntentClassifier, :classify, fn ^message, _opts ->
        {:ok, mock_classification}
      end)

      # Mock LocationExtractor
      mock_location_result = %{
        location: "Tarifa",
        confidence: 0.9,
        needs_clarification: false,
        reasoning: "Clear location mentioned"
      }

      expect(Kite4rent.Extractors.LocationExtractor, :extract, fn ^message, _opts ->
        {:ok, mock_location_result}
      end)

      # Mock GearExtractor
      mock_gear_result = %{
        gear: [
          %{
            type: "kite",
            brand: "North",
            model: "Reach",
            size: "11m",
            year: nil,
            condition: nil
          }
        ],
        extraction_confidence: 0.9,
        needs_clarification: false,
        clarification_request: nil
      }

      expect(Kite4rent.Extractors.GearExtractor, :extract, fn ^message, _opts ->
        {:ok, mock_gear_result}
      end)

      result =
        MessageCoordinator.process_text(message,
          feature_flags: %{
            use_intent_classifier: true,
            use_location_extractor: true,
            use_gear_extractor: true
          },
          provider: :openrouter,
          model: "meta-llama/llama-3.3-70b-instruct:free"
        )

      assert {:ok, response} = result
      assert response.intention == "offer_gear"
      assert response.language == "es"
      assert response.location == "Tarifa"

      # Verify gear extraction
      assert length(response.gear) == 1
      gear = hd(response.gear)
      assert gear["brand"] == "North"
      assert gear["model"] == "Reach"
      assert gear["size"] == "11m"
    end
  end

  describe "gear_clarification preserves is_school label" do
    test "is_school is included in gear_clarification response" do
      message = "soy una escuela de kite y tengo kites"

      mock_classification = %{
        intent: "offer_gear",
        intent_confidence: 0.9,
        doubt_asked_likelihood: 0.1,
        language: "es",
        is_school: true,
        location: nil
      }

      expect(Kite4rent.Extractors.IntentClassifier, :classify, fn ^message, _opts ->
        {:ok, mock_classification}
      end)

      expect(Kite4rent.Extractors.GearExtractor, :extract, fn ^message, _opts ->
        {:ok,
         %Kite4rent.Extractors.GearExtraction{
           gear: [],
           needs_clarification: true,
           clarification_request: "¿Qué equipo tienes?",
           extraction_confidence: 0.1
         }}
      end)

      {:ok, response} = MessageCoordinator.process_text(message)

      assert response.gear_clarification == "¿Qué equipo tienes?"
      assert response.is_school == true
    end
  end

  describe "offers_full_gear from GearExtractor" do
    test "offers_full_gear bypasses gear clarification and flows normally" do
      message = "soy una escuela de kite y alquilo equipo de kite completo"

      mock_classification = %{
        intent: "offer_gear",
        intent_confidence: 0.9,
        doubt_asked_likelihood: 0.1,
        language: "es",
        is_school: true,
        location: nil
      }

      expect(Kite4rent.Extractors.IntentClassifier, :classify, fn ^message, _opts ->
        {:ok, mock_classification}
      end)

      expect(Kite4rent.Extractors.GearExtractor, :extract, fn ^message, _opts ->
        {:ok,
         %Kite4rent.Extractors.GearExtraction{
           gear: [],
           needs_clarification: false,
           clarification_request: nil,
           extraction_confidence: 1.0,
           offers_full_gear: true
         }}
      end)

      {:ok, response} = MessageCoordinator.process_text(message)

      assert response.offers_full_gear == true
      assert response.is_school == true
      assert response.gear == []
      assert is_nil(response.gear_clarification)
    end
  end

  describe "feature flag behavior" do
    test "defaults to intent classifier enabled" do
      # When no feature flags provided, should default to using intent classifier
      message = "Test message"

      # Mock IntentClassifier directly
      mock_classification = %{
        intent: "other",
        intent_confidence: 0.9,
        doubt_asked_likelihood: 0.1,
        language: "en",
        security_deposit: nil
      }

      expect(Kite4rent.Extractors.IntentClassifier, :classify, fn ^message, _opts ->
        {:ok, mock_classification}
      end)

      result =
        MessageCoordinator.process_text(message,
          provider: :openrouter,
          model: "meta-llama/llama-3.3-70b-instruct:free"
        )

      assert {:ok, response} = result
      # Intent classifier should be used (no fallback to legacy)
      assert response.intention == "other"
      assert response.language == "en"
    end
  end

  describe "error handling" do
    @tag :capture_log
    test "returns error when intent classification fails" do
      message = "Test message"

      # Mock IntentClassifier to fail
      expect(Kite4rent.Extractors.IntentClassifier, :classify, fn ^message, _opts ->
        {:error, :intent_classification_error, "classification failed"}
      end)

      result =
        MessageCoordinator.process_text(message,
          feature_flags: %{
            use_intent_classifier: true
          },
          provider: :openrouter,
          model: "meta-llama/llama-3.3-70b-instruct:free"
        )

      # Should return error, no legacy fallback
      assert {:error, :intent_classification_error, _reason} = result
    end

    @tag :capture_log
    test "raises exception when message coordination raises exception" do
      message = "Test message"

      # Mock IntentClassifier to raise an exception
      expect(Kite4rent.Extractors.IntentClassifier, :classify, fn ^message, _opts ->
        raise RuntimeError, "unexpected error"
      end)

      # Should re-raise the exception (no fallback)
      assert_raise RuntimeError, "unexpected error", fn ->
        MessageCoordinator.process_text(message,
          feature_flags: %{
            use_intent_classifier: true
          },
          provider: :openrouter,
          model: "meta-llama/llama-3.3-70b-instruct:free"
        )
      end
    end
  end
end
