defmodule Kite4rentWeb.HealthController do
  use Kite4rentWeb, :controller

  def index(conn, _params) do
    case Ecto.Adapters.SQL.query(Kite4rent.Repo, "SELECT 1") do
      {:ok, _} ->
        json(conn, %{status: "ok"})

      {:error, reason} ->
        conn
        |> put_status(503)
        |> json(%{status: "error", reason: inspect(reason)})
    end
  end
end
