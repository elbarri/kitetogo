defmodule Kite4rent.MessageProcessor.LLMProcessing do
  @moduledoc """
  Handles LLM content processing, language detection, and feedback notifications.
  """
  require Logger

  alias Kite4rent.Intentions
  alias Kite4rent.MessageCoordinatorIntegration
  alias Kite4rent.Messages
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.ReplyComposer
  alias Kite4rent.Users
  alias Kite4rent.Users.User
  alias Kite4rent.WhatsappClient

  @feedback Intentions.feedback()
  @default_language "en"

  def process_llm_content(message, text, type, opts \\ []) do
    conversation_history =
      Messages.get_conversation_history(message.user_id,
        limit: 5,
        exclude_current: message.message_id
      )

    llm_opts =
      opts
      |> Keyword.take([:language])
      |> Keyword.put(:is_audio?, :audio == type)
      |> Keyword.put(:conversation_history, conversation_history)
      |> Keyword.put(:user_id, message.user_id)

    feature_flags = %{
      use_intent_classifier: true,
      use_location_extractor: true,
      use_gear_extractor: true
    }

    with {:ok, response} <-
           MessageCoordinatorIntegration.process_with_flags(text, llm_opts, feature_flags) do
      detected_language = Keyword.get(opts, :language)

      response = %LLMResponse{
        response
        | language: detected_language || response.language || get_user_language(message.user)
      }

      content_to_merge =
        case Keyword.get(opts, :transcription) do
          nil -> {"llm_response", response}
          transcription -> %{"transcription" => transcription, "llm_response" => response}
        end

      message
      |> maybe_update_user_language(response.language)
      |> Messages.merge_into_content!(content_to_merge, drop_nils: true)
      |> tap(&notify_feedback_if_any/1)
      |> then(&Kite4rent.MessageProcessor.act_on_intention(response, &1))
    else
      error ->
        handle_processing_error(error, message, type, opts)
    end
  end

  def handle_processing_error({:error, _type, reason}, message, type, opts) do
    handle_processing_error({:error, reason}, message, type, opts)
  end

  def handle_processing_error({:error, reason}, message, type, opts) do
    {error_type, error_message, metadata} = build_error_details(type, reason, message, opts)

    Logger.error(error_message, [{:error, error_type} | Map.to_list(metadata)])

    compose_error_reply(reason, message)
  end

  defp build_error_details(:text, reason, message, opts) do
    {
      :text_processing_failed,
      "Failed to process text: #{reason}",
      %{
        phone_number: message.phone_number,
        user_id: message.user_id,
        message_id: message.message_id,
        opts: opts,
        text_length: String.length(message.content["body"])
      }
    }
  end

  defp build_error_details(:audio, reason, message, opts) do
    media_id = Keyword.get(opts, :media_id)

    {
      :audio_processing_failed,
      "Failed to process audio for media_id #{media_id}: #{reason}",
      %{
        phone_number: message.phone_number,
        user_id: message.user_id,
        message_id: message.message_id,
        media_id: media_id
      }
    }
  end

  defp get_user_language(user) when is_struct(user, User), do: User.get_language(user)
  defp get_user_language(_), do: @default_language

  defp maybe_update_user_language(%WhatsappMessage{} = msg, detected_language)
       when detected_language in ["un", nil, ""],
       do: msg

  defp maybe_update_user_language(%WhatsappMessage{user: user} = msg, detected_language) do
    current_language = get_user_language(user)

    if detected_language != current_language do
      %{msg | user: Users.update_user!(user, %{language: detected_language})}
    else
      msg
    end
  end

  defp notify_feedback_if_any(
         %WhatsappMessage{content: %{"llm_response" => %{"intention" => @feedback}}} = message
       ) do
    if Mix.env() != :test do
      admin_phone = Application.get_env(:kite4rent, :admin_phone)

      body_text = message.content["body"] || message.content["transcription"]["text"]

      header =
        "[Feedback] from #{message.phone_number} (lang=#{message.user.language})\n" <>
          "Message ID: #{message.message_id}\n"

      max_len = 3500

      trimmed_body =
        if is_binary(body_text) and String.length(body_text) > max_len do
          String.slice(body_text, 0, max_len) <> "…"
        else
          body_text
        end

      WhatsappClient.send_message(admin_phone, header <> trimmed_body)
    else
      :ok
    end
  end

  defp notify_feedback_if_any(%WhatsappMessage{}), do: :ok

  defp compose_error_reply(reason, %WhatsappMessage{user: user} = _message) do
    Logger.warning("Failed to compose error reply for reason: #{inspect(reason)}")
    ReplyComposer.compose_reply({:error, reason}, user)
  end
end
