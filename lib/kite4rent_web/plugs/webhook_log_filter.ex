defmodule Kite4rentWeb.Plugs.WebhookLogFilter do
  @moduledoc """
  Plug that reduces logging noise for WhatsApp status update webhooks.
  Status updates (delivered, read, etc.) are frequent and create a lot of log noise.

  Since Phoenix route logging is disabled for webhooks (log: false),
  this plug logs non-status webhooks manually.
  """

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    if status_only_webhook?(conn) do
      # Status-only webhook - don't log anything
      conn
    else
      # Regular message webhook - log it manually since route has log: false
      Logger.debug(
        "Processing WhatsApp webhook\n" <>
          "  Parameters: #{inspect(conn.params)}\n" <>
          "  Pipelines: [:whatsapp_webhook]"
      )
      conn
    end
  end

  # Check if this is a status-only WhatsApp webhook (no actual messages)
  defp status_only_webhook?(conn) do
    case conn.body_params do
      %{"entry" => [%{"changes" => [%{"value" => value}]}]} ->
        # Has statuses but no messages = status-only update
        Map.has_key?(value, "statuses") && !Map.has_key?(value, "messages")

      _ ->
        false
    end
  end
end
