defmodule Kite4rent.Repo.Migrations.AddGenderToGear do
  use Ecto.Migration

  def change do
    alter table(:kite_gear) do
      add :gender, :string
    end
  end
end
