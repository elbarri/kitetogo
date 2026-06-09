defmodule Kite4rent.ReplyComposer do
  @moduledoc """
  Composes human-readable responses for WhatsApp users.
  Uses translation service for multi-language support.

  This module is a thin router that delegates to specialized sub-modules:
  - GearReplies: gear offer, request, inventory, completion
  - DepositReplies: deposit creation, selection, payment
  - ErrorReplies: error conditions
  - GeneralReplies: feedback, conversational, location, contact, payment, welcome
  """

  alias Kite4rent.IntentionHandler.RequestGear
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.ReplyComposer.DepositReplies
  alias Kite4rent.ReplyComposer.ErrorReplies
  alias Kite4rent.ReplyComposer.GearReplies
  alias Kite4rent.ReplyComposer.GeneralReplies
  alias Kite4rent.Users.User

  @doc """
  Compose a reply based on the action tuple and user.

  ## Parameters
  - First argument: action tuple or struct describing what to reply
  - `user`: User struct for language and location-based template substitutions

  ## Returns
  - `{:ok, reply}` or `{:ok, reply, extra_content}`
  """
  def compose_reply(action, nil),
    do: raise("User is required for compose_reply's action: #{inspect(action)}")

  # ============================================================================
  # Gear-related replies
  # ============================================================================

  def compose_reply({:full_gear_registered, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply({:offer_gear, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply({:offer_gear_incomplete, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply({:gear_offer_completed, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply({:contact_sharing_consent, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply({:list_own_inventory, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply(%RequestGear{} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply({:availability_countries, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply({:availability_locations, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply({:edit_gear_active_deposit, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply({:edit_gear_no_items, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply({:edit_gear_select_item, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply({:edit_gear_select_field, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply({:edit_gear_ask_value, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply({:edit_gear_success, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply({:availability_no_gear, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  def compose_reply({:availability_no_gear_in_country, _} = action, %User{} = user),
    do: GearReplies.compose_reply(action, user)

  # ============================================================================
  # Deposit-related replies
  # ============================================================================

  def compose_reply({:no_gear_to_rent, _} = action, %User{} = user),
    do: DepositReplies.compose_reply(action, user)

  def compose_reply({:deposit_creation_failed, _} = action, %User{} = user),
    do: DepositReplies.compose_reply(action, user)

  def compose_reply({:deposit_ask_missing_fields, _} = action, %User{} = user),
    do: DepositReplies.compose_reply(action, user)

  def compose_reply({:deposit_created_request_contact, _} = action, %User{} = user),
    do: DepositReplies.compose_reply(action, user)

  def compose_reply({:deposit_released, _} = action, %User{} = user),
    do: DepositReplies.compose_reply(action, user)

  def compose_reply({:renter_attached, _} = action, %User{} = user),
    do: DepositReplies.compose_reply(action, user)

  def compose_reply({:contact_not_registered, _, _} = action, %User{} = user),
    do: DepositReplies.compose_reply(action, user)

  def compose_reply({:deposit_select_gear, _} = action, %User{} = user),
    do: DepositReplies.compose_reply(action, user)

  def compose_reply({:deposit_ask_currency, _} = action, %User{} = user),
    do: DepositReplies.compose_reply(action, user)

  def compose_reply({:deposit_ask_value, _, _, _} = action, %User{} = user),
    do: DepositReplies.compose_reply(action, user)

  def compose_reply({:deposit_item_added, _, _, _} = action, %User{} = user),
    do: DepositReplies.compose_reply(action, user)

  def compose_reply({:deposit_ask_duration, _, _, _} = action, %User{} = user),
    do: DepositReplies.compose_reply(action, user)

  def compose_reply({:deposit_request_contact, _, _, _, _} = action, %User{} = user),
    do: DepositReplies.compose_reply(action, user)

  def compose_reply({:deposit_created_with_items, _, _} = action, %User{} = user),
    do: DepositReplies.compose_reply(action, user)

  def compose_reply({:deposit_created_review_agreement, _, _} = action, %User{} = user),
    do: DepositReplies.compose_reply(action, user)

  # ============================================================================
  # Error replies
  # ============================================================================

  def compose_reply({:error, :missing_location, %LLMResponse{}} = action, %User{} = user),
    do: ErrorReplies.compose_reply(action, user)

  def compose_reply({:error, {:location_not_found, _}} = action, %User{} = user),
    do: ErrorReplies.compose_reply(action, user)

  def compose_reply({:error, {:ambiguous_location, _, _}} = action, %User{} = user),
    do: ErrorReplies.compose_reply(action, user)

  def compose_reply({:error, {:missing_required_fields, _}} = action, %User{} = user),
    do: ErrorReplies.compose_reply(action, user)

  def compose_reply({:error, :no_gear_extracted} = action, %User{} = user),
    do: ErrorReplies.compose_reply(action, user)

  def compose_reply({:error, {:intention_not_yet_supported, _}} = action, %User{} = user),
    do: ErrorReplies.compose_reply(action, user)

  def compose_reply({:error, :unsupported_message_type} = action, %User{} = user),
    do: ErrorReplies.compose_reply(action, user)

  def compose_reply({:error, _reason} = action, %User{} = user),
    do: ErrorReplies.compose_reply(action, user)

  # ============================================================================
  # General replies
  # ============================================================================

  def compose_reply({:feedback_thanks, _} = action, %User{} = user),
    do: GeneralReplies.compose_reply(action, user)

  def compose_reply({:gear_clarification, _} = action, %User{} = user),
    do: GeneralReplies.compose_reply(action, user)

  def compose_reply({:conversational_response, _} = action, %User{} = user),
    do: GeneralReplies.compose_reply(action, user)

  def compose_reply({:location_updated, _} = action, %User{} = user),
    do: GeneralReplies.compose_reply(action, user)

  def compose_reply({:location_options, _} = action, %User{} = user),
    do: GeneralReplies.compose_reply(action, user)

  def compose_reply({:contact_selection_invalid} = action, %User{} = user),
    do: GeneralReplies.compose_reply(action, user)

  def compose_reply({:contact_payment_cta, _, _} = action, %User{} = user),
    do: GeneralReplies.compose_reply(action, user)

  def compose_reply({:first_time_user_welcome} = action, %User{} = user),
    do: GeneralReplies.compose_reply(action, user)

  # Fallback
  def compose_reply(action, %User{} = user),
    do: GeneralReplies.compose_reply(action, user)

  # ============================================================================
  # 3-arity overloads
  # ============================================================================

  def compose_reply(
        {:error, {:ambiguous_location_in_offer, _, _}} = action,
        %User{} = user,
        llm_response
      ),
      do: GearReplies.compose_reply(action, user, llm_response)
end
