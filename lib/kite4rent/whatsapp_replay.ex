defmodule Kite4rent.WhatsappReplay do
  @moduledoc """
  Module for replaying WhatsApp webhook messages for testing.
  """

  require Logger
  alias Kite4rentWeb.WhatsappController
  alias Plug.Conn

  # Sample WhatsApp webhook messages for testing
  @sample_messages [
    # ... existing code ...
  ]

  @doc """
  Replays a specific message from the sample messages.
  Useful for testing different message types.

  ## Examples

      iex> Kite4rent.WhatsappReplay.replay_message(0)  # Replay text message
      iex> Kite4rent.WhatsappReplay.replay_message(1)  # Replay audio message
      iex> Kite4rent.WhatsappReplay.replay_message(2)  # Replay location message
  """
  def replay_message(index)
      when is_integer(index) and index >= 0 and index < length(@sample_messages) do
    Logger.info("Starting to replay message #{index}")
    message = Enum.at(@sample_messages, index)

    Logger.info(
      "Message type: #{get_in(message, ["entry", Access.at(0), "changes", Access.at(0), "value", "messages", Access.at(0), "type"])}"
    )

    # Create a new connection
    Logger.info("Creating connection")

    conn =
      %Conn{}
      |> Conn.put_private(:phoenix_endpoint, Kite4rentWeb.Endpoint)
      |> Conn.put_private(:plug_skip_csrf_protection, true)
      |> Conn.put_req_header("content-type", "application/json")

    Logger.info("Connection created, sending to webhook")

    # Send the webhook request
    try do
      conn = WhatsappController.webhook(conn, message)
      Logger.info("Webhook processed successfully")
      {:ok, conn, message}
    rescue
      e ->
        Logger.error("Error processing webhook: #{inspect(e)}")
        {:error, :webhook_error}
    end
  end

  def replay_message(_index), do: {:error, :invalid_index}

  @doc """
  Replays all sample messages in sequence.
  Useful for testing the entire flow.

  ## Examples

      iex> Kite4rent.WhatsappReplay.replay_all_messages()
  """
  def replay_all_messages do
    Logger.info("Starting to replay all messages")
    results = Enum.map(0..(length(@sample_messages) - 1), &replay_message/1)
    Logger.info("Finished replaying all messages")
    {:ok, results}
  end
end
