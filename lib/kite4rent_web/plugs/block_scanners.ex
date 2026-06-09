defmodule Kite4rentWeb.Plugs.BlockScanners do
  @moduledoc """
  Plug that short-circuits requests from bot scanners probing for common
  vulnerability paths (WordPress, PHP, etc.). Returns 404 immediately
  to avoid waking up the full Phoenix pipeline and database connections.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if scanner_path?(conn.request_path) do
      conn
      |> send_resp(404, "Not Found")
      |> halt()
    else
      conn
    end
  end

  defp scanner_path?(path) do
    downcased = String.downcase(path)

    String.ends_with?(downcased, ".php") or
      String.starts_with?(downcased, "/wp-") or
      String.starts_with?(downcased, "/wordpress") or
      String.starts_with?(downcased, "/.env") or
      String.starts_with?(downcased, "/cgi-bin") or
      String.starts_with?(downcased, "/admin") or
      String.starts_with?(downcased, "/phpmyadmin") or
      String.starts_with?(downcased, "/.git") or
      String.starts_with?(downcased, "/.aws") or
      String.starts_with?(downcased, "/.well-known/security.txt") or
      downcased == "/xmlrpc.php" or
      downcased == "/config.json" or
      downcased == "/telescope/requests" or
      downcased == "/.ds_store"
  end
end
