defmodule Kite4rent.LocationNotFoundIntegrationTest do
  use Kite4rent.DataCase, async: true
  import Mimic

  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.IntentionHandler
  alias Kite4rent.ReplyComposer
  import Kite4rent.UsersFixtures

  setup do
    default_radius = Application.get_env(:kite4rent, :geocoding, [])[:default_radius_km] || 25
    %{default_radius: default_radius}
  end

  test "complete flow: location_not_found error is properly handled and user gets helpful message", %{default_radius: default_radius} do
    user = user_fixture()

    llm_response = %LLMResponse{
      intention: "request_gear",
      location: "NonExistentPlace",
      location_radius_km: default_radius,
      language: "en"
    }

    # Mock Users.find_users_near to raise LocationNotFoundError
    expect(Kite4rent.Users, :find_users_near, fn _location ->
      raise Kite4rent.LocationNotFoundError, location_name: "NonExistentPlace"
    end)

    # Test the complete flow
    case IntentionHandler.handle(llm_response, user) do
      {:error, {:location_not_found, location_name}} ->
        # Now test that the error is properly composed into a user-friendly message
        {:ok, {:text, reply}} =
          ReplyComposer.compose_reply(
            {:error, {:location_not_found, location_name}},
            user
          )

        # Verify the message is helpful and contains the location name
        assert is_binary(reply)
        assert reply =~ "NonExistentPlace"

        assert String.contains?(String.downcase(reply), "couldn't find") or
                 String.contains?(String.downcase(reply), "not found")

        assert String.contains?(String.downcase(reply), "check the spelling") or
                 String.contains?(String.downcase(reply), "try a different")

      other ->
        flunk("Expected {:error, {:location_not_found, location_name}}, got: #{inspect(other)}")
    end
  end

  test "location_not_found error in Spanish", %{default_radius: default_radius} do
    user = user_fixture() |> Map.put(:language, "es")

    llm_response = %LLMResponse{
      intention: "request_gear",
      location: "LugarInexistente",
      location_radius_km: default_radius,
      language: "es"
    }

    # Mock Users.find_users_near to raise LocationNotFoundError
    expect(Kite4rent.Users, :find_users_near, fn _location ->
      raise Kite4rent.LocationNotFoundError, location_name: "LugarInexistente"
    end)

    case IntentionHandler.handle(llm_response, user) do
      {:error, {:location_not_found, location_name}} ->
        {:ok, {:text, reply}} =
          ReplyComposer.compose_reply(
            {:error, {:location_not_found, location_name}},
            user
          )

        # Verify the Spanish message
        assert is_binary(reply)
        assert reply =~ "LugarInexistente"

        assert String.contains?(String.downcase(reply), "no pude encontrar") or
                 String.contains?(String.downcase(reply), "ubicación")

      other ->
        flunk("Expected {:error, {:location_not_found, location_name}}, got: #{inspect(other)}")
    end
  end
end
