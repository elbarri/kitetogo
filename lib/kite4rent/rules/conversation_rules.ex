defmodule Kite4rent.Rules.ConversationRules do
  @moduledoc """
  Conversation flow rules for the Wongi Engine.
  Rules are grouped by semantic meaning/scope.
  """
  alias Wongi.Engine
  import Wongi.Engine.DSL

  @doc """
  Load all conversation rules into the engine.
  Returns the engine with rules added (immutable operation).
  """
  def load(engine) do
    engine
    |> load_consent_rules()
    |> load_reaction_rules()
    |> load_interactive_button_rules()
    |> load_deposit_button_rules()
    |> load_deposit_item_selection_rules()
    |> load_location_message_rules()
    |> load_contact_selection_rules()
    |> load_text_message_rules()
    |> load_audio_message_rules()
    |> load_list_reply_rules()
    |> load_contacts_message_rules()
  end

  # ============================================================================
  # Consent & Permission Rules
  # ============================================================================

  defp load_consent_rules(engine) do
    # Rule: Grant consent when user reacts with thumbs up to consent request
    consent_rule =
      rule(:consent_thumbs_up,
        forall: [
          # Message must be a reaction with thumbs up emoji
          has(var(:msg), :type, "reaction"),
          has(var(:msg), :emoji, "👍"),
          # Context: reacting to a consent request message
          has(var(:context), :reacted_message_type, "text"),
          has(var(:context), :reacted_message_intent, "contact_sharing_consent_request"),
          has(var(:context), :reacted_message_is_incoming, false),
          # User doesn't have consent yet
          has(var(:user), :has_consent, false)
        ],
        do: [
          # Generate action to grant consent
          gen(var(:action), :action_type, :grant_consent),
          gen(var(:action), :priority, 100)
        ]
      )

    Engine.compile(engine, consent_rule)
  end

  # ============================================================================
  # Reaction Handling Rules
  # ============================================================================

  defp load_reaction_rules(engine) do
    # Rule: Acknowledge reactions that don't match specific patterns
    fallback_rule =
      rule(:reaction_acknowledge_fallback,
        forall: [
          has(var(:msg), :type, "reaction"),
          # This rule has lowest priority - only fires if no other reaction rule matches
          neg(var(:action), :action_type, :grant_consent)
        ],
        do: [
          gen(var(:action), :action_type, :acknowledge_reaction),
          gen(var(:action), :priority, 1)
        ]
      )

    Engine.compile(engine, fallback_rule)
  end

  # ============================================================================
  # Interactive Button Rules
  # ============================================================================

  defp load_interactive_button_rules(engine) do
    # Rule: Find gear around here button
    find_gear_rule =
      rule(:find_gear_around_here_button,
        forall: [
          has(var(:msg), :type, "interactive"),
          has(var(:msg), :button_id, "find_gear_around_here"),
          has(var(:context), :has_location, true),
          has(var(:context), :location, var(:location))
        ],
        do: [
          gen(var(:action), :action_type, :find_gear_around_location),
          gen(var(:action), :location, var(:location)),
          gen(var(:action), :priority, 80)
        ]
      )

    # Rule: Update my location button
    update_location_rule =
      rule(:update_my_location_button,
        forall: [
          has(var(:msg), :type, "interactive"),
          has(var(:msg), :button_id, "update_my_location"),
          has(var(:context), :has_location, true),
          has(var(:context), :location, var(:location))
        ],
        do: [
          gen(var(:action), :action_type, :update_user_location),
          gen(var(:action), :location, var(:location)),
          gen(var(:action), :priority, 80)
        ]
      )

    # Rule: Search in closest location button
    search_in_closest_location_rule =
      rule(:search_in_closest_location_button,
        forall: [
          has(var(:msg), :type, "interactive"),
          has(var(:msg), :button_id, "search_in_closest_location"),
          has(var(:context), :has_closest_location, true),
          has(var(:context), :closest_location, var(:closest_location))
        ],
        do: [
          gen(var(:action), :action_type, :search_in_closest_location),
          gen(var(:action), :closest_location, var(:closest_location)),
          gen(var(:action), :priority, 80)
        ]
      )

    engine
    |> Engine.compile(find_gear_rule)
    |> Engine.compile(update_location_rule)
    |> Engine.compile(search_in_closest_location_rule)
  end

  # ============================================================================
  # Deposit Button Rules (Duration Selection & Renter Confirmation)
  # ============================================================================

  defp load_deposit_button_rules(engine) do
    # Rule: Owner releases deposit
    owner_release_deposit_rule =
      rule(:deposit_owner_release,
        forall: [
          has(var(:msg), :type, "interactive"),
          has(var(:msg), :button_id, "deposit_release"),
          has(var(:context), :authorized_deposit_id, var(:deposit_id))
        ],
        do: [
          gen(var(:action), :action_type, :release_deposit),
          gen(var(:action), :deposit_id, var(:deposit_id)),
          gen(var(:action), :priority, 95)
        ]
      )

    # Rule: Either party initiates a dispute
    deposit_dispute_rule =
      rule(:deposit_initiate_dispute,
        forall: [
          has(var(:msg), :type, "interactive"),
          has(var(:msg), :button_id, "deposit_dispute"),
          has(var(:context), :authorized_deposit_id, var(:deposit_id)),
          has(var(:context), :dispute_initiator, var(:initiator))
        ],
        do: [
          gen(var(:action), :action_type, :initiate_dispute),
          gen(var(:action), :deposit_id, var(:deposit_id)),
          gen(var(:action), :initiator_role, var(:initiator)),
          gen(var(:action), :priority, 95)
        ]
      )

    # Rule: Renter confirms return is OK
    deposit_return_ok_rule =
      rule(:deposit_confirm_return_ok,
        forall: [
          has(var(:msg), :type, "interactive"),
          has(var(:msg), :button_id, "deposit_return_ok"),
          has(var(:context), :authorized_deposit_id, var(:deposit_id))
        ],
        do: [
          gen(var(:action), :action_type, :confirm_return_ok),
          gen(var(:action), :deposit_id, var(:deposit_id)),
          gen(var(:action), :priority, 95)
        ]
      )

    engine
    |> Engine.compile(owner_release_deposit_rule)
    |> Engine.compile(deposit_dispute_rule)
    |> Engine.compile(deposit_return_ok_rule)
  end

  # ============================================================================
  # Deposit Item Selection Rules (Gear selection for deposits)
  # ============================================================================

  defp load_deposit_item_selection_rules(engine) do
    # Note: Gear selection from list is handled via the conversation flow mechanism
    # in maybe_handle_conversation_flow, not through rules. This is because the filter
    # function can't evaluate Var structs at compile time.

    # Rule: Add more items - Yes button
    deposit_add_more_yes_rule =
      rule(:deposit_add_more_yes,
        forall: [
          has(var(:msg), :type, "interactive"),
          has(var(:msg), :button_id, "deposit_add_more_yes")
        ],
        do: [
          gen(var(:action), :action_type, :deposit_add_more_item),
          gen(var(:action), :priority, 90)
        ]
      )

    # Rule: Add more items - No button (proceed to duration)
    deposit_add_more_no_rule =
      rule(:deposit_add_more_no,
        forall: [
          has(var(:msg), :type, "interactive"),
          has(var(:msg), :button_id, "deposit_add_more_no")
        ],
        do: [
          gen(var(:action), :action_type, :deposit_proceed_to_duration),
          gen(var(:action), :priority, 90)
        ]
      )

    # Note: Duration is now entered as text (hours 2-72), handled in message_processor.ex
    # via the deposit_item_selection flow's :awaiting_duration step

    engine
    |> Engine.compile(deposit_add_more_yes_rule)
    |> Engine.compile(deposit_add_more_no_rule)
  end

  # ============================================================================
  # Location Message Rules
  # ============================================================================

  defp load_location_message_rules(engine) do
    contextual_location_rule =
      rule(:location_message_with_context,
        forall: [
          has(var(:msg), :type, "location"),
          has(var(:msg), :has_coordinates, true),
          has(var(:msg), :location, var(:location)),
          has(var(:context), :has_llm_response, true),
          has(var(:context), :llm_response, var(:llm_response))
        ],
        do: [
          gen(var(:action), :action_type, :update_location_and_act_on_intention),
          gen(var(:action), :location, var(:location)),
          gen(var(:action), :llm_response, var(:llm_response)),
          gen(var(:action), :priority, 90)
        ]
      )

    non_contextual_location_rule =
      rule(:location_message_without_context,
        forall: [
          has(var(:msg), :type, "location"),
          has(var(:msg), :has_coordinates, true),
          has(var(:msg), :location, var(:location)),
          neg(var(:context), :has_llm_response, true)
        ],
        do: [
          gen(var(:action), :action_type, :show_location_options),
          gen(var(:action), :location, var(:location)),
          gen(var(:action), :priority, 85)
        ]
      )

    invalid_location_rule =
      rule(:location_message_invalid_coordinates,
        forall: [
          has(var(:msg), :type, "location"),
          has(var(:msg), :has_coordinates, false)
        ],
        do: [
          gen(var(:action), :action_type, :invalid_location_coordinates),
          gen(var(:action), :priority, 90)
        ]
      )

    engine
    |> Engine.compile(contextual_location_rule)
    |> Engine.compile(non_contextual_location_rule)
    |> Engine.compile(invalid_location_rule)
  end

  # ============================================================================
  # Contact Selection Rules
  # ============================================================================

  defp load_contact_selection_rules(engine) do
    contact_selection_with_gear_list_rule =
      rule(:contact_selection_with_gear_list,
        forall: [
          has(var(:msg), :type, "text"),
          has(var(:msg), :is_contact_selection, true),
          has(var(:msg), :selection_number, var(:selection_number)),
          has(var(:context), :has_gear_list, true),
          has(var(:context), :gear_list_users, var(:gear_list_users)),
          has(var(:user), :has_paid_access, var(:has_paid))
        ],
        do: [
          gen(var(:action), :action_type, :handle_contact_selection),
          gen(var(:action), :selection_number, var(:selection_number)),
          gen(var(:action), :gear_list_users, var(:gear_list_users)),
          gen(var(:action), :has_paid_access, var(:has_paid)),
          gen(var(:action), :priority, 95)
        ]
      )

    Engine.compile(engine, contact_selection_with_gear_list_rule)
  end

  # ============================================================================
  # General Text Message Rules
  # ============================================================================

  defp load_text_message_rules(engine) do
    # Rule: Process text messages with LLM (fallback for non-contact-selection texts)
    text_llm_fallback_rule =
      rule(:text_message_llm_fallback,
        forall: [
          has(var(:msg), :type, "text")
        ],
        do: [
          gen(var(:action), :action_type, :process_with_llm),
          gen(var(:action), :priority, 10)
        ]
      )

    Engine.compile(engine, text_llm_fallback_rule)
  end

  # ============================================================================
  # Audio Message Rules
  # ============================================================================

  defp load_audio_message_rules(engine) do
    # Rule: Process audio messages - download, transcribe, and process with LLM
    audio_processing_rule =
      rule(:audio_message_processing,
        forall: [
          has(var(:msg), :type, "audio"),
          has(var(:msg), :has_media_id, true)
        ],
        do: [
          gen(var(:action), :action_type, :process_audio_with_llm),
          gen(var(:action), :priority, 50)
        ]
      )

    Engine.compile(engine, audio_processing_rule)
  end

  # ============================================================================
  # List Reply Rules
  # ============================================================================

  defp load_list_reply_rules(engine) do
    # Rule: Handle disambiguation location selection
    disambiguate_rule =
      rule(:disambiguate_location_selection,
        forall: [
          has(var(:msg), :type, "interactive"),
          has(var(:msg), :interactive_type, "list_reply"),
          has(var(:msg), :has_selection, true),
          has(var(:msg), :selection_id, var(:selection_id))
        ],
        do: [
          gen(var(:action), :action_type, :disambiguate_location),
          gen(var(:action), :selection_id, var(:selection_id)),
          gen(var(:action), :priority, 80)
        ]
      )

    # Rule: Handle other list reply messages (not yet fully implemented)
    list_reply_rule =
      rule(:list_reply_not_implemented,
        forall: [
          has(var(:msg), :type, "interactive"),
          has(var(:msg), :interactive_type, "list_reply"),
          has(var(:msg), :has_selection, true)
        ],
        do: [
          gen(var(:action), :action_type, :handle_list_reply_not_implemented),
          gen(var(:action), :priority, 50)
        ]
      )

    engine
    |> Engine.compile(disambiguate_rule)
    |> Engine.compile(list_reply_rule)
  end

  # ============================================================================
  # ============================================================================
  # Contacts Message Rules (vCard/contact sharing)
  # ============================================================================

  defp load_contacts_message_rules(engine) do
    # Rule: User sends contacts when they have a pending deposit request
    # (Owner attaching renter's contact to deposit)
    contacts_with_pending_deposit_rule =
      rule(:contacts_with_pending_deposit,
        forall: [
          has(var(:msg), :type, "contacts"),
          has(var(:msg), :has_contacts, true),
          has(var(:user), :has_pending_deposit_request, true),
          has(var(:context), :pending_deposit_id, var(:deposit_id))
        ],
        do: [
          gen(var(:action), :action_type, :attach_renter_to_deposit),
          gen(var(:action), :deposit_id, var(:deposit_id)),
          gen(var(:action), :priority, 90)
        ]
      )

    # Rule: User sends contacts but has no pending deposit request
    contacts_without_pending_deposit_rule =
      rule(:contacts_without_pending_deposit,
        forall: [
          has(var(:msg), :type, "contacts"),
          has(var(:msg), :has_contacts, true),
          neg(var(:user), :has_pending_deposit_request, true)
        ],
        do: [
          gen(var(:action), :action_type, :contacts_no_pending_deposit),
          gen(var(:action), :priority, 50)
        ]
      )

    engine
    |> Engine.compile(contacts_with_pending_deposit_rule)
    |> Engine.compile(contacts_without_pending_deposit_rule)
  end
end
