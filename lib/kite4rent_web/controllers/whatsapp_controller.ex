defmodule Kite4rentWeb.WhatsappController do
  use Kite4rentWeb, :controller
  require Logger
  alias Kite4rent.{AdminNotifier, MessageProcessor, Messages, WhatsappClient, LLMProcessor, ReplyComposer}

  @doc """
  Handles the webhook verification from WhatsApp.
  WhatsApp sends a GET request with a challenge code that we need to verify.
  """
  def verify(conn, %{
        "hub.mode" => "subscribe",
        "hub.verify_token" => token,
        "hub.challenge" => challenge
      }) do
    verify_token = Application.fetch_env!(:kite4rent, :whatsapp_verify_token)

    if token == verify_token do
      conn
      |> put_status(:ok)
      |> text(challenge)
    else
      IO.puts("token: " <> token)
      IO.puts("verify_token: " <> verify_token)

      conn
      |> put_status(:forbidden)
      |> text("Invalid verify token")
    end
  end

  def verify(conn, _params) do
    conn
    |> put_status(:forbidden)
    |> text("Invalid verification request")
  end

  @doc """
  Handles incoming messages from WhatsApp.
  Processes both text and audio messages.

  For webhook payload examples, see:
  https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/payload-examples/
  """
  def webhook(conn, %{
        "entry" => [
          %{
            "changes" => [
              %{
                "field" => "messages",
                "value" => value
              }
            ],
            "id" => _entry_id
          }
        ],
        "object" => "whatsapp_business_account"
      }) do
    case Messages.create_message_from_webhook(value) do
      {:ok, %Messages.WhatsappMessage{} = message} ->
        WhatsappClient.mark_message_read_and_show_typing(
          message.phone_number,
          message.message_id
        )

        try do
          case MessageProcessor.process(message) do
            {:ok, :reaction_acknowledged} ->
              # Reaction received and acknowledged - no further action needed
              :ok

            {:ok, :ignored} ->
              # Unsupported/ignored message types are just stored. No outbound message.
              :ok

            {:ok, messages} when is_list(messages) ->
              # Multiple messages to send
              send_messages_with_context(message, messages)

            {:ok, single_message, extra_content} when is_tuple(single_message) ->
              # Single message with extra content - convert to list and send
              # Extra content will be merged into the message tuple by the processor
              enriched_message = merge_extra_content(single_message, extra_content)
              send_messages_with_context(message, [enriched_message])

            {:ok, single_message} ->
              # Single message - convert to list and send
              send_messages_with_context(message, [single_message])

            {:error, reason} ->
              Logger.error("Failed to process message: #{inspect(reason)}",
                error: :message_processing_failed,
                phone_number: message.phone_number,
                message_id: message.message_id,
                user_id: message.user_id,
                reason: reason
              )

              AdminNotifier.notify_error(message, {:error, reason})
          end
        rescue
          exception ->
            stacktrace = __STACKTRACE__
            # Log the full exception for debugging (stacktrace in message body so it's visible in dev)
            Logger.error("""
            Unexpected error processing message #{message.message_id} (user: #{message.user_id}):
            #{Exception.message(exception)}
            #{Exception.format_stacktrace(stacktrace)}
            """,
              error: :unexpected_message_processing_error,
              phone_number: message.phone_number,
              message_id: message.message_id,
              user_id: message.user_id
            )

            AdminNotifier.notify_error(message, {:exception, exception, stacktrace})

            # Generate user-friendly error message using LLM
            user_language = message.user.language || "en"

            case LLMProcessor.process_exception(exception, user_language) do
              {:ok, friendly_message} ->
                WhatsappClient.send_message(message.phone_number, friendly_message)

              {:error, _reason} ->
                # Fallback if LLM processing also fails - use ReplyComposer's generic error
                {:ok, {:text, fallback_message}} =
                  ReplyComposer.compose_reply(:generic_error, message.user)

                WhatsappClient.send_message(message.phone_number, fallback_message)
            end
        end
        |> case do
          {:error, reason} ->
            Logger.error("Failed to send message to WhatsApp: #{inspect(reason)}",
              error: :whatsapp_cliente_failed_on_send_message,
              phone_number: message.phone_number,
              message_id: message.message_id,
              user_id: message.user_id,
              reason: reason
            )

          _ ->
            :ok
        end

      {:ok, %Messages.MessageStatus{}} ->
        # Status update received - no action needed for now
        # Logger.debug("Status update received")
        :ok

      {:error, changeset} ->
        Logger.error("Failed to create message from webhook: #{inspect(changeset.errors)}",
          error: :webhook_message_creation_failed,
          changeset_errors: changeset.errors,
          operation: "create_message_from_webhook"
        )

        conn
        |> put_status(:bad_request)
        |> text("Invalid message format")
    end

    conn
    |> put_status(:ok)
    |> text("OK")
  end

  def webhook(conn, params) do
    Logger.error("Failed to process WhatsApp webhook: #{inspect(params)}",
      error: :webhook_processing_failed,
      params: params,
      operation: "webhook_processing"
    )

    # TODO: pattern match likely failed. Do something.
    conn
    |> put_status(:bad_request)
    |> text("Bad request")
  end

  # Private helper to send messages with context enrichment
  defp send_messages_with_context(incoming_message, messages) do
    # Enrich messages that need context (like interactive_reply_buttons)
    enriched_messages =
      Enum.map(messages, fn msg ->
        enrich_message_with_context(msg, incoming_message)
      end)

    WhatsappClient.send_messages(incoming_message.phone_number, enriched_messages)
  end

  # Interactive reply buttons that already have extra_content - pass through
  defp enrich_message_with_context(
         {:interactive_reply_buttons, _body_text, _buttons, opts} = message,
         _incoming_message
       )
       when is_list(opts) do
    message
  end

  # Add context to interactive_reply_buttons if needed (legacy case)
  defp enrich_message_with_context({:interactive_reply_buttons, body_text, buttons}, incoming_message) do
    extra_content =
      Map.get(Messages.get_message_by_whatsapp_id!(incoming_message.message_id), :content)

    {:interactive_reply_buttons, body_text, buttons, extra_content: extra_content}
  end

  # Special case for reactions - need message_id
  defp enrich_message_with_context({:reaction, emoji}, incoming_message) do
    {:reaction, incoming_message.message_id, emoji}
  end

  # All other message types pass through unchanged
  defp enrich_message_with_context(message, _incoming_message), do: message

  # Helper to merge extra_content into message tuples
  # Handles messages that come with extra_content from ReplyComposer
  defp merge_extra_content({:text, text}, extra_content) when is_map(extra_content) do
    {:text, text, extra_content}
  end

  defp merge_extra_content({:location_request, text}, extra_content) when is_map(extra_content) do
    {:location_request, text, extra_content}
  end

  defp merge_extra_content({:interactive_reply_buttons, body_text, buttons}, extra_content)
       when is_map(extra_content) do
    {:interactive_reply_buttons, body_text, buttons, [extra_content: extra_content]}
  end

  defp merge_extra_content({:interactive_list, body_text, button_text, sections}, extra_content)
       when is_map(extra_content) do
    {:interactive_list, body_text, button_text, sections, extra_content}
  end

  defp merge_extra_content(message, _extra_content), do: message
end
