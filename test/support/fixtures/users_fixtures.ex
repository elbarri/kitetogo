defmodule Kite4rent.UsersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Kite4rent.Users` context.
  """

  @doc """
  Generate a user.
  """
  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: "some email",
        name: "some name",
        whatsapp: "some whatsapp",
        language: "en"
      })
      |> Kite4rent.Users.create_user()

    user
  end
end
