defmodule Kite4rent.GearFormatterTest do
  use ExUnit.Case, async: true
  alias Kite4rent.GearFormatter

  describe "format_gear/2" do
    test "formats basic gear with default options" do
      gear = %{"type" => "kite", "brand" => "Duotone", "size" => "12m"}
      formatted = GearFormatter.format_gear(gear)
      assert formatted == "🪂 Duotone (12M)"
    end

    test "formats gear with model and year" do
      gear = %{
        "type" => "kite",
        "brand" => "Duotone",
        "model" => "Evo",
        "size" => "12m",
        "year" => "2023"
      }

      formatted = GearFormatter.format_gear(gear)
      assert formatted == "🪂 Duotone Evo (12M) - 2023"
    end

    test "formats gear with listing option" do
      gear = %{"type" => "board", "brand" => "North", "model" => "X-Ride"}
      formatted = GearFormatter.format_gear(gear, listing: true)
      assert formatted == "* 🏄 North X-Ride"
    end

    test "formats gear without emoticon" do
      gear = %{"type" => "kite", "brand" => "Duotone", "size" => "12m"}
      formatted = GearFormatter.format_gear(gear, include_emoticon: false)
      assert formatted == "Duotone (12M)"
    end
  end

  describe "format_gear_list/2" do
    test "formats list of gear without aggregation" do
      gear_list = [
        %{"type" => "kite", "brand" => "Duotone", "size" => "12m"},
        %{"type" => "board", "brand" => "North", "model" => "X-Ride"}
      ]

      formatted = GearFormatter.format_gear_list(gear_list)
      expected = "🪂 Duotone (12M)\n🏄 North X-Ride"
      assert formatted == expected
    end

    test "formats list of gear with aggregation enabled" do
      gear_list = [
        %{"type" => "kite", "brand" => "Slingshot", "model" => "RPM", "size" => "11 meters"},
        %{"type" => "kite", "brand" => "Slingshot", "model" => "RPM", "size" => "9 meters"},
        %{"type" => "kite", "brand" => "Slingshot", "model" => "SST", "size" => "6 meters"}
      ]

      formatted = GearFormatter.format_gear_list(gear_list, aggregate: true)
      expected = "🪂 Slingshot RPM (9M & 11M)\n🪂 Slingshot SST (6M)"
      assert formatted == expected
    end

    test "formats empty list" do
      formatted = GearFormatter.format_gear_list([])
      assert formatted == ""
    end
  end

  describe "aggregate_gear/1" do
    test "aggregates gear by type, brand, and model" do
      gear_list = [
        %{"type" => "kite", "brand" => "Slingshot", "model" => "RPM", "size" => "11 meters"},
        %{"type" => "kite", "brand" => "Slingshot", "model" => "RPM", "size" => "9 meters"},
        %{"type" => "kite", "brand" => "Slingshot", "model" => "SST", "size" => "6 meters"}
      ]

      aggregated = GearFormatter.aggregate_gear(gear_list)

      assert length(aggregated) == 2

      # Find the RPM kite
      rpm_kite = Enum.find(aggregated, fn gear -> gear["model"] == "RPM" end)
      assert rpm_kite["size"] == "9 meters & 11 meters"

      # Find the SST kite
      sst_kite = Enum.find(aggregated, fn gear -> gear["model"] == "SST" end)
      assert sst_kite["size"] == "6 meters"
    end

    test "sorts sizes numerically" do
      gear_list = [
        %{"type" => "kite", "brand" => "Duotone", "model" => "Evo", "size" => "14m"},
        %{"type" => "kite", "brand" => "Duotone", "model" => "Evo", "size" => "9m"},
        %{"type" => "kite", "brand" => "Duotone", "model" => "Evo", "size" => "12m"}
      ]

      aggregated = GearFormatter.aggregate_gear(gear_list)
      assert length(aggregated) == 1
      assert List.first(aggregated)["size"] == "9m, 12m & 14m"
    end

    test "handles gear with different years separately" do
      gear_list = [
        %{
          "type" => "kite",
          "brand" => "Duotone",
          "model" => "Evo",
          "size" => "12m",
          "year" => "2023"
        },
        %{
          "type" => "kite",
          "brand" => "Duotone",
          "model" => "Evo",
          "size" => "12m",
          "year" => "2024"
        }
      ]

      aggregated = GearFormatter.aggregate_gear(gear_list)
      assert length(aggregated) == 2
    end

    test "handles gear without model" do
      gear_list = [
        %{"type" => "kite", "brand" => "Duotone", "size" => "12m"},
        %{"type" => "kite", "brand" => "Duotone", "size" => "9m"}
      ]

      aggregated = GearFormatter.aggregate_gear(gear_list)
      assert length(aggregated) == 1
      assert List.first(aggregated)["size"] == "9m & 12m"
    end

    test "handles gear without sizes" do
      gear_list = [
        %{"type" => "harness", "brand" => "Mystic"},
        %{"type" => "harness", "brand" => "Mystic"}
      ]

      aggregated = GearFormatter.aggregate_gear(gear_list)
      assert length(aggregated) == 1
      assert List.first(aggregated)["size"] == nil
    end

    test "handles mixed key types (string and atom)" do
      gear_list = [
        %{type: "kite", brand: "Duotone", model: "Evo", size: "12m"},
        %{"type" => "kite", "brand" => "Duotone", "model" => "Evo", "size" => "9m"}
      ]

      aggregated = GearFormatter.aggregate_gear(gear_list)
      assert length(aggregated) == 1

      # Should have combined size regardless of key type
      gear = List.first(aggregated)
      combined_size = gear["size"] || gear[:size]
      assert combined_size == "9m & 12m"
    end

    test "removes duplicate sizes" do
      gear_list = [
        %{"type" => "kite", "brand" => "Duotone", "model" => "Evo", "size" => "12m"},
        %{"type" => "kite", "brand" => "Duotone", "model" => "Evo", "size" => "12m"},
        %{"type" => "kite", "brand" => "Duotone", "model" => "Evo", "size" => "9m"}
      ]

      aggregated = GearFormatter.aggregate_gear(gear_list)
      assert length(aggregated) == 1
      assert List.first(aggregated)["size"] == "9m & 12m"
    end

    test "handles empty list" do
      aggregated = GearFormatter.aggregate_gear([])
      assert aggregated == []
    end
  end

  describe "get_gear_emoticon/1" do
    test "returns correct emoticons for gear types" do
      assert GearFormatter.get_gear_emoticon("kite") == "🪂"
      assert GearFormatter.get_gear_emoticon("board") == "🏄"
      assert GearFormatter.get_gear_emoticon("twintip") == "🏄"
      assert GearFormatter.get_gear_emoticon("bar") == "🎮"
      assert GearFormatter.get_gear_emoticon("harness") == "💺"
      assert GearFormatter.get_gear_emoticon("leash") == "🔗"
    end

    test "returns default emoticon for unknown types" do
      assert GearFormatter.get_gear_emoticon("unknown") == "⚡"
      assert GearFormatter.get_gear_emoticon("") == "⚡"
    end

    test "handles case insensitive gear types" do
      assert GearFormatter.get_gear_emoticon("KITE") == "🪂"
      assert GearFormatter.get_gear_emoticon("Board") == "🏄"
    end
  end
end
