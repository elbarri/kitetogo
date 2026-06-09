defmodule Kite4rent.RentalFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Kite4rent.Rental` context.
  """

  alias Kite4rent.Users.User

  @doc """
  Generate a gear.
  """
  def gear_fixture(attrs \\ %{}) do
    user =
      %User{
        name: "Test User",
        email: "test@example.com",
        whatsapp: "1234567890"
      }
      |> Kite4rent.Repo.insert!()

    # Set default values based on type
    type = Map.get(attrs, :type, "board")
    default_size = if type == "kite", do: "12", else: "139x42"

    {:ok, gear} =
      attrs
      |> Enum.into(%{
        additional_details: "some additional_details",
        brand: "some brand",
        condition: "some condition",
        model: "some model",
        size: default_size,
        type: type,
        year: "2021",
        user_id: user.id
      })
      |> Kite4rent.Rental.create_gear()

    gear
  end
end
