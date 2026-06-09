defmodule Kite4rent.MessagesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Kite4rent.Messages` context.
  """

  @doc """
  Generate a message_status.
  """
  def message_status_fixture(attrs \\ %{}) do
    {:ok, message_status} =
      attrs
      |> Enum.into(%{
        conversation: %{},
        message_id: "some message_id",
        phone_number: "some phone_number",
        pricing: %{},
        status: "sent",
        timestamp: ~U[2025-06-18 16:53:00Z]
      })
      |> Kite4rent.Messages.create_message_status()

    message_status
  end
end
