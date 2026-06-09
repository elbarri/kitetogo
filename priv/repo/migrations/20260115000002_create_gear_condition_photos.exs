defmodule Kite4rent.Repo.Migrations.CreateGearConditionPhotos do
  use Ecto.Migration

  def change do
    create table(:gear_condition_photos) do
      add :rental_agreement_id, references(:rental_agreements, on_delete: :delete_all), null: false
      add :gear_id, references(:kite_gear, on_delete: :nilify_all)

      add :file_path, :string, null: false
      add :description, :text
      add :uploaded_by_id, references(:users, on_delete: :nilify_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:gear_condition_photos, [:rental_agreement_id])
    create index(:gear_condition_photos, [:gear_id])
  end
end
