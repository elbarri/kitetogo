defmodule Kite4rent.Repo.Migrations.AddValueToKiteGears do
  use Ecto.Migration

  def change do
    alter table(:kite_gear) do
      add :value, :integer, null: false, default: 0
    end
  end
end
