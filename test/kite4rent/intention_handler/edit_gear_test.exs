defmodule Kite4rent.IntentionHandler.EditGearTest do
  use Kite4rent.DataCase

  alias Kite4rent.IntentionHandler.EditGear
  alias Kite4rent.Messages.LLMResponse

  defp edit_gear_response do
    %LLMResponse{
      intention: "edit_gear",
      gear: [],
      location: nil,
      location_radius_km: nil,
      language: "en"
    }
  end

  describe "handle_intention/2" do
    test "returns edit_gear_no_items when user has no gear" do
      user = Kite4rent.UsersFixtures.user_fixture()

      assert {:ok, {:edit_gear_no_items, nil, %Kite4rent.Users.User{}}} =
               EditGear.handle_intention(edit_gear_response(), user)
    end

    test "goes directly to field selection with single gear item" do
      user = Kite4rent.UsersFixtures.user_fixture()
      gear = Kite4rent.RentalFixtures.gear_fixture(%{user_id: user.id})

      assert {:ok, {:edit_gear_select_field, returned_gear, %Kite4rent.Users.User{}}} =
               EditGear.handle_intention(edit_gear_response(), user)

      assert returned_gear.id == gear.id
    end

    test "shows item list with multiple gear items" do
      user = Kite4rent.UsersFixtures.user_fixture()
      _gear1 = Kite4rent.RentalFixtures.gear_fixture(%{user_id: user.id})
      _gear2 = Kite4rent.RentalFixtures.gear_fixture(%{user_id: user.id, model: "other model"})

      assert {:ok, {:edit_gear_select_item, gear_list, %Kite4rent.Users.User{}}} =
               EditGear.handle_intention(edit_gear_response(), user)

      assert length(gear_list) == 2
    end

    test "returns error for invalid intention" do
      user = Kite4rent.UsersFixtures.user_fixture()

      wrong_response = %LLMResponse{
        intention: "offer_gear",
        gear: [],
        location: nil,
        location_radius_km: nil,
        language: "en"
      }

      assert {:error, :invalid_intention_for_handler} =
               EditGear.handle_intention(wrong_response, user)
    end
  end
end
