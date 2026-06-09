defmodule Kite4rent.MessageCoordinator do
  @moduledoc """
  Coordinates the processing of user messages using separated extractors.

  Uses focused extractors (IntentClassifier, LocationExtractor, GearExtractor, DepositExtractor)
  to process messages with multi-step prompting for better accuracy.
  """

  require Logger
  alias Kite4rent.Extractors.IntentClassifier
  alias Kite4rent.Extractors.LocationExtractor
  alias Kite4rent.Extractors.GearExtractor
  alias Kite4rent.Extractors.DepositExtractor
  alias Kite4rent.Intentions
  alias Kite4rent.Messages.LLMResponse

  @offer_gear Intentions.offer_gear()
  @request_gear Intentions.request_gear()
  @check_availability Intentions.check_availability()
  @list_own_inventory Intentions.list_own_inventory()
  @request_security_deposit Intentions.request_security_deposit()

  @doc """
  Process text using the extractor architecture.

  Returns {:ok, %LLMResponse{}} on success, {:error, reason} on failure.
  """
  def process_text(text, opts \\ []) do
    use_location_extractor = get_feature_flag(opts, :use_location_extractor, true)
    use_gear_extractor = get_feature_flag(opts, :use_gear_extractor, true)

    process_with_extractors(text, opts, %{
      location_extractor: use_location_extractor,
      gear_extractor: use_gear_extractor
    })
  end

  # Process using the new extractor architecture
  defp process_with_extractors(text, opts, extractor_flags) do
    try do
      # Step 1: Always classify intent first
      is_audio = Keyword.get(opts, :language) != nil
      conversation_history = Keyword.get(opts, :conversation_history, [])

      # Build opts for intent classification, only including provider/model if explicitly set
      # Include conversation_history for confirmation/negation/follow-up detection
      classifier_opts =
        [is_audio_transcription: is_audio, conversation_history: conversation_history]
        |> build_extractor_opts(opts)

      case IntentClassifier.classify(text, classifier_opts) do
        {:ok, classification} ->
          # Step 2: Based on intent, decide what to extract in parallel
          case classification.intent do
            intent when intent in [@offer_gear, @request_gear] ->
              extract_entities_for_gear_intent(text, classification, opts, extractor_flags)

            @list_own_inventory ->
              # This intent doesn't need entity extraction
              build_response_from_classification(classification, %{
                gear: [],
                location: nil
              })

            @request_security_deposit ->
              # Extract deposit amount and currency
              extract_entities_for_deposit_intent(text, classification, opts)

            @check_availability ->
              # Extract location only (user might ask "where in Spain?" or just "where?")
              extract_location_for_availability_intent(
                text,
                classification,
                opts,
                extractor_flags
              )

            _ ->
              # All other intents (including "other") - no entity extraction needed
              # Will be handled by ChatHandler or DefaultHandler
              build_response_from_classification(classification, %{
                gear: [],
                location: nil
              })
          end

        {:error, _type, _message} = error ->
          error
      end
    rescue
      exception ->
        Logger.error("Exception in message coordination",
          error: :message_coordination_exception,
          exception: inspect(exception)
        )

        reraise exception, __STACKTRACE__
    end
  end

  # Extract entities for gear-related intents (offer_gear, request_gear)
  defp extract_entities_for_gear_intent(text, classification, opts, extractor_flags) do
    # Run extractions in parallel when enabled

    # Check if LLM already provided location (e.g., from context for confirmations)
    # If so, use it directly; otherwise extract from the current message
    location_from_classification =
      case Map.get(classification, :location) do
        "null" -> nil
        "" -> nil
        val -> val
      end

    location_task =
      if location_from_classification do
        # LLM already resolved location from context - no need to extract
        Logger.info("Using location from classification: #{location_from_classification}")
        nil
      else
        # Location extraction task (if enabled and no location from classification)
        if extractor_flags.location_extractor do
          Task.async(fn ->
            location_opts = build_extractor_opts([language: classification.language], opts)

            case LocationExtractor.extract(text, location_opts) do
              {:ok, location_result} ->
                # Return location name or nil, maintaining compatibility
                # Don't use low-confidence locations
                location =
                  if location_result.confidence < 0.5 do
                    nil
                  else
                    location_result.location
                  end

                {:location, location}

              {:error, _type, reason} ->
                # No fallback to legacy - log and return nil
                Logger.warning("Location extraction failed: #{inspect(reason)}")
                {:location, nil}
            end
          end)
        else
          nil
        end
      end

    # Gear extraction task (if enabled)
    # NOTE: We intentionally DO NOT pass conversation_history to GearExtractor.
    # The extractor should only extract gear from the current message, not from
    # conversation context (which might include gear listings from oneself or
    # other users).
    gear_task =
      if extractor_flags.gear_extractor and classification.intent != @request_gear do
        Task.async(fn ->
          gear_opts = [
            is_audio?: Keyword.get(opts, :is_audio?),
            language: classification.language,
            intent: classification.intent
          ]

          case GearExtractor.extract(text, gear_opts) do
            {:ok, gear_result} ->
              cond do
                Map.get(gear_result, :offers_full_gear) == true ->
                  {:offers_full_gear, true}

                gear_result.needs_clarification and is_binary(gear_result.clarification_request) and
                    gear_result.clarification_request != "" ->
                  {:gear_clarification, gear_result.clarification_request}

                true ->
                  # Convert to legacy format for compatibility
                  gear_list =
                    Enum.map(gear_result.gear, fn item ->
                      %{
                        "type" => item.type,
                        "brand" => item.brand,
                        "model" => item.model,
                        "size" => item.size,
                        "year" => item.year,
                        "condition" => item.condition
                      }
                    end)

                  {:gear, gear_list}
              end

            {:error, _type, reason} ->
              Logger.warning("Gear extraction failed: #{inspect(reason)}")
              {:gear, []}
          end
        end)
      else
        nil
      end

    # Collect results from async tasks
    results =
      [location_task, gear_task]
      |> Enum.reject(&is_nil/1)
      # 5 second timeout
      |> Task.await_many(5000)
      |> Enum.into(%{})

    # Route based on gear extraction result
    cond do
      Map.get(results, :offers_full_gear) ->
        # User offers complete gear — no individual items needed
        entities = %{
          location: location_from_classification || Map.get(results, :location),
          gear: [],
          offers_full_gear: true
        }

        build_response_from_classification(classification, entities)

      clarification_request = Map.get(results, :gear_clarification) ->
        # Gear needs more details — return a special LLMResponse that bypasses normal handling
        {:ok,
         %LLMResponse{
           intention: classification.intent,
           intent_confidence: classification.intent_confidence,
           doubt_asked_likelihood: classification.doubt_asked_likelihood,
           language: classification.language,
           location: location_from_classification || Map.get(results, :location),
           gear_clarification: clarification_request,
           is_school: Map.get(classification, :is_school)
         }}

      true ->
        # Normal flow — merge results and build response
        entities = %{
          location: location_from_classification || Map.get(results, :location),
          gear: Map.get(results, :gear, [])
        }

        build_response_from_classification(classification, entities)
    end
  end

  # Extract location for check_availability intent
  defp extract_location_for_availability_intent(text, classification, opts, extractor_flags) do
    if extractor_flags.location_extractor do
      location_opts = build_extractor_opts([language: classification.language], opts)

      location =
        case LocationExtractor.extract(text, location_opts) do
          {:ok, location_result} ->
            # Accept location with reasonable confidence
            if location_result.confidence >= 0.5 do
              location_result.location
            else
              nil
            end

          {:error, _type, reason} ->
            Logger.warning("Location extraction for availability failed: #{inspect(reason)}")
            nil
        end

      build_response_from_classification(classification, %{
        gear: [],
        location: location
      })
    else
      # No location extractor enabled, return with nil location
      build_response_from_classification(classification, %{
        gear: [],
        location: nil
      })
    end
  end

  # Extract entities for security deposit intent
  defp extract_entities_for_deposit_intent(text, classification, opts) do
    deposit_opts = build_extractor_opts([language: classification.language], opts)

    case DepositExtractor.extract(text, deposit_opts) do
      {:ok, deposit_result} ->
        entities = %{
          gear: [],
          location: nil,
          security_deposit: deposit_result
        }

        build_response_from_classification(classification, entities)

      {:error, _type, reason} ->
        Logger.warning("Deposit extraction failed: #{inspect(reason)}")

        # Return with nil deposit so the handler can ask for clarification
        entities = %{
          gear: [],
          location: nil,
          security_deposit: nil
        }

        build_response_from_classification(classification, entities)
    end
  end

  # Build LLMResponse from classification and extracted entities
  defp build_response_from_classification(classification, entities) do
    response = %LLMResponse{
      intention: classification.intent,
      intent_confidence: classification.intent_confidence,
      doubt_asked_likelihood: classification.doubt_asked_likelihood,
      language: classification.language,
      location: entities.location,
      gear: entities.gear,
      location_radius_km: nil,
      security_deposit: Map.get(entities, :security_deposit),
      is_school: Map.get(classification, :is_school),
      offers_full_gear: Map.get(entities, :offers_full_gear)
    }

    {:ok, response}
  end

  # Helper to get feature flags with defaults
  defp get_feature_flag(opts, flag_name, default) do
    feature_flags = Keyword.get(opts, :feature_flags, %{})
    Map.get(feature_flags, flag_name, default)
  end

  # Helper to build extractor opts, only including provider/model if explicitly set
  # This prevents blocking fallback logic in LLMProcessor when provider is nil
  #
  # NOTE: We intentionally DO NOT pass conversation_history to extractors.
  # Extractors (IntentClassifier, LocationExtractor, GearExtractor, DepositExtractor)
  # should only analyze the CURRENT message to avoid "context bleeding" where
  # information from previous messages incorrectly influences extraction results.
  # Only ChatHandler and similar handlers should use conversation history.
  defp build_extractor_opts(base_opts, source_opts) do
    base_opts
    |> maybe_put_opt(:provider, source_opts)
    |> maybe_put_opt(:model, source_opts)
  end

  defp maybe_put_opt(opts, key, source_opts) do
    case Keyword.get(source_opts, key) do
      nil -> opts
      value -> Keyword.put(opts, key, value)
    end
  end
end
