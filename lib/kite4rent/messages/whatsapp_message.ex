defmodule Kite4rent.Messages.WhatsappMessage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "whatsapp_messages" do
    field :message_id, :string
    field :phone_number, :string
    field :timestamp, :utc_datetime
    # JSONB field storing message-specific data based on type
    field :content, :map
    # JSONB field for contextual data (e.g., reply context)
    field :context, :map
    field :wa_id, :string
    # true for incoming, false for outgoing
    field :is_incoming, :boolean, default: true

    # Direct type field (text, image, audio, video, document, sticker, location, contacts, button, interactive)
    field :type, :string

    belongs_to :user, Kite4rent.Users.User

    # Statuses related to this message
    has_many :message_statuses, Kite4rent.Messages.MessageStatus,
      foreign_key: :original_message_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :message_id,
      :phone_number,
      :timestamp,
      :content,
      :context,
      :wa_id,
      :type,
      :user_id,
      :is_incoming
    ])
    |> validate_required([
      :message_id,
      :phone_number,
      :timestamp,
      :content,
      :wa_id,
      :is_incoming,
      :type
    ])
    |> validate_length(:message_id, max: 100)
    |> validate_length(:phone_number, max: 30)
    |> validate_length(:wa_id, max: 50)
    |> validate_length(:type, max: 20)
    |> validate_inclusion(:type, [
      "audio",
      "button",
      "contacts",
      "document",
      "image",
      "interactive",
      "location",
      "reaction",
      "status",
      "sticker",
      "system",
      "template",
      "text",
      "video",
      "unsupported",
      "order"  # WhatsApp Order/Commerce messages
    ])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:message_id, name: :whatsapp_messages_message_id_unique_index)
  end

  @doc """
  Changeset for status messages that don't require user_id
  """
  def status_changeset(message, attrs) do
    message
    |> cast(attrs, [
      :message_id,
      :phone_number,
      :timestamp,
      :content,
      :context,
      :wa_id,
      :type,
      :user_id,
      :is_incoming
    ])
    |> validate_required([
      :message_id,
      :phone_number,
      :timestamp,
      :content,
      :wa_id,
      :is_incoming,
      :type
    ])
    |> validate_length(:message_id, max: 100)
    |> validate_length(:phone_number, max: 30)
    |> validate_length(:wa_id, max: 50)
    |> validate_length(:type, max: 20)
    |> validate_inclusion(:type, [
      "text",
      "image",
      "audio",
      "video",
      "document",
      "sticker",
      "location",
      "contacts",
      "button",
      "interactive",
      "status",
      "system",
      "reaction",
      "template"
    ])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:message_id, name: :whatsapp_messages_message_id_unique_index)
  end
end
