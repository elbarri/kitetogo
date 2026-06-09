defmodule Kite4rent.Messages.MessageStatus do
  use Ecto.Schema
  import Ecto.Changeset

  schema "message_statuses" do
    field :status, :string
    field :timestamp, :utc_datetime
    field :message_id, :string
    field :phone_number, :string
    field :pricing, :map
    field :conversation, :map

    # Optional reference to the original message if it exists
    belongs_to :whatsapp_message, Kite4rent.Messages.WhatsappMessage,
      foreign_key: :original_message_id

    belongs_to :user, Kite4rent.Users.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message_status, attrs) do
    message_status
    |> cast(attrs, [
      :message_id,
      :status,
      :phone_number,
      :timestamp,
      :pricing,
      :conversation,
      :original_message_id,
      :user_id
    ])
    |> validate_required([:message_id, :status, :phone_number, :timestamp])
    |> validate_inclusion(:status, ["sent", "delivered", "read", "failed"])
    |> foreign_key_constraint(:original_message_id)
    |> foreign_key_constraint(:user_id)
  end
end
