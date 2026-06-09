defmodule Kite4rent.AdminNotifier do
  @moduledoc """
  Sends error alerts to the admin via WhatsApp when message processing fails.
  Includes conversation context and a follow-up with post-error messages.
  """

  require Logger
  alias Kite4rent.{Messages, WhatsappClient}

  @max_message_length 4096
  @content_truncate_length 200

  def notify_error(message, error_info) do
    if Mix.env() != :test do
      admin_phone = Application.get_env(:kite4rent, :admin_phone)

      if admin_phone do
        Task.start(fn ->
          try do
            do_notify(message, error_info, admin_phone)
          rescue
            e ->
              Logger.error("AdminNotifier crashed: #{Exception.message(e)}")
          end
        end)
      end
    end
  end

  defp do_notify(message, error_info, admin_phone) do
    # Wait for the system response to be saved to DB
    Process.sleep(3_000)

    user = message.user
    messages_around = Messages.get_messages_around_error(user.id, message.id)

    {error_text, location_text} = format_error_info(error_info)

    header = """
    🚨 ERROR ALERT

    👤 User: #{user.name || "Unknown"} (ID: #{user.id})
    📱 Phone: +#{message.phone_number}

    ❌ Error: #{error_text}
    📍 #{location_text}
    """

    conversation = format_conversation(messages_around, message.id)

    full_message = header <> "\n" <> conversation

    if String.length(full_message) <= @max_message_length do
      WhatsappClient.send_message(admin_phone, full_message)
    else
      # Split into header + conversation
      WhatsappClient.send_messages(admin_phone, [
        {:text, String.slice(header, 0, @max_message_length)},
        {:text, String.slice(conversation, 0, @max_message_length)}
      ])
    end

    # Wait 1 minute then send follow-up
    Process.sleep(60_000)

    followup_messages = Messages.get_messages_after(user.id, message.id)

    followup =
      if followup_messages == [] do
        "📋 UPDATE (User: #{user.name || "Unknown"}, ID: #{user.id})\n\nNo further messages."
      else
        followup_conversation =
          followup_messages
          |> Enum.map(&format_single_message/1)
          |> Enum.join("\n")

        """
        📋 UPDATE (User: #{user.name || "Unknown"}, ID: #{user.id})

        Post-error messages:
        ━━━━━━━━━━━━━━━━━━━━━━
        #{followup_conversation}
        """
      end

    WhatsappClient.send_message(admin_phone, String.slice(followup, 0, @max_message_length))
  end

  defp format_error_info({:exception, exception, stacktrace}) do
    error_text = inspect(exception)

    location_text =
      case stacktrace do
        [{mod, fun, arity, info} | _] ->
          file = Keyword.get(info, :file, "?") |> to_string()
          line = Keyword.get(info, :line, "?")
          "#{inspect(mod)}.#{fun}/#{normalize_arity(arity)}\n   #{file}:#{line}"

        _ ->
          "Unknown location"
      end

    {error_text, location_text}
  end

  defp format_error_info({:error, reason}) do
    {inspect(reason), "MessageProcessor.process/1"}
  end

  defp normalize_arity(arity) when is_integer(arity), do: arity
  defp normalize_arity(args) when is_list(args), do: length(args)

  defp format_conversation(messages, error_message_id) do
    header = "💬 Messages (#{length(messages)}):\n━━━━━━━━━━━━━━━━━━━━━━\n"

    lines =
      messages
      |> Enum.map(fn msg ->
        line = format_single_message(msg)
        if msg.id == error_message_id, do: line <> "  ⚠️", else: line
      end)
      |> Enum.join("\n")

    header <> lines
  end

  defp format_single_message(msg) do
    direction = if msg.is_incoming, do: "→", else: "←"
    content = truncate(inspect(msg.content), @content_truncate_length)

    context_part =
      case msg.context do
        nil -> ""
        ctx when ctx == %{} -> ""
        ctx -> " ctx:#{truncate(inspect(ctx), 80)}"
      end

    "##{msg.id} #{direction} #{content}#{context_part}"
  end

  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max - 3) <> "..."
end
