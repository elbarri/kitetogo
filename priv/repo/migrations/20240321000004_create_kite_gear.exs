defmodule Kite4rent.Repo.Migrations.CreateKiteGear do
  use Ecto.Migration

  def change do
    create table(:kite_gear) do
      add :type, :string
      add :model, :string
      add :brand, :string
      add :year, :string
      add :size, :string
      add :condition, :string
      add :additional_details, :string
      add :user_id, references(:users, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:kite_gear, [:user_id])
  end
end
