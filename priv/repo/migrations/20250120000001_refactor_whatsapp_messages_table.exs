defmodule Kite4rent.Repo.Migrations.RefactorWhatsappMessagesTable do
  use Ecto.Migration
  import Ecto.Migration

  def up do
    # Create the whatsapp_messages table if it doesn't exist
    create_if_not_exists table(:whatsapp_messages) do
      add :message_id, :string, size: 100, null: false
      add :phone_number, :string, size: 30, null: false
      add :timestamp, :utc_datetime, null: false
      add :content, :map, null: false
      add :context, :map
      add :wa_id, :string, size: 50, null: false
      add :is_incoming, :boolean, null: false, default: true
      add :type, :string, size: 20, null: false
      add :user_id, references(:users, on_delete: :nothing), null: false
      add :session_id, references(:sessions, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    # Create indexes if they don't exist
    create_if_not_exists index(:whatsapp_messages, [:user_id])
    create_if_not_exists index(:whatsapp_messages, [:phone_number])
    create_if_not_exists index(:whatsapp_messages, [:session_id])
    create_if_not_exists index(:whatsapp_messages, [:message_id])
    create_if_not_exists index(:whatsapp_messages, [:type])
  end

  def down do
    # Note: This migration is not reversible due to the complete table refactor
    # If you need to rollback, you would need to restore from backup
    raise "This migration cannot be rolled back due to complete table refactor"
  end
end
