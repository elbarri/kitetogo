defmodule Kite4rent.Repo.Migrations.AddUniqueConstraintToWhatsappMessagesMessageId do
  use Ecto.Migration

  def up do
    # First, remove any duplicate message_id entries by keeping only the most recent one
    execute """
    DELETE FROM whatsapp_messages
    WHERE id NOT IN (
      SELECT MAX(id)
      FROM whatsapp_messages
      GROUP BY message_id
    )
    """

    # Add unique constraint to message_id
    create_if_not_exists unique_index(:whatsapp_messages, [:message_id],
                           name: :whatsapp_messages_message_id_unique_index
                         )
  end

  def down do
    drop_if_exists unique_index(:whatsapp_messages, [:message_id],
                     name: :whatsapp_messages_message_id_unique_index
                   )
  end
end
