defmodule Kite4rent.Repo do
  use Ecto.Repo,
    otp_app: :kite4rent,
    adapter: Ecto.Adapters.Postgres
end
