defmodule Kite4rent.Translations do
  @moduledoc """
  Translation service with caching capabilities.

  Uses LLM-based translation for all language pairs through Kite4rent.Translator.

  Implements persistent caching to minimize API calls and costs.
  """

  require Logger
  import Ecto.Query, warn: false
  alias Kite4rent.Repo
  alias Kite4rent.Translations.Translation

  @doc """
  Translate text from source language to target language.

  ## Parameters
  - `text`: Text to translate
  - `source_lang`: Source language code (e.g., "en", "es", "pt")
  - `target_lang`: Target language code
  - `provider`: Translation provider (optional, defaults to configured provider)

  ## Returns
  - `{:ok, translated_text}` when successful
  - `{:error, reason}` when failed
  """
  def translate(text, source_lang, target_lang, provider \\ nil)

  def translate(text, source_lang, target_lang, _provider) when source_lang == target_lang do
    {:ok, text}
  end

  def translate(text, source_lang, target_lang, provider) do
    text = String.trim(text)

    if text == "" do
      {:ok, ""}
    else
      text_hash = Translation.generate_hash(text)

      case get_cached_translation(text_hash, source_lang, target_lang) do
        {:ok, cached_translation} ->
          Logger.debug("Using cached translation for #{source_lang} -> #{target_lang}")
          {:ok, cached_translation}

        {:error, :not_found} ->
          perform_translation(
            text,
            text_hash,
            source_lang,
            target_lang,
            provider || default_provider()
          )
      end
    end
  end

  @doc """
  Get available translation providers and their status
  """
  def get_providers_status do
    %{
      llm: :available
    }
  end

  @doc """
  Clear translation cache for a specific language pair or all translations
  """
  def clear_cache(source_lang \\ nil, target_lang \\ nil) do
    query =
      case {source_lang, target_lang} do
        {nil, nil} ->
          from(t in Translation)

        {source, nil} ->
          from(t in Translation, where: t.source_language == ^source)

        {nil, target} ->
          from(t in Translation, where: t.target_language == ^target)

        {source, target} ->
          from(t in Translation,
            where: t.source_language == ^source and t.target_language == ^target
          )
      end

    {count, _} = Repo.delete_all(query)

    Logger.info("Cleared #{count} translation cache entries",
      source_lang: source_lang,
      target_lang: target_lang
    )

    {:ok, count}
  end

  @doc """
  Clear expired translation cache entries (older than 30 days)
  """
  def clear_expired_cache do
    expiry = DateTime.add(DateTime.utc_now(), -30 * 24 * 60 * 60, :second)

    {count, _} =
      from(t in Translation, where: t.inserted_at < ^expiry)
      |> Repo.delete_all()

    Logger.info("Cleared #{count} expired translation cache entries")
    {:ok, count}
  end

  # Private functions

  defp get_cached_translation(text_hash, source_lang, target_lang) do
    case Repo.get_by(Translation,
           text_hash: text_hash,
           source_language: source_lang,
           target_language: target_lang
         ) do
      nil -> {:error, :not_found}
      translation -> {:ok, translation.translated_text}
    end
  end

  defp perform_translation(text, text_hash, source_lang, target_lang, _provider) do
    # Use LLM-based translation for all translations
    case Kite4rent.Translator.translate(text, target_lang) do
      {:ok, translated_text} ->
        cache_translation(text, text_hash, source_lang, target_lang, translated_text, "llm")
        {:ok, translated_text}

      {:error, reason} ->
        Logger.error("LLM translation failed: #{inspect(reason)}",
          error: :translation_failed,
          source_lang: source_lang,
          target_lang: target_lang,
          text_length: String.length(text),
          reason: reason
        )

        {:error, reason}
    end
  end


  defp cache_translation(text, text_hash, source_lang, target_lang, translated_text, provider) do
    attrs = %{
      source_text: text,
      source_language: source_lang,
      target_language: target_lang,
      translated_text: translated_text,
      provider: provider,
      text_hash: text_hash
    }

    case %Translation{} |> Translation.changeset(attrs) |> Repo.insert() do
      {:ok, _translation} ->
        Logger.debug("Cached translation: #{source_lang} -> #{target_lang}")
        :ok

      {:error, changeset} ->
        Logger.warning("Failed to cache translation: #{inspect(changeset.errors)}")
        # Don't fail the translation if caching fails
        :ok
    end
  end




  defp default_provider do
    "llm"
  end
end
