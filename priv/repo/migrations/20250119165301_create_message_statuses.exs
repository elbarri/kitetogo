defmodule Kite4rent.Repo.Migrations.CreateMessageStatuses do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:message_statuses) do
      add :message_id, :string, null: false
      add :status, :string, null: false
      add :phone_number, :string, null: false
      add :timestamp, :utc_datetime, null: false
      add :pricing, :map
      add :conversation, :map

      # Foreign keys
      # Note: original_message_id reference to whatsapp_messages will be added in refactor migration
      add :original_message_id, :bigint
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # Indexes for better query performance
    create_if_not_exists index(:message_statuses, [:message_id])
    create_if_not_exists index(:message_statuses, [:phone_number])
    create_if_not_exists index(:message_statuses, [:status])
    create_if_not_exists index(:message_statuses, [:timestamp])
    create_if_not_exists index(:message_statuses, [:user_id])
    create_if_not_exists index(:message_statuses, [:original_message_id])

    # Ensure we don't have duplicate status entries for the same message
    create_if_not_exists unique_index(:message_statuses, [:message_id, :status],
                           name: :message_statuses_message_id_status_index
                         )
  end
end
