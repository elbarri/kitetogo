defmodule Kite4rent.Repo.Migrations.RemoveSessions do
  use Ecto.Migration

  def up do
    # Remove session_id foreign key from whatsapp_messages table
    drop constraint(:whatsapp_messages, "whatsapp_messages_session_id_fkey")
    drop index(:whatsapp_messages, [:session_id])

    alter table(:whatsapp_messages) do
      remove :session_id
    end

    # Drop the sessions table
    drop table(:sessions)
  end

  def down do
    # Recreate sessions table
    create table(:sessions) do
      add :first_at, :utc_datetime
      add :last_at, :utc_datetime
      add :states, {:array, :string}
      add :user_id, references(:users, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:sessions, [:user_id])

    # Add session_id back to whatsapp_messages
    alter table(:whatsapp_messages) do
      add :session_id, references(:sessions, on_delete: :nothing)
    end

    create index(:whatsapp_messages, [:session_id])
  end
end
