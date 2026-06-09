defmodule Kite4rent.IntentionHandler.RequestGearTest do
  use Kite4rent.DataCase, async: true
  import Mimic

  alias Kite4rent.IntentionHandler.RequestGear
  alias Kite4rent.Messages.LLMResponse
  import Kite4rent.UsersFixtures

  setup do
    default_radius = Application.get_env(:kite4rent, :geocoding, [])[:default_radius_km] || 25
    %{default_radius: default_radius}
  end

  describe "handle_intention/2" do
    @tag :capture_log
    test "handles location_not_found error gracefully", %{default_radius: default_radius} do
      user = user_fixture()

      llm_response = %LLMResponse{
        intention: "request_gear",
        location: "NonExistentPlace",
        location_radius_km: default_radius
      }

      # Mock Users.find_users_near to raise LocationNotFoundError
      expect(Kite4rent.Users, :find_users_near, fn _location ->
        raise Kite4rent.LocationNotFoundError, location_name: "NonExistentPlace"
      end)

      result = RequestGear.handle_intention(llm_response, user)

      assert {:error, {:location_not_found, "NonExistentPlace"}} = result
    end

    @tag :capture_log
    test "handles other geocoding errors", %{default_radius: default_radius} do
      user = user_fixture()

      llm_response = %LLMResponse{
        intention: "request_gear",
        location: "SomePlace",
        location_radius_km: default_radius
      }

      # Mock Users.find_users_near to raise a different error
      expect(Kite4rent.Users, :find_users_near, fn _location ->
        raise "Network errorr"
      end)

      result = RequestGear.handle_intention(llm_response, user)

      assert {:error, {:search_failed, %RuntimeError{message: "Network errorr"}}} = result
    end

    @tag :capture_log
    test "includes full gear renters without kite_gear items", %{default_radius: default_radius} do
      requesting_user = user_fixture()

      full_gear_user =
        user_fixture(%{
          whatsapp: "+1234567890",
          name: "Full Gear School",
          is_renting_full_gear: true,
          is_school: true,
          contact_sharing_consent: true,
          location_name: "Tarifa"
        })

      llm_response = %LLMResponse{
        intention: "request_gear",
        location: "Tarifa",
        location_radius_km: default_radius
      }

      expect(Kite4rent.Users, :find_users_near, fn _location ->
        [full_gear_user]
      end)

      expect(Kite4rent.Repo, :preload, fn users, :kite_gear ->
        Enum.map(users, fn u -> %{u | kite_gear: []} end)
      end)

      result = RequestGear.handle_intention(llm_response, requesting_user)

      assert {:ok, {%RequestGear{users_with_gear: users_with_gear}, _user}} = result
      assert length(users_with_gear) == 1
      assert hd(users_with_gear).user.name == "Full Gear School"
      assert hd(users_with_gear).user.is_renting_full_gear == true
    end

    @tag :capture_log
    test "excludes users without gear and without full gear flag", %{default_radius: default_radius} do
      requesting_user = user_fixture()

      regular_user =
        user_fixture(%{
          whatsapp: "+9876543210",
          name: "Regular User",
          is_renting_full_gear: false,
          contact_sharing_consent: true
        })

      llm_response = %LLMResponse{
        intention: "request_gear",
        location: "Tarifa",
        location_radius_km: default_radius
      }

      expect(Kite4rent.Users, :find_users_near, fn _location ->
        [regular_user]
      end)

      expect(Kite4rent.Repo, :preload, fn users, :kite_gear ->
        Enum.map(users, fn u -> %{u | kite_gear: []} end)
      end)

      result = RequestGear.handle_intention(llm_response, requesting_user)

      assert {:ok, {%RequestGear{users_with_gear: []}, _user}} = result
    end
  end
end
