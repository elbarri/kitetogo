defmodule Kite4rent.Repo.Migrations.AddCurrencyToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :currency, :string, size: 3, null: false, default: "USD"
    end
  end
end
