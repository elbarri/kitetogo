defmodule Kite4rent.Rental.GearModelTest do
  use Kite4rent.DataCase

  alias Kite4rent.Rental

  describe "lookup_brand_for_model/1" do
    test "returns {:ok, brand} when single brand matches" do
      Rental.create_gear_model(%{model_name: "RPM", brand: "Slingshot", gear_type: "kite"})

      assert {:ok, "Slingshot"} = Rental.lookup_brand_for_model("RPM")
    end

    test "is case-insensitive" do
      Rental.create_gear_model(%{model_name: "RPM", brand: "Slingshot", gear_type: "kite"})

      assert {:ok, "Slingshot"} = Rental.lookup_brand_for_model("rpm")
      assert {:ok, "Slingshot"} = Rental.lookup_brand_for_model("Rpm")
      assert {:ok, "Slingshot"} = Rental.lookup_brand_for_model("RPM")
    end

    test "returns {:ok, brand} when same brand across multiple gear types" do
      Rental.create_gear_model(%{model_name: "Select", brand: "Duotone", gear_type: "kite"})
      Rental.create_gear_model(%{model_name: "Select", brand: "Duotone", gear_type: "board"})

      assert {:ok, "Duotone"} = Rental.lookup_brand_for_model("Select")
    end

    test "returns {:ambiguous, brands} when multiple brands match" do
      Rental.create_gear_model(%{model_name: "Edge", brand: "Ozone", gear_type: "kite"})
      Rental.create_gear_model(%{model_name: "Edge", brand: "Slingshot", gear_type: "board"})

      assert {:ambiguous, brands} = Rental.lookup_brand_for_model("Edge")
      assert length(brands) == 2
      assert "Ozone" in brands
      assert "Slingshot" in brands
    end

    test "returns :not_found when no match" do
      assert :not_found = Rental.lookup_brand_for_model("NonExistentModel")
    end

    test "returns :not_found for nil" do
      assert :not_found = Rental.lookup_brand_for_model(nil)
    end
  end

  describe "create_gear_model/1" do
    test "creates a gear model with valid attrs" do
      assert {:ok, gear_model} =
               Rental.create_gear_model(%{
                 model_name: "Orbit",
                 brand: "North",
                 gear_type: "kite"
               })

      assert gear_model.model_name == "Orbit"
      assert gear_model.brand == "North"
      assert gear_model.gear_type == "kite"
    end

    test "rejects invalid gear_type" do
      assert {:error, changeset} =
               Rental.create_gear_model(%{
                 model_name: "Orbit",
                 brand: "North",
                 gear_type: "surfboard"
               })

      assert errors_on(changeset)[:gear_type]
    end

    test "rejects duplicate entries (case-insensitive)" do
      Rental.create_gear_model(%{model_name: "RPM", brand: "Slingshot", gear_type: "kite"})

      assert {:error, changeset} =
               Rental.create_gear_model(%{model_name: "rpm", brand: "slingshot", gear_type: "kite"})

      assert errors_on(changeset)[:model_name]
    end
  end
end
