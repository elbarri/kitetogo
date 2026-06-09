defmodule Kite4rent.MessageProcessor.TextUtils do
  @moduledoc """
  Shared text utility functions used across message processor modules.
  """

  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.ResponseTemplates

  @doc "Check if a message is a thumbs up emoji (any skin tone variant)"
  def thumbs_up?(text) when is_binary(text) do
    String.match?(String.trim(text), ~r/\A\x{1F44D}[\x{1F3FB}-\x{1F3FF}]?\z/u)
  end

  @doc "Check if a message contains only emoji characters (and optional whitespace)"
  def emoji_only?(text) when is_binary(text) do
    trimmed = String.trim(text)
    trimmed != "" and String.match?(trimmed, ~r/\A[\p{So}\p{Sk}\x{200D}\x{FE0F}\x{FE0E}\x{20E3}\x{1F3FB}-\x{1F3FF}\s]+\z/u)
  end

  @doc "Extract text from text or audio messages"
  def extract_text_from_message(%WhatsappMessage{type: "text", content: %{"body" => body}}),
    do: body

  def extract_text_from_message(%WhatsappMessage{type: "audio"}) do
    nil
  end

  def extract_text_from_message(_), do: nil

  @doc "Join a list with commas and localized 'and' for the last item"
  def join_with_localized_and([single], _language), do: single

  def join_with_localized_and([first, second], language) do
    and_word = ResponseTemplates.get_template(:conjunction_and, language)
    "#{first} #{and_word} #{second}"
  end

  def join_with_localized_and(list, language) do
    and_word = ResponseTemplates.get_template(:conjunction_and, language)
    [last | rest] = Enum.reverse(list)
    Enum.join(Enum.reverse(rest), ", ") <> " #{and_word} " <> last
  end

  @doc "Normalize emoji by removing skin tone modifiers"
  def normalize_emoji(nil), do: nil

  def normalize_emoji(emoji) when is_binary(emoji) do
    emoji
    |> String.graphemes()
    |> Enum.reject(fn char ->
      case String.to_charlist(char) do
        [codepoint] when codepoint >= 127995 and codepoint <= 127999 -> true
        _ -> false
      end
    end)
    |> Enum.join()
  end
end
