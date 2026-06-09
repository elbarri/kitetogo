defmodule Kite4rent.Repo.Migrations.RemoveMessageStatusUniqueConstraint do
  use Ecto.Migration

  def change do
    # Remove the unique constraint that prevents multiple status updates for the same message
    # According to WhatsApp API documentation, the same message can have multiple status updates
    # of the same type (e.g., multiple "sent" statuses due to retries or different delivery attempts).
    # The application now handles duplicates gracefully by checking for existing status records
    # with the same message_id, status, and timestamp before creating new ones.
    drop_if_exists unique_index(:message_statuses, [:message_id, :status],
                     name: :message_statuses_message_id_status_index
                   )
  end
end
