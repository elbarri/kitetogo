defmodule Kite4rent.IntentionHandlerTest do
  use ExUnit.Case
  use Mimic
  use Kite4rent.DataCase

  alias Kite4rent.IntentionHandler
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.Repo
  alias Kite4rent.Rental.Gear
  alias Kite4rent.Users.User

  # Mock all the dependencies
  setup :verify_on_exit!

  setup do
    # Start a transaction
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    # Create a test user
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        whatsapp: "+1234567890",
        name: "Test User"
      })
      |> Repo.insert()

    default_radius = Application.get_env(:kite4rent, :geocoding, [])[:default_radius_km] || 25
    {:ok, user: user, default_radius: default_radius}
  end

  describe "handle/2" do
    @tag :request_gear_direct
    test "handles request_gear intention correctly", %{user: user} do
      # Test the handle function directly
      llm_response = %LLMResponse{
        intention: "request_gear",
        location: "Miami",
        location_radius_km: 15
      }

      # Create mock users with consent
      user1 = %User{
        id: 2,
        name: "Owner 1",
        whatsapp: "+1111111111",
        contact_sharing_consent: true
      }

      user2 = %User{
        id: 3,
        name: "Owner 2",
        whatsapp: "+2222222222",
        contact_sharing_consent: true
      }

      # Mock finding users near location
      expect(Kite4rent.Users, :find_users_near, fn %Kite4rent.Location{} = location ->
        assert location.name == "Miami"
        assert location.radius_km == 15
        [user1, user2]
      end)

      # Mock gear listings
      gear1 = [%Gear{id: 1, type: "kite", brand: "Test", user_id: 2}]
      gear2 = [%Gear{id: 2, type: "board", brand: "Test", user_id: 3}]

      # Mock Repo.preload for the optimization
      expect(Kite4rent.Repo, :preload, fn users, :kite_gear ->
        Enum.map(users, fn user ->
          case user.id do
            2 -> %{user | kite_gear: gear1}
            3 -> %{user | kite_gear: gear2}
          end
        end)
      end)

      {:ok, {request_gear, _user}} =
        IntentionHandler.handle(llm_response, user)

      assert length(request_gear.users_with_gear) == 2

      assert Enum.all?(request_gear.users_with_gear, fn item ->
               Map.has_key?(item, :user) and Map.has_key?(item, :gear)
             end)

      assert request_gear.location_name == "Miami"
      assert request_gear.radius_km == 15
    end

    @tag :request_gear_direct
    test "filters out users with no gear", %{user: user, default_radius: default_radius} do
      llm_response = %LLMResponse{
        intention: "request_gear",
        location: "Barcelona"
      }

      # Create mock users with consent
      user1 = %User{
        id: 2,
        name: "Owner 1",
        whatsapp: "+1111111111",
        contact_sharing_consent: true
      }

      user2 = %User{
        id: 3,
        name: "No Gear Owner",
        whatsapp: "+2222222222",
        contact_sharing_consent: true
      }

      # Mock finding users near location with default radius
      expect(Kite4rent.Users, :find_users_near, fn %Kite4rent.Location{} = location ->
        assert location.name == "Barcelona"
        assert location.radius_km == default_radius
        [user1, user2]
      end)

      # Mock gear listings - user1 has gear, user2 has no gear
      gear1 = [%Gear{id: 1, type: "kite", brand: "Test", user_id: 2}]
      gear2 = []

      # Mock Repo.preload for the optimization
      expect(Kite4rent.Repo, :preload, fn users, :kite_gear ->
        Enum.map(users, fn user ->
          case user.id do
            2 -> %{user | kite_gear: gear1}
            3 -> %{user | kite_gear: gear2}
          end
        end)
      end)

      {:ok, {request_gear, _user}} =
        IntentionHandler.handle(llm_response, user)

      # Should only return user1 (user2 filtered out due to no gear)
      assert length(request_gear.users_with_gear) == 1
      assert hd(request_gear.users_with_gear).user.id == 2
      assert length(hd(request_gear.users_with_gear).gear) == 1

      assert request_gear.location_name == "Barcelona"
      assert request_gear.radius_km == default_radius
    end

    @tag :capture_log
    test "handles unsupported intentions", %{user: user} do
      llm_response = %LLMResponse{
        intention: "unsupported_intention"
      }

      result = IntentionHandler.handle(llm_response, user)

      assert {:error, :intention_not_yet_supported} = result
    end

    test "handles list_own_inventory intention correctly", %{user: user} do
      llm_response = %LLMResponse{
        intention: "list_own_inventory"
      }

      # Mock gear for the user
      gear_list = [
        %Gear{
          id: 1,
          type: "kite",
          brand: "Duotone",
          model: "Evo",
          size: "12m",
          year: "2023",
          user_id: user.id
        },
        %Gear{id: 2, type: "board", brand: "North", model: "X-Ride", user_id: user.id}
      ]

      expect(Kite4rent.Rental, :list_available_gear_for_user, fn user_id ->
        assert user_id == user.id
        {:ok, gear_list}
      end)

      {:ok, {:list_own_inventory, gear_items, returned_user}} =
        IntentionHandler.handle(llm_response, user)

      assert gear_items == gear_list
      assert returned_user == user
    end

    test "does not apply labels (label application moved to MessageProcessor)", %{user: user} do
      llm_response = %LLMResponse{
        intention: "list_own_inventory",
        is_school: true,
        offers_full_gear: true
      }

      expect(Kite4rent.Rental, :list_available_gear_for_user, fn _user_id ->
        {:ok, []}
      end)

      {:ok, {:list_own_inventory, _, returned_user}} =
        IntentionHandler.handle(llm_response, user)

      # Labels should NOT be applied here — that's now MessageProcessor's job
      assert returned_user.is_school == false
      assert returned_user.is_renting_full_gear == false
    end

    test "handles list_own_inventory with empty gear list", %{user: user} do
      llm_response = %LLMResponse{
        intention: "list_own_inventory"
      }

      expect(Kite4rent.Rental, :list_available_gear_for_user, fn user_id ->
        assert user_id == user.id
        {:ok, []}
      end)

      {:ok, {:list_own_inventory, gear_items, returned_user}} =
        IntentionHandler.handle(llm_response, user)

      assert gear_items == []
      assert returned_user == user
    end
  end
end
