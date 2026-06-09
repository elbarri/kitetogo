defmodule Kite4rent.Repo.Migrations.CreateGearModels do
  use Ecto.Migration

  def change do
    create table(:gear_models) do
      add :model_name, :string, null: false
      add :brand, :string, null: false
      add :gear_type, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # Unique index to prevent duplicates (case-insensitive)
    create unique_index(:gear_models, ["lower(model_name)", "lower(brand)", :gear_type],
      name: :gear_models_model_brand_type_unique
    )

    # Fast lookup by model name only (gear_type not always known)
    create index(:gear_models, ["lower(model_name)"],
      name: :gear_models_model_name_lookup
    )
  end
end
