defmodule Kite4rent.Repo.Migrations.AddGearSnapshotToDepositItems do
  use Ecto.Migration

  def change do
    alter table(:security_deposit_items) do
      # Snapshot fields to preserve gear state at deposit creation time
      add :gear_type, :string
      add :gear_brand, :string
      add :gear_model, :string
      add :gear_size, :string
      add :gear_year, :string
    end

    # Drop the old foreign key constraint with on_delete: :restrict
    drop constraint(:security_deposit_items, "security_deposit_items_gear_id_fkey")

    # Make gear_id nullable and change on_delete to :nilify_all
    alter table(:security_deposit_items) do
      modify :gear_id, references(:kite_gear, on_delete: :nilify_all), null: true
    end

    # Backfill existing records with gear snapshot data
    execute(
      """
      UPDATE security_deposit_items
      SET gear_type = kg.type,
          gear_brand = kg.brand,
          gear_model = kg.model,
          gear_size = kg.size,
          gear_year = kg.year
      FROM kite_gear kg
      WHERE security_deposit_items.gear_id = kg.id
      """,
      # Rollback: no-op, data will be lost but that's acceptable
      "SELECT 1"
    )
  end
end
