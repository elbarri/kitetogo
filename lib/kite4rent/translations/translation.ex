defmodule Kite4rent.Translations.Translation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "translations" do
    field :source_text, :string
    field :source_language, :string
    field :target_language, :string
    field :translated_text, :string
    field :provider, :string, default: "libretranslate"
    field :text_hash, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(translation, attrs) do
    translation
    |> cast(attrs, [
      :source_text,
      :source_language,
      :target_language,
      :translated_text,
      :provider,
      :text_hash
    ])
    |> validate_required([
      :source_text,
      :source_language,
      :target_language,
      :translated_text,
      :provider,
      :text_hash
    ])
    |> validate_length(:source_language, max: 10)
    |> validate_length(:target_language, max: 10)
    |> unique_constraint([:text_hash, :source_language, :target_language],
      name: :translations_cache_index
    )
  end

  @doc """
  Generate a hash for the source text to use in unique constraints
  """
  def generate_hash(text) do
    :crypto.hash(:sha256, String.trim(text))
    |> Base.encode16()
    |> String.downcase()
  end
end
