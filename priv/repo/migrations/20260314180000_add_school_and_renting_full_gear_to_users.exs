defmodule Kite4rent.Repo.Migrations.AddSchoolAndRentingFullGearToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_school, :boolean, default: false, null: false
      add :is_renting_full_gear, :boolean, default: false, null: false
    end
  end
end
