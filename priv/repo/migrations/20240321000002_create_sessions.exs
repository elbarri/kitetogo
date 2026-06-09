defmodule Kite4rent.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions) do
      add :first_at, :utc_datetime
      add :last_at, :utc_datetime
      add :states, {:array, :string}
      add :user_id, references(:users, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:sessions, [:user_id])
  end
end
