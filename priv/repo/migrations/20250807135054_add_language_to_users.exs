defmodule Kite4rent.Repo.Migrations.AddLanguageToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :language, :string, size: 2, default: "en"
    end
  end
end
