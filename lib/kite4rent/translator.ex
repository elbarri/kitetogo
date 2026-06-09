defmodule Kite4rent.Translator do
  @moduledoc """
  Provides LLM-powered translation services for unsupported languages.
  Uses example translations in supported languages to guide the LLM for more accurate translations.
  """

  require Logger
  alias Kite4rent.LLMProcessor

  # Languages that have pre-translated templates
  @supported_languages ~w(en es fr de nl it)

  @doc """
  Translate text to target language using LLM with example translations for context.

  ## Parameters
  - `text`: The text to translate (in English)
  - `target_language`: ISO 639-1 language code (e.g., "pt", "ja", "ru")
  - `opts`: Optional parameters including `:provider` and `:model`

  ## Returns
  - `{:ok, translated_text}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> Kite4rent.Translator.translate("Hello, how are you?", "pt")
      {:ok, "Olá, como você está?"}
      
      iex> Kite4rent.Translator.translate("Your gear is now listed!", "ja")  
      {:ok, "あなたのギアはリストに登録されました！"}
  """
  def translate(text, target_language, opts \\ [])

  def translate(text, target_language, _opts) when target_language in @supported_languages do
    # No translation needed for supported languages
    {:ok, text}
  end

  def translate(text, target_language, opts)
      when is_binary(text) and is_binary(target_language) do
    provider = Keyword.get(opts, :provider) || get_default_provider()
    model = Keyword.get(opts, :model)

    prompt = build_translation_prompt(text, target_language)

    case LLMProcessor.generate_response(text, prompt, provider: provider, model: model) do
      {:ok, translated_text} ->
        Logger.info("Successfully translated text to #{target_language}")
        {:ok, String.trim(translated_text)}

      {:error, reason} ->
        Logger.warning("Translation failed for language #{target_language}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def translate(_text, _target_language, _opts) do
    {:error, "Invalid input parameters"}
  end

  @doc """
  Check if a language is natively supported (has pre-translated templates).

  ## Parameters
  - `language_code`: ISO 639-1 language code

  ## Returns
  - `true` if language has native template support
  - `false` if language requires LLM translation
  """
  def supported_language?(language_code) when language_code in @supported_languages, do: true
  def supported_language?(_language_code), do: false

  @doc """
  Get list of natively supported languages.
  """
  def supported_languages, do: @supported_languages

  # Private functions

  defp get_default_provider do
    Application.get_env(:kite4rent, :default_llm_provider, :openrouter)
  end

  defp build_translation_prompt(text, target_language) do
    """
    You are a professional translator specializing in kitesurfing/watersports terminology and casual messaging app named KiteToGo.

    Your task is to translate the given English (en) text to #{target_language} (ISO 639-1 two-letter language code).

    IMPORTANT GUIDELINES:
    1. Use the target language's most natural and conversational form
    2. Maintain the same tone and formality level as the original
    3. Keep any technical kitesurfing terms accurate
    4. Preserve line breaks (\\n) exactly as they appear
    5. Do not add explanations, just provide the translation
    6. Use informal/casual language appropriate for WhatsApp messaging
    7. Keep the emoticons in place and don't add any other emoticon

    Now translate this text to '#{target_language}' (ISO 639-1 two-letter language code):
    ```
    #{text}
    ```

    Provide only the translation, nothing else.
    """
  end
end
