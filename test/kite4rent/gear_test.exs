defmodule Kite4rent.GearTest do
  use Kite4rent.DataCase

  alias Kite4rent.Rental
  alias Kite4rent.Users.User
  alias Kite4rent.Rental.Gear

  describe "kite_gear" do
    @invalid_attrs %{type: nil, brand: nil, user_id: nil}

    setup do
      # Create and insert a user
      user =
        %User{
          name: "Facundo",
          email: "user@example.com",
          whatsapp: "34600000000"
        }
        |> Repo.insert!()

      # Create a gear item with the user association
      gear_attrs = %{
        type: "twintip",
        size: "139x42",
        year: "2021",
        model: "Master",
        brand: "Eleveight",
        condition: "Good",
        additional_details: "Used for 2 seasons",
        user_id: user.id
      }

      gear = %Gear{} |> Gear.changeset(gear_attrs) |> Repo.insert!()

      # Return the created data for use in tests
      {:ok, %{user: user, gear: gear}}
    end

    test "list_kite_gear/0 returns all kite_gear", %{gear: gear} do
      assert Rental.list_kite_gear() == [gear]
    end

    test "get_gear!/1 returns the gear with given id", %{gear: gear} do
      assert Rental.get_gear!(gear.id) == gear
    end

    test "create_gear/1 with valid data creates a gear", %{user: user} do
      valid_attrs = %{
        type: "twintip",
        size: "135x41",
        year: "2023",
        model: "Spectrum",
        brand: "Cabrinha",
        condition: "Excellent",
        additional_details: "New",
        user_id: user.id
      }

      assert {:ok, %Gear{} = gear} = Rental.create_gear(valid_attrs)
      assert gear.type == "twintip"
      assert gear.size == "135x41"
      assert gear.year == "2023"
      assert gear.model == "Spectrum"
      assert gear.brand == "Cabrinha"
      assert gear.condition == "Excellent"
      assert gear.additional_details == "New"
      assert gear.user_id == user.id
    end

    test "create_gear/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Rental.create_gear(@invalid_attrs)
    end

    test "update_gear/2 with valid data updates the gear", %{gear: gear} do
      update_attrs = %{
        size: "140x43",
        year: "2024",
        model: "Pro",
        condition: "Like new"
      }

      assert {:ok, %Gear{} = gear} = Rental.update_gear(gear, update_attrs)
      assert gear.size == "140x43"
      assert gear.year == "2024"
      assert gear.model == "Pro"
      assert gear.condition == "Like new"
    end

    test "update_gear/2 with invalid data returns error changeset", %{gear: gear} do
      assert {:error, %Ecto.Changeset{}} = Rental.update_gear(gear, @invalid_attrs)
      assert gear == Rental.get_gear!(gear.id)
    end

    test "delete_gear/1 deletes the gear", %{gear: gear} do
      assert {:ok, %Gear{}} = Rental.delete_gear(gear)
      assert_raise Ecto.NoResultsError, fn -> Rental.get_gear!(gear.id) end
    end

    test "change_gear/1 returns a gear changeset", %{gear: gear} do
      assert %Ecto.Changeset{} = Rental.change_gear(gear)
    end

    test "create_gear/1 with kite type and valid numeric size succeeds", %{user: user} do
      # Test integer size
      attrs_integer = %{
        type: "kite",
        size: "12",
        brand: "Duotone",
        model: "Evo",
        year: "2022",
        user_id: user.id
      }

      assert {:ok, %Gear{} = gear} = Rental.create_gear(attrs_integer)
      assert gear.type == "kite"
      assert gear.size == "12"

      # Test decimal size
      attrs_decimal = %{
        type: "kite",
        size: "12.5",
        brand: "Cabrinha",
        model: "Switchblade",
        year: "2023",
        user_id: user.id
      }

      assert {:ok, %Gear{} = gear} = Rental.create_gear(attrs_decimal)
      assert gear.type == "kite"
      assert gear.size == "12.5"

      # Test size with units (m) - should extract the number
      attrs_with_m = %{
        type: "kite",
        size: "12m",
        brand: "North",
        model: "Rebel",
        year: "2021",
        user_id: user.id
      }

      assert {:ok, %Gear{} = gear} = Rental.create_gear(attrs_with_m)
      assert gear.type == "kite"
      assert gear.size == "12m"

      # Test size with "M" - should extract the number
      attrs_with_M = %{
        type: "kite",
        size: "12M",
        brand: "Slingshot",
        model: "RPM",
        year: "2024",
        user_id: user.id
      }

      assert {:ok, %Gear{} = gear} = Rental.create_gear(attrs_with_M)
      assert gear.type == "kite"
      assert gear.size == "12M"

      # Test size with "meters" - should extract the number
      attrs_with_meters = %{
        type: "kite",
        size: "12 meters",
        brand: "Duotone",
        model: "Dice",
        year: "2020",
        user_id: user.id
      }

      assert {:ok, %Gear{} = gear} = Rental.create_gear(attrs_with_meters)
      assert gear.type == "kite"
      assert gear.size == "12 meters"

      # Test decimal size with units - should extract the number
      attrs_decimal_with_m = %{
        type: "kite",
        size: "12.5m",
        brand: "Cabrinha",
        model: "FX",
        year: "2019",
        user_id: user.id
      }

      assert {:ok, %Gear{} = gear} = Rental.create_gear(attrs_decimal_with_m)
      assert gear.type == "kite"
      assert gear.size == "12.5m"
    end

    test "create_gear/1 with kite type and invalid size fails", %{user: user} do
      # Test size with multiple decimals - should be invalid
      attrs_multiple_decimals = %{
        type: "kite",
        size: "12.25",
        brand: "Cabrinha",
        user_id: user.id
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Rental.create_gear(attrs_multiple_decimals)

      assert "must contain a valid number (integer or with one decimal) when type is kite" in errors_on(
               changeset
             ).size

      # Test size with multiple decimals and units - should be invalid
      attrs_multiple_decimals_with_units = %{
        type: "kite",
        size: "12.25m",
        brand: "North",
        user_id: user.id
      }

      assert {:error, %Ecto.Changeset{} = changeset} =
               Rental.create_gear(attrs_multiple_decimals_with_units)

      assert "must contain a valid number (integer or with one decimal) when type is kite" in errors_on(
               changeset
             ).size

      # Test board-style size - should be invalid (no extractable number in correct format)
      attrs_board_style = %{
        type: "kite",
        size: "139x42",
        brand: "North",
        user_id: user.id
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Rental.create_gear(attrs_board_style)

      assert "must contain a valid number (integer or with one decimal) when type is kite" in errors_on(
               changeset
             ).size

      # Test non-numeric size - should be invalid
      attrs_letters = %{
        type: "kite",
        size: "large",
        brand: "Slingshot",
        user_id: user.id
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Rental.create_gear(attrs_letters)

      assert "must contain a valid number (integer or with one decimal) when type is kite" in errors_on(
               changeset
             ).size
    end

    test "create_gear/1 with non-kite type allows any size format", %{user: user} do
      # Test board with board-style size
      attrs_board = %{
        type: "board",
        size: "139x42",
        brand: "North",
        model: "Atmos",
        year: "2022",
        user_id: user.id
      }

      assert {:ok, %Gear{} = gear} = Rental.create_gear(attrs_board)
      assert gear.type == "board"
      assert gear.size == "139x42"

      # Test harness with size containing letters
      attrs_harness = %{
        type: "harness",
        size: "M",
        brand: "Mystic",
        model: "Stealth",
        gender: "M",
        user_id: user.id
      }

      assert {:ok, %Gear{} = gear} = Rental.create_gear(attrs_harness)
      assert gear.type == "harness"
      assert gear.size == "M"
    end

    test "create_gear/1 with kite type and empty size is rejected", %{user: user} do
      attrs_empty_size = %{
        type: "kite",
        size: "",
        brand: "Duotone",
        user_id: user.id
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Rental.create_gear(attrs_empty_size)
      assert "is required for kites" in errors_on(changeset).size
    end

    test "create_gear/1 with kite type and nil size is rejected", %{user: user} do
      attrs_nil_size = %{
        type: "kite",
        size: nil,
        brand: "Duotone",
        user_id: user.id
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Rental.create_gear(attrs_nil_size)
      assert "is required for kites" in errors_on(changeset).size
    end

    test "create_gear/1 with kite missing required fields is rejected", %{user: user} do
      attrs_missing_model_year = %{
        type: "kite",
        size: "12m",
        brand: "Duotone",
        user_id: user.id
        # Missing model and year
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Rental.create_gear(attrs_missing_model_year)
      errors = errors_on(changeset)
      assert "is required for kites" in errors.model
      assert "is required for kites" in errors.year
    end

    test "create_gear/1 with board missing required fields is rejected", %{user: user} do
      attrs_missing_model_year = %{
        type: "board",
        size: "139x42",
        brand: "North",
        user_id: user.id
        # Missing model and year
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Rental.create_gear(attrs_missing_model_year)
      errors = errors_on(changeset)
      assert "is required for boards" in errors.model
      assert "is required for boards" in errors.year
    end

    test "create_gear/1 with harness missing optional fields is allowed", %{user: user} do
      attrs_minimal_harness = %{
        type: "harness",
        brand: "Mystic",
        size: "M",
        gender: "F",
        user_id: user.id
        # Missing model, year - but should be valid for harness
      }

      assert {:ok, %Gear{} = gear} = Rental.create_gear(attrs_minimal_harness)
      assert gear.type == "harness"
      assert gear.brand == "Mystic"
      assert gear.model == nil
      assert gear.year == nil
      assert gear.size == "M"
      assert gear.gender == "F"
    end
  end
end
