defmodule Kite4rent.Repo.Migrations.CreateTranslations do
  use Ecto.Migration

  def change do
    create table(:translations) do
      add :source_text, :text, null: false
      add :source_language, :string, null: false, size: 10
      add :target_language, :string, null: false, size: 10
      add :translated_text, :text, null: false
      add :provider, :string, null: false, default: "libretranslate"
      add :text_hash, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # Unique index for caching - same text/source/target should have one translation
    create unique_index(:translations, [:text_hash, :source_language, :target_language],
             name: :translations_cache_index
           )

    # Index for querying by languages
    create index(:translations, [:source_language, :target_language])

    # Index for provider queries
    create index(:translations, [:provider])
  end
end
