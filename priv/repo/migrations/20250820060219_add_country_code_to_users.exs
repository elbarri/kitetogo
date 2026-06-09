defmodule Kite4rent.Repo.Migrations.AddCountryCodeToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :country_code, :string, size: 2
    end
  end
end
