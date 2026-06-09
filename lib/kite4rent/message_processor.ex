defmodule Kite4rent.MessageProcessor do
  @moduledoc """
  Processes incoming WhatsApp messages, including text and audio.
  Converts audio to text and uses LLM to interpret and respond.
  Returns the final translated response ready to be sent.
  """
  require Logger

  alias Kite4rent.IntentionHandler
  alias Kite4rent.Messages
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.MessageProcessor.ConsentHandler
  alias Kite4rent.MessageProcessor.ImageHandler
  alias Kite4rent.MessageProcessor.MessageRouter
  alias Kite4rent.MessageProcessor.TextUtils
  alias Kite4rent.ReplyComposer
  alias Kite4rent.Users
  alias Kite4rent.Users.User
  alias Kite4rent.WhatsappClient

  # ============================================================================
  # Public API — Notifications (delegated to preserve external callers)
  # ============================================================================

  defdelegate notify_renter_agreement_ready(deposit, renter),
    to: Kite4rent.MessageProcessor.Notifications

  defdelegate notify_owner_changes_requested(deposit, owner),
    to: Kite4rent.MessageProcessor.Notifications

  defdelegate notify_owner_renter_approved_agreement(deposit, owner),
    to: Kite4rent.MessageProcessor.Notifications

  defdelegate notify_renter_payment_ready(deposit, renter),
    to: Kite4rent.MessageProcessor.Notifications

  # ============================================================================
  # Main Processing Path
  # ============================================================================

  def process(%WhatsappMessage{type: "text", content: %{"body" => body}, user: user} = message) do
    cond do
      TextUtils.thumbs_up?(body) ->
        if user && !user.contact_sharing_consent && ConsentHandler.replied_to_consent_request?(message) do
          Logger.info("Thumbs up text reply as consent from user #{user.id}")
          WhatsappClient.send_reaction(message.phone_number, message.message_id, "✅")
          ConsentHandler.handle_grant_consent(message)
        else
          Logger.info("Thumbs up received, reacting with checkmark: #{body}")
          WhatsappClient.send_reaction(message.phone_number, message.message_id, "✅")
          {:ok, :ignored}
        end

      TextUtils.emoji_only?(body) ->
        Logger.info("Ignoring emoji-only message: #{body}")
        {:ok, :ignored}

      true ->
        MessageRouter.route(message)
    end
  end

  def process(%WhatsappMessage{type: type} = message)
      when type in ["audio", "reaction", "location", "interactive", "contacts"] do
    MessageRouter.route(message)
  end

  def process(%WhatsappMessage{type: "image", user: user} = message) do
    ImageHandler.handle_image_message(message, user)
  end

  def process(%WhatsappMessage{type: type, message_id: message_id, phone_number: phone_number}) do
    Logger.info(
      "Ignoring unsupported message. id: #{message_id}, type: #{type} from #{phone_number}"
    )

    {:ok, :ignored}
  end

  # ============================================================================
  # Public helpers called by sub-modules
  # ============================================================================

  @doc false
  def act_on_intention(
        %LLMResponse{gear_clarification: text, intention: intention} = llm_response,
        %WhatsappMessage{user: user} = _message
      )
      when is_binary(text) and text != "" and
             intention not in ["request_gear", "check_availability"] do
    apply_labels_if_needed(llm_response, user)
    ReplyComposer.compose_reply({:gear_clarification, text}, user)
  end

  def act_on_intention(%LLMResponse{} = llm_response, %WhatsappMessage{user: user} = message) do
    user = apply_labels_if_needed(llm_response, user)
    original_text = TextUtils.extract_text_from_message(message)

    case IntentionHandler.handle(llm_response, user, original_text: original_text) do
      {:ok, {:no_response, _user}} ->
        {:ok, :ignored}

      {:ok, {action, action_data, user}} ->
        ReplyComposer.compose_reply({action, action_data}, user)

      {:ok, {handled_intention, user}} when is_map(handled_intention) ->
        ReplyComposer.compose_reply(handled_intention, user)

      {:error, {:ambiguous_location, _location_name, _countries_data}} = error ->
        ReplyComposer.compose_reply(error, user)

      {:error, {:ambiguous_location_in_offer, _location_name, _countries_data}} = error ->
        ReplyComposer.compose_reply(error, user, llm_response)

      {:error, :missing_location, llm_response_with_context} ->
        ReplyComposer.compose_reply({:error, :missing_location, llm_response_with_context}, user)

      {:error, reason} ->
        compose_error_reply(reason, llm_response, message)
    end
  end

  # ============================================================================
  # Label Application (is_school / is_renting_full_gear)
  # ============================================================================

  defp apply_labels_if_needed(%LLMResponse{}, %User{id: nil} = user), do: user

  defp apply_labels_if_needed(%LLMResponse{} = llm_response, %User{} = user) do
    updates =
      %{}
      |> maybe_put_label(:is_school, llm_response.is_school, user.is_school)
      |> maybe_put_label(:is_renting_full_gear, llm_response.offers_full_gear, user.is_renting_full_gear)

    # Auto-grant consent when a school or full-gear renter is detected
    updates =
      if map_size(updates) > 0 and not user.contact_sharing_consent do
        Map.merge(updates, %{
          contact_sharing_consent: true,
          contact_sharing_consent_at: DateTime.utc_now()
        })
      else
        updates
      end

    if map_size(updates) > 0 do
      case Users.update_user(user, updates) do
        {:ok, updated_user} ->
          Logger.info("Applied labels #{inspect(Map.keys(updates))} to user #{user.id}")
          updated_user

        {:error, reason} ->
          Logger.warning("Failed to apply labels to user #{user.id}: #{inspect(reason)}")
          user
      end
    else
      user
    end
  end

  defp maybe_put_label(updates, _key, true, true), do: updates
  defp maybe_put_label(updates, key, true, _current), do: Map.put(updates, key, true)
  defp maybe_put_label(updates, _key, _detected, _current), do: updates

  # ============================================================================
  # Error Reply Composition
  # ============================================================================

  defp compose_error_reply(
         :missing_location,
         %LLMResponse{} = response,
         %WhatsappMessage{user: user} = _message
       ) do
    ReplyComposer.compose_reply({:error, :missing_location, response}, user)
  end

  defp compose_error_reply(
         :unsupported_message_type,
         _response,
         %WhatsappMessage{user: user} = _message
       ) do
    ReplyComposer.compose_reply({:error, :unsupported_message_type}, user)
  end

  defp compose_error_reply(
         :location_not_found,
         %LLMResponse{location: location_name},
         %WhatsappMessage{user: user}
       ) do
    ReplyComposer.compose_reply({:error, {:location_not_found, location_name}}, user)
  end

  defp compose_error_reply(
         :intention_not_yet_supported,
         %LLMResponse{intention: intention},
         %WhatsappMessage{user: user}
       ) do
    if length(Messages.list_messages_by_user_id(user.id)) <= 1 do
      ReplyComposer.compose_reply({:first_time_user_welcome}, user)
    else
      ReplyComposer.compose_reply(
        {:error, {:intention_not_yet_supported, intention}},
        user
      )
    end
  end

  defp compose_error_reply(
         {:missing_required_fields, gear_type},
         %LLMResponse{},
         %WhatsappMessage{user: user}
       ) do
    ReplyComposer.compose_reply({:error, {:missing_required_fields, gear_type}}, user)
  end

  defp compose_error_reply(
         :no_gear_extracted,
         %LLMResponse{},
         %WhatsappMessage{user: user}
       ) do
    ReplyComposer.compose_reply({:error, :no_gear_extracted}, user)
  end

  defp compose_error_reply(reason, %LLMResponse{}, %WhatsappMessage{user: user}) do
    Logger.warning("Unhandled error in compose_error_reply/3: #{inspect(reason)}")
    ReplyComposer.compose_reply({:error, reason}, user)
  end
end
