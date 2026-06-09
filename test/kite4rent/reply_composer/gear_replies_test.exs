defmodule Kite4rent.ReplyComposer.GearRepliesTest do
  use Kite4rent.DataCase, async: true
  import Mimic

  alias Kite4rent.IntentionHandler.RequestGear
  alias Kite4rent.ReplyComposer.GearReplies
  import Kite4rent.UsersFixtures

  describe "compose_reply/2 for request_gear results" do
    test "school user gets school location label" do
      requesting_user = user_fixture(%{language: "en"})

      school_user =
        user_fixture(%{
          whatsapp: "+1111111111",
          name: "Kite School Tarifa",
          is_school: true,
          is_renting_full_gear: true,
          contact_sharing_consent: true,
          location_name: "Tarifa"
        })

      request_gear = %RequestGear{
        location_name: "Tarifa",
        users_with_gear: [%{user: school_user, gear: []}]
      }

      stub(Kite4rent.Repo, :preload, fn data, _ -> data end)

      {:ok, {:text, message}, _extra} = GearReplies.compose_reply(request_gear, requesting_user)

      assert message =~ "Kite school - Tarifa"
      assert message =~ "Full gear rental"
      assert message =~ "Kite School Tarifa"
    end

    test "non-school full gear user shows full gear label without school label" do
      requesting_user = user_fixture(%{language: "en"})

      full_gear_user =
        user_fixture(%{
          whatsapp: "+2222222222",
          name: "Pedro",
          is_school: false,
          is_renting_full_gear: true,
          contact_sharing_consent: true,
          location_name: "Tarifa"
        })

      request_gear = %RequestGear{
        location_name: "Tarifa",
        users_with_gear: [%{user: full_gear_user, gear: []}]
      }

      stub(Kite4rent.Repo, :preload, fn data, _ -> data end)

      {:ok, {:text, message}, _extra} = GearReplies.compose_reply(request_gear, requesting_user)

      assert message =~ "Full gear rental"
      assert message =~ "(Tarifa)"
      refute message =~ "Kite school"
    end

    test "regular user without school or full gear flags shows only gear" do
      requesting_user = user_fixture(%{language: "en"})

      regular_user =
        user_fixture(%{
          whatsapp: "+3333333333",
          name: "Maria",
          is_school: false,
          is_renting_full_gear: false,
          contact_sharing_consent: true,
          location_name: "Tarifa"
        })

      gear_item = %{
        type: "kite",
        brand: "North",
        model: "Reach",
        size: "12",
        year: "2023",
        gender: nil
      }

      request_gear = %RequestGear{
        location_name: "Tarifa",
        users_with_gear: [%{user: regular_user, gear: [gear_item]}]
      }

      stub(Kite4rent.Repo, :preload, fn data, _ -> data end)

      {:ok, {:text, message}, _extra} = GearReplies.compose_reply(request_gear, requesting_user)

      assert message =~ "Maria"
      assert message =~ "(Tarifa)"
      refute message =~ "Full gear rental"
      refute message =~ "Kite school"
    end
  end
end
