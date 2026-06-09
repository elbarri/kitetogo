defmodule Kite4rent.ResponseTemplates do
  @moduledoc """
  Manages response templates for different languages.
  Provides centralized template management with multilingual support.

  Templates are loaded from YAML files in priv/templates/ at compile time.
  """

  @template_dir Path.join(:code.priv_dir(:kite4rent) |> to_string(), "templates")

  @default_radius_km Integer.to_string(
                       Application.compile_env(:kite4rent, [:geocoding, :default_radius_km], 25)
                     )

  # Load and merge all template YAML files at compile time (excluding gear_types.yml)
  @template_files Path.wildcard(Path.join(@template_dir, "*.yml"))
                  |> Enum.reject(&String.ends_with?(&1, "gear_types.yml"))

  for file <- @template_files do
    @external_resource file
  end

  @templates @template_files
             |> Enum.flat_map(fn file ->
               file
               |> YamlElixir.read_from_file!()
               |> Enum.map(fn {key, lang_map} ->
                 atomized_langs =
                   lang_map
                   |> Enum.map(fn {lang, text} ->
                     {String.to_atom(lang), String.trim_trailing(text)}
                   end)
                   |> Map.new()

                 {String.to_atom(key), atomized_langs}
               end)
             end)
             |> Map.new()

  # Load gear type translations
  @gear_types_file Path.join(@template_dir, "gear_types.yml")
  @external_resource @gear_types_file

  @gear_type_translations @gear_types_file
                          |> YamlElixir.read_from_file!()
                          |> Enum.map(fn {type, lang_map} ->
                            atomized =
                              lang_map
                              |> Enum.map(fn {lang, text} -> {String.to_atom(lang), text} end)
                              |> Map.new()

                            {type, atomized}
                          end)
                          |> Map.new()

  @doc """
  Get a template for a specific key and language.

  ## Parameters
  - `key`: The template key (atom)
  - `language`: The target language code (string, defaults to "en")
  - `substitutions`: A map of placeholder substitutions (optional)

  ## Returns
  - The template string in the requested language with substitutions applied
  - Falls back to English if the language is not available
  - Falls back to a default message if the key is not found

  ## Examples

      iex> Kite4rent.ResponseTemplates.get_template(:gear_offer_success, "es", %{location_name: "Barcelona"})
      "¡Genial!\\nTu equipo de kitesurf ahora aparecerá listado cuando alguien busque en Barcelona."

      iex> result = Kite4rent.ResponseTemplates.get_template(:gear_offer_success, "unknown")
      iex> result =~ "Awesome!"
      true

  """
  def get_template(key, language \\ "en", substitutions \\ %{})
      when is_atom(key) and is_binary(language) and is_map(substitutions) do
    template_map =
      Map.get(@templates, key, %{
        en: "Sorry, there was an issue processing your message.\nPlease try again."
      })

    # Convert language string to atom for map access and get base template
    {base_template, needs_translation} =
      try do
        language_atom = String.to_existing_atom(language)

        case Map.get(template_map, language_atom) do
          nil ->
            # Language atom exists but no template for this language, use English and translate
            english_template =
              Map.get(template_map, :en) ||
                "Sorry, there was an issue processing your message.\nPlease try again."

            {english_template, true}

          template ->
            # Found template in requested language
            {template, false}
        end
      rescue
        ArgumentError ->
          # Language atom doesn't exist, use English template and translate
          english_template =
            Map.get(template_map, :en) ||
              "Sorry, there was an issue processing your message.\nPlease try again."

          {english_template, true}
      end

    # Apply substitutions to base template
    processed_template =
      base_template
      |> apply_substitutions(substitutions)
      |> String.replace("__RADIUS__", @default_radius_km)

    # Translate if needed and language is a valid 2-3 letter ISO code
    # Skip translation for:
    # - "en" (already English)
    # - "un" (unknown language marker)
    # - Empty/nil languages
    # - Invalid language codes (not 2-3 characters)
    is_valid_language_code = is_binary(language) and String.length(language) in 2..3

    if needs_translation and is_valid_language_code and language not in ["en", "un"] do
      case Kite4rent.Translator.translate(processed_template, language) do
        {:ok, translated_text} -> translated_text
        # Fallback to English on translation failure
        {:error, _reason} -> processed_template
      end
    else
      processed_template
    end
  end

  defp apply_substitutions(template, substitutions) do
    Enum.reduce(substitutions, template, fn {key, value}, acc ->
      placeholder = "__#{String.upcase(to_string(key))}__"
      String.replace(acc, placeholder, to_string(value))
    end)
  end

  @doc """
  Get all available languages for a template key.

  ## Parameters
  - `key`: The template key (atom)

  ## Returns
  - List of available language codes for the template
  - Empty list if the key is not found

  ## Examples

      iex> Kite4rent.ResponseTemplates.available_languages(:gear_offer_success)
      ["de", "en", "es", "fr", "it", "nl"]

  """
  def available_languages(key) when is_atom(key) do
    @templates
    |> Map.get(key, %{})
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.sort()
  end

  @doc """
  Get all available template keys.

  ## Returns
  - List of all available template keys

  ## Examples

      iex> templates = Kite4rent.ResponseTemplates.available_templates()
      iex> :gear_offer_success in templates
      true
      iex> :location_updated in templates
      true

  """
  def available_templates do
    Map.keys(@templates)
  end

  @doc """
  Translates a gear type to the given language.
  "kite" always stays as "kite" in all languages.
  Returns capitalized English type as fallback for unknown types.
  """
  def translate_gear_type(type, language) when is_binary(type) do
    lang_atom = if is_binary(language), do: String.to_existing_atom(language), else: language

    case @gear_type_translations[String.downcase(type)] do
      %{} = translations -> Map.get(translations, lang_atom, String.capitalize(type))
      nil -> String.capitalize(type)
    end
  end

  def translate_gear_type(_, _), do: "gear"
end
