defmodule Kite4rent.Repo.Migrations.CreateSecurityDepositItems do
  use Ecto.Migration

  def change do
    create table(:security_deposit_items) do
      add :security_deposit_id, references(:security_deposits, on_delete: :delete_all), null: false
      add :gear_id, references(:kite_gear, on_delete: :restrict), null: false
      add :declared_value, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:security_deposit_items, [:security_deposit_id, :gear_id])
    create index(:security_deposit_items, [:gear_id])
  end
end
