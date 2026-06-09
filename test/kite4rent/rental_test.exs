defmodule Kite4rent.RentalTest do
  use Kite4rent.DataCase

  alias Kite4rent.Rental
  alias Kite4rent.Users.User

  describe "kite_gear" do
    alias Kite4rent.Rental.Gear

    import Kite4rent.RentalFixtures

    @invalid_attrs %{
      size: nil,
      type: nil,
      year: nil,
      model: nil,
      brand: nil,
      condition: nil,
      additional_details: nil,
      user_id: nil
    }

    setup do
      # Create and insert a user
      user =
        %User{
          name: "Test User",
          email: "test@example.com",
          whatsapp: "1234567890"
        }
        |> Repo.insert!()

      {:ok, %{user: user}}
    end

    test "list_kite_gear/0 returns all kite_gear", %{user: user} do
      gear = gear_fixture(%{user_id: user.id})
      assert Rental.list_kite_gear() == [gear]
    end

    test "get_gear!/1 returns the gear with given id", %{user: user} do
      gear = gear_fixture(%{user_id: user.id})
      assert Rental.get_gear!(gear.id) == gear
    end

    test "create_gear/1 with valid data creates a gear", %{user: user} do
      valid_attrs = %{
        size: "some size",
        type: "some type",
        year: "42",
        model: "some model",
        brand: "some brand",
        condition: "some condition",
        additional_details: "some additional_details",
        user_id: user.id
      }

      assert {:ok, %Gear{} = gear} = Rental.create_gear(valid_attrs)
      assert gear.size == "some size"
      assert gear.type == "some type"
      assert gear.year == "42"
      assert gear.model == "Some Model"
      assert gear.brand == "Some Brand"
      assert gear.condition == "some condition"
      assert gear.additional_details == "some additional_details"
      assert gear.user_id == user.id
    end

    test "create_gear/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Rental.create_gear(@invalid_attrs)
    end

    test "update_gear/2 with valid data updates the gear", %{user: user} do
      gear = gear_fixture(%{user_id: user.id})

      update_attrs = %{
        size: "some updated size",
        type: "some updated type",
        year: "43",
        model: "some updated model",
        brand: "some updated brand",
        condition: "some updated condition",
        additional_details: "some updated additional_details"
      }

      assert {:ok, %Gear{} = gear} = Rental.update_gear(gear, update_attrs)
      assert gear.size == "some updated size"
      assert gear.type == "some updated type"
      assert gear.year == "43"
      assert gear.model == "Some Updated Model"
      assert gear.brand == "Some Updated Brand"
      assert gear.condition == "some updated condition"
      assert gear.additional_details == "some updated additional_details"
    end

    test "update_gear/2 with invalid data returns error changeset", %{user: user} do
      gear = gear_fixture(%{user_id: user.id})
      assert {:error, %Ecto.Changeset{}} = Rental.update_gear(gear, @invalid_attrs)
      assert gear == Rental.get_gear!(gear.id)
    end

    test "delete_gear/1 deletes the gear", %{user: user} do
      gear = gear_fixture(%{user_id: user.id})
      assert {:ok, %Gear{}} = Rental.delete_gear(gear)
      assert_raise Ecto.NoResultsError, fn -> Rental.get_gear!(gear.id) end
    end

    test "change_gear/1 returns a gear changeset", %{user: user} do
      gear = gear_fixture(%{user_id: user.id})
      assert %Ecto.Changeset{} = Rental.change_gear(gear)
    end

    test "list_available_gear_for_user/1 returns gear for specific user", %{user: user} do
      # Create another user
      other_user =
        %User{
          name: "Other User",
          email: "other@example.com",
          whatsapp: "9876543210"
        }
        |> Repo.insert!()

      # Create gear for the first user
      gear1 = gear_fixture(%{user_id: user.id, type: "kite", brand: "Duotone"})
      gear2 = gear_fixture(%{user_id: user.id, type: "board", brand: "North"})

      # Create gear for the other user
      _other_gear = gear_fixture(%{user_id: other_user.id, type: "kite", brand: "Cabrinha"})

      # Test that we get only the gear for the specific user
      {:ok, user_gear} = Rental.list_available_gear_for_user(user.id)
      assert length(user_gear) == 2
      assert Enum.all?(user_gear, fn gear -> gear.user_id == user.id end)
      assert gear1 in user_gear
      assert gear2 in user_gear

      # Test for other user
      {:ok, other_user_gear} = Rental.list_available_gear_for_user(other_user.id)
      assert length(other_user_gear) == 1
      assert hd(other_user_gear).user_id == other_user.id
    end

    test "list_available_gear_for_user/1 returns empty list for user with no gear", %{user: _user} do
      # Create another user with no gear
      no_gear_user =
        %User{
          name: "No Gear User",
          email: "nogear@example.com",
          whatsapp: "5555555555"
        }
        |> Repo.insert!()

      {:ok, gear_list} = Rental.list_available_gear_for_user(no_gear_user.id)
      assert gear_list == []
    end

    test "delete_all_gear_for_user/1 deletes all gear for a user", %{user: user} do
      # Create gear for the user
      gear1 = gear_fixture(%{user_id: user.id, type: "kite", brand: "Duotone"})
      gear2 = gear_fixture(%{user_id: user.id, type: "board", brand: "North"})

      # Create another user with gear
      other_user =
        %User{
          name: "Other User",
          email: "other@example.com",
          whatsapp: "9876543210"
        }
        |> Repo.insert!()

      other_gear = gear_fixture(%{user_id: other_user.id, type: "kite", brand: "Cabrinha"})

      # Delete all gear for the first user
      assert {:ok, 2} = Rental.delete_all_gear_for_user(user.id)

      # Verify gear was deleted
      assert_raise Ecto.NoResultsError, fn -> Rental.get_gear!(gear1.id) end
      assert_raise Ecto.NoResultsError, fn -> Rental.get_gear!(gear2.id) end

      # Verify other user's gear is still there
      assert other_gear == Rental.get_gear!(other_gear.id)
    end

    test "delete_all_gear_for_user/1 returns 0 for user with no gear", %{user: _user} do
      # Create a user with no gear
      no_gear_user =
        %User{
          name: "No Gear User",
          email: "nogear@example.com",
          whatsapp: "5555555555"
        }
        |> Repo.insert!()

      assert {:ok, 0} = Rental.delete_all_gear_for_user(no_gear_user.id)
    end
  end
end
