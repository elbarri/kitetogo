defmodule Kite4rent.Repo.Migrations.AddLastUsedFullnameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :last_used_fullname, :string
    end
  end
end
