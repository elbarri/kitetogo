defmodule Kite4rent.MessageProcessor.Flows.GearEditTest do
  use Kite4rent.DataCase

  alias Kite4rent.Conversation.Manager, as: FlowManager
  alias Kite4rent.MessageProcessor.Flows.GearEdit
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.Rental

  defp create_user_with_gear do
    user = Kite4rent.UsersFixtures.user_fixture()

    {:ok, gear} =
      Rental.create_gear(%{
        type: "kite",
        brand: "Slingshot",
        model: "RPM",
        size: "11m",
        year: "2023",
        user_id: user.id
      })

    {user, gear}
  end

  describe "handle_gear_edit_selection/1" do
    test "selects gear item and advances to selecting_field step" do
      {user, gear} = create_user_with_gear()

      FlowManager.start_flow(user.id, :gear_edit, :selecting_item, initial_data: %{})

      message = %WhatsappMessage{
        type: "interactive",
        user: user,
        content: %{
          "type" => "list_reply",
          "list_reply" => %{"id" => "edit_gear_#{gear.id}"}
        }
      }

      assert {:handled, {:ok, {:interactive_reply_buttons, _body, buttons}}} =
               GearEdit.handle_gear_edit_selection(message)

      assert length(buttons) == 3
      assert Enum.any?(buttons, fn b -> b.id == "edit_field_brand" end)
      assert Enum.any?(buttons, fn b -> b.id == "edit_field_model" end)
      assert Enum.any?(buttons, fn b -> b.id == "edit_field_delete" end)
    end

    test "returns :not_in_flow for non-owned gear" do
      {_owner, gear} = create_user_with_gear()
      other_user = Kite4rent.UsersFixtures.user_fixture(%{whatsapp: "other"})

      FlowManager.start_flow(other_user.id, :gear_edit, :selecting_item, initial_data: %{})

      message = %WhatsappMessage{
        type: "interactive",
        user: other_user,
        content: %{
          "type" => "list_reply",
          "list_reply" => %{"id" => "edit_gear_#{gear.id}"}
        }
      }

      assert :not_in_flow = GearEdit.handle_gear_edit_selection(message)
    end
  end

  describe "handle_gear_edit_field_selection/2 - delete" do
    test "deletes gear item and clears flow" do
      {user, gear} = create_user_with_gear()

      FlowManager.start_flow(user.id, :gear_edit, :selecting_field,
        initial_data: %{"gear_id" => gear.id}
      )

      collected_data = %{"gear_id" => gear.id}

      message = %WhatsappMessage{
        type: "interactive",
        user: user,
        content: %{
          "type" => "button_reply",
          "button_reply" => %{"id" => "edit_field_delete"}
        }
      }

      assert {:handled, {:ok, {:text, text}}} =
               GearEdit.handle_gear_edit_field_selection(message, collected_data)

      assert text =~ "✅"

      # Verify gear was deleted
      assert {:ok, []} = Rental.list_available_gear_for_user(user.id)
    end
  end

  describe "handle_gear_edit_value_input/2 - brand edit" do
    test "updates brand and clears flow" do
      {user, gear} = create_user_with_gear()

      FlowManager.start_flow(user.id, :gear_edit, :awaiting_value,
        initial_data: %{"gear_id" => gear.id, "edit_field" => "brand"}
      )

      collected_data = %{"gear_id" => gear.id, "edit_field" => "brand"}

      message = %WhatsappMessage{
        type: "text",
        user: user,
        content: %{"body" => "North"}
      }

      assert {:handled, {:ok, {:text, text}}} =
               GearEdit.handle_gear_edit_value_input(message, collected_data)

      assert text =~ "✅"

      # Verify brand was updated
      updated_gear = Rental.get_gear!(gear.id)
      assert updated_gear.brand == "North"
    end

    test "updates model and clears flow" do
      {user, gear} = create_user_with_gear()

      FlowManager.start_flow(user.id, :gear_edit, :awaiting_value,
        initial_data: %{"gear_id" => gear.id, "edit_field" => "model"}
      )

      collected_data = %{"gear_id" => gear.id, "edit_field" => "model"}

      message = %WhatsappMessage{
        type: "text",
        user: user,
        content: %{"body" => "Orbit"}
      }

      assert {:handled, {:ok, {:text, text}}} =
               GearEdit.handle_gear_edit_value_input(message, collected_data)

      assert text =~ "✅"

      # Verify model was updated
      updated_gear = Rental.get_gear!(gear.id)
      assert updated_gear.model == "Orbit"
    end

    test "rejects edit from non-owner" do
      {_owner, gear} = create_user_with_gear()
      other_user = Kite4rent.UsersFixtures.user_fixture(%{whatsapp: "other2"})

      FlowManager.start_flow(other_user.id, :gear_edit, :awaiting_value,
        initial_data: %{"gear_id" => gear.id, "edit_field" => "brand"}
      )

      collected_data = %{"gear_id" => gear.id, "edit_field" => "brand"}

      message = %WhatsappMessage{
        type: "text",
        user: other_user,
        content: %{"body" => "Hacked Brand"}
      }

      assert :not_in_flow = GearEdit.handle_gear_edit_value_input(message, collected_data)

      # Verify brand was NOT changed
      original_gear = Rental.get_gear!(gear.id)
      assert original_gear.brand == "Slingshot"
    end
  end
end
