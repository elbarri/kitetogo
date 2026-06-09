defmodule Kite4rent.MessageProcessor.FlowRouter do
  @moduledoc """
  Routes messages to appropriate conversation flow handlers based on active flow state.
  """
  require Logger

  alias Kite4rent.Conversation.Manager, as: FlowManager
  alias Kite4rent.Conversation.State, as: FlowState
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.MessageProcessor.Flows.DepositCollection
  alias Kite4rent.MessageProcessor.Flows.DepositItemSelection
  alias Kite4rent.MessageProcessor.Flows.GearCompletion
  alias Kite4rent.MessageProcessor.Flows.GearEdit
  alias Kite4rent.MessageProcessor.Flows.GearOffer
  alias Kite4rent.MessageProcessor.TextUtils
  alias Kite4rent.ResponseTemplates
  alias Kite4rent.Users.User

  @doc """
  Check if user has an active conversation flow and handle accordingly.
  Returns {:handled, result} or :not_in_flow.
  """
  def maybe_handle(%WhatsappMessage{type: type} = message, %User{} = user)
      when type in ["text", "audio", "location", "interactive", "contacts"] do
    case FlowManager.get_state(user.id) do
      {:ok, %FlowState{current_flow: flow, flow_step: step} = state}
      when not is_nil(flow) ->
        Logger.info("User #{user.id} has active flow: #{flow}, step: #{inspect(step)}")
        handle_flow_message(message, state)

      _ ->
        :not_in_flow
    end
  end

  def maybe_handle(_message, _user), do: :not_in_flow

  # ============================================================================
  # Gear Offer Flow
  # ============================================================================

  defp handle_flow_message(
         %WhatsappMessage{type: "location"} = message,
         %FlowState{current_flow: :gear_offer, flow_step: {:awaiting, :location}} = state
       ) do
    GearOffer.handle_gear_offer_location_received(message, state)
  end

  defp handle_flow_message(
         %WhatsappMessage{type: type} = message,
         %FlowState{current_flow: :gear_offer, flow_step: {:awaiting, :location}} = state
       )
       when type in ["text", "audio"] do
    GearOffer.handle_gear_offer_text_as_location(message, state)
  end

  # ============================================================================
  # Gear Completion Flow
  # ============================================================================

  defp handle_flow_message(
         %WhatsappMessage{type: type} = message,
         %FlowState{current_flow: :gear_completion, flow_step: {:awaiting, :gear_fields}} = state
       )
       when type in ["text", "audio"] do
    GearCompletion.handle_gear_completion_response(message, state)
  end

  # ============================================================================
  # Deposit Collection Flow
  # ============================================================================

  defp handle_flow_message(
         %WhatsappMessage{type: type} = message,
         %FlowState{current_flow: :deposit_collection, flow_step: {:awaiting, :deposit_fields}} = state
       )
       when type in ["text", "audio"] do
    DepositCollection.handle_deposit_collection_response(message, state)
  end

  # ============================================================================
  # Deposit Item Selection Flow
  # ============================================================================

  defp handle_flow_message(
         %WhatsappMessage{type: type} = message,
         %FlowState{current_flow: :deposit_item_selection, flow_step: :awaiting_value} = state
       )
       when type in ["text", "audio"] do
    DepositItemSelection.handle_deposit_item_value_input(message, state)
  end

  defp handle_flow_message(
         %WhatsappMessage{type: type, user: user} = message,
         %FlowState{current_flow: :deposit_item_selection, flow_step: :awaiting_duration, collected_data: collected_data}
       )
       when type in ["text", "audio"] do
    text = TextUtils.extract_text_from_message(message)
    DepositItemSelection.handle_deposit_duration_input(user, text, collected_data)
  end

  defp handle_flow_message(
         %WhatsappMessage{type: "contacts"} = message,
         %FlowState{current_flow: :deposit_item_selection, flow_step: :awaiting_contact} = state
       ) do
    DepositItemSelection.handle_deposit_item_contact_received(message, state)
  end

  defp handle_flow_message(
         %WhatsappMessage{type: "text"} = message,
         %FlowState{current_flow: :deposit_item_selection, flow_step: :awaiting_contact} = _state
       ) do
    text = TextUtils.extract_text_from_message(message)
    language = User.get_language(message.user)

    cleaned = String.replace(text || "", ~r/[^\d+]/, "")

    if String.length(cleaned) >= 8 do
      reminder = ResponseTemplates.get_template(:deposit_share_contact_reminder, language)
      {:handled, {:ok, {:text, reminder}}}
    else
      :not_in_flow
    end
  end

  defp handle_flow_message(
         %WhatsappMessage{type: "interactive", content: content, user: user} = _message,
         %FlowState{current_flow: :deposit_item_selection, flow_step: :selecting_item} = _state
       ) do
    interactive_type = content["type"]
    list_reply = content["list_reply"]

    case {interactive_type, list_reply} do
      {"list_reply", %{"id" => selection_id}} when is_binary(selection_id) ->
        if String.starts_with?(selection_id, "deposit_gear_") do
          DepositItemSelection.handle_deposit_gear_selection(user, selection_id)
        else
          :not_in_flow
        end

      _ ->
        :not_in_flow
    end
  end

  defp handle_flow_message(
         %WhatsappMessage{type: "interactive", content: content, user: user} = _message,
         %FlowState{current_flow: :deposit_item_selection, flow_step: :awaiting_currency, collected_data: collected_data} = _state
       ) do
    interactive_type = content["type"]
    button_reply = content["button_reply"]

    case {interactive_type, button_reply} do
      {"button_reply", %{"id" => button_id}} when is_binary(button_id) ->
        if String.starts_with?(button_id, "deposit_currency_") do
          DepositItemSelection.handle_deposit_currency_selection(user, button_id, collected_data)
        else
          :not_in_flow
        end

      _ ->
        :not_in_flow
    end
  end

  # ============================================================================
  # Gear Edit Flow
  # ============================================================================

  # Gear Edit - selecting item (interactive list)
  defp handle_flow_message(
         %WhatsappMessage{type: "interactive"} = message,
         %FlowState{current_flow: :gear_edit, flow_step: :selecting_item}
       ) do
    GearEdit.handle_gear_edit_selection(message)
  end

  # Gear Edit - selecting field (interactive buttons)
  defp handle_flow_message(
         %WhatsappMessage{type: "interactive", content: content} = message,
         %FlowState{current_flow: :gear_edit, flow_step: :selecting_field, collected_data: collected_data}
       ) do
    button_id = get_in(content, ["button_reply", "id"])

    if button_id && String.starts_with?(button_id, "edit_field_") do
      GearEdit.handle_gear_edit_field_selection(message, collected_data)
    else
      :not_in_flow
    end
  end

  # Gear Edit - awaiting value (text/audio input)
  defp handle_flow_message(
         %WhatsappMessage{type: type} = message,
         %FlowState{current_flow: :gear_edit, flow_step: :awaiting_value, collected_data: collected_data}
       )
       when type in ["text", "audio"] do
    GearEdit.handle_gear_edit_value_input(message, collected_data)
  end

  # Catch stale edit_gear/edit_field interactions when flow step doesn't match
  defp handle_flow_message(
         %WhatsappMessage{type: "interactive", content: content, user: user} = _message,
         %FlowState{current_flow: :gear_edit}
       ) do
    button_id = get_in(content, ["button_reply", "id"])
    list_id = get_in(content, ["list_reply", "id"])
    interaction_id = button_id || list_id

    if interaction_id &&
         (String.starts_with?(interaction_id, "edit_gear_") or
            String.starts_with?(interaction_id, "edit_field_")) do
      Logger.info("Stale gear edit interaction: #{interaction_id}")
      language = User.get_language(user)
      message = ResponseTemplates.get_template(:edit_gear_action_expired, language)
      {:handled, {:ok, {:text, message}}}
    else
      :not_in_flow
    end
  end

  # Catch edit_gear/edit_field button clicks when there's NO active gear_edit flow
  defp handle_flow_message(
         %WhatsappMessage{type: "interactive", content: content, user: user} = _message,
         %FlowState{current_flow: current_flow}
       )
       when current_flow != :gear_edit and current_flow != :deposit_item_selection do
    button_id = get_in(content, ["button_reply", "id"])
    list_id = get_in(content, ["list_reply", "id"])
    interaction_id = button_id || list_id

    if interaction_id &&
         (String.starts_with?(interaction_id, "edit_gear_") or
            String.starts_with?(interaction_id, "edit_field_")) do
      Logger.info("Gear edit button clicked with no active flow: #{interaction_id}")
      language = User.get_language(user)
      message = ResponseTemplates.get_template(:edit_gear_action_expired, language)
      {:handled, {:ok, {:text, message}}}
    else
      :not_in_flow
    end
  end

  # Catch-all for interactive messages in deposit_item_selection flow that don't match current step
  defp handle_flow_message(
         %WhatsappMessage{type: "interactive", content: content, user: user} = _message,
         %FlowState{current_flow: :deposit_item_selection, flow_step: current_step} = _state
       ) do
    button_id = get_in(content, ["button_reply", "id"])
    list_id = get_in(content, ["list_reply", "id"])
    interaction_id = button_id || list_id

    if interaction_id && String.starts_with?(interaction_id, "deposit_") do
      if interaction_valid_for_step?(interaction_id, current_step) do
        :not_in_flow
      else
        Logger.info("Stale deposit interaction received: #{interaction_id}, current step: #{inspect(current_step)}")
        language = User.get_language(user)
        message = ResponseTemplates.get_template(:deposit_action_no_longer_available, language)
        {:handled, {:ok, {:text, message}}}
      end
    else
      :not_in_flow
    end
  end

  # Catch deposit-related button clicks when there's NO active deposit_item_selection flow
  defp handle_flow_message(
         %WhatsappMessage{type: "interactive", content: content, user: user} = _message,
         %FlowState{current_flow: current_flow} = _state
       )
       when current_flow != :deposit_item_selection do
    button_id = get_in(content, ["button_reply", "id"])
    list_id = get_in(content, ["list_reply", "id"])
    interaction_id = button_id || list_id

    if interaction_id && String.starts_with?(interaction_id, "deposit_") do
      Logger.info("Deposit button clicked with no active flow: #{interaction_id}")
      language = User.get_language(user)
      message = ResponseTemplates.get_template(:deposit_action_no_longer_available, language)
      {:handled, {:ok, {:text, message}}}
    else
      :not_in_flow
    end
  end

  defp handle_flow_message(_message, _state) do
    :not_in_flow
  end

  # Check if an interaction ID is valid for the current flow step
  defp interaction_valid_for_step?(interaction_id, step) do
    case step do
      :selecting_item ->
        String.starts_with?(interaction_id, "deposit_gear_")

      :awaiting_currency ->
        String.starts_with?(interaction_id, "deposit_currency_")

      :confirm_add_more ->
        interaction_id in ["deposit_add_more_yes", "deposit_add_more_no"]

      _ ->
        false
    end
  end
end
