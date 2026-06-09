defmodule Kite4rent.IntentionHandler.ChatHandlerTest do
  use Kite4rent.DataCase, async: true
  alias Kite4rent.IntentionHandler.ChatHandler

  describe "handle_get_feature_guide/1" do
    test "returns offer_gear feature info with format and description" do
      args = %{"feature" => "offer_gear"}
      {:ok, json} = ChatHandler.handle_get_feature_guide(args)
      data = Jason.decode!(json)

      assert data["feature"] == "offer_gear"
      assert data["description"] == "Publish your kitesurfing gear for rent"
      assert data["message_format"] == "[gear_type] [brand] [model] [size] in [location]"
      assert data["example_format"] == "kite North Reach 12m in Tarifa"
    end

    test "returns request_gear feature info with format and description" do
      args = %{"feature" => "request_gear"}
      {:ok, json} = ChatHandler.handle_get_feature_guide(args)
      data = Jason.decode!(json)

      assert data["feature"] == "request_gear"
      assert data["description"] == "Find gear to rent from other users"
      assert data["message_format"] == "[gear_type] in [location]"
      assert data["example_format"] == "kite in Tarifa"
    end

    test "returns kite required fields when gear_type is specified" do
      args = %{"feature" => "offer_gear", "gear_type" => "kite"}
      {:ok, json} = ChatHandler.handle_get_feature_guide(args)
      data = Jason.decode!(json)

      required = data["required_fields"]["required"]
      assert Enum.member?(required, "brand")
      assert Enum.member?(required, "model")
      assert Enum.member?(required, "size (meters, e.g. 12)")
      assert Enum.member?(required, "year")
      assert data["required_fields"]["optional"] == ["condition"]
    end

    test "returns board required fields when gear_type is board" do
      args = %{"feature" => "offer_gear", "gear_type" => "board"}
      {:ok, json} = ChatHandler.handle_get_feature_guide(args)
      data = Jason.decode!(json)

      required = data["required_fields"]["required"]
      assert Enum.member?(required, "brand")
      assert Enum.member?(required, "model")
      assert Enum.member?(required, "size (e.g. 139x42)")
      assert Enum.member?(required, "year")
    end

    test "returns harness required fields when gear_type is harness" do
      args = %{"feature" => "offer_gear", "gear_type" => "harness"}
      {:ok, json} = ChatHandler.handle_get_feature_guide(args)
      data = Jason.decode!(json)

      required = data["required_fields"]["required"]
      assert Enum.member?(required, "brand")
      assert Enum.member?(required, "size (S/M/L/XL)")
      assert Enum.member?(required, "gender (M/F)")
      assert data["required_fields"]["optional"] == ["model"]
    end

    test "returns wetsuit required fields when gear_type is wetsuit" do
      args = %{"feature" => "offer_gear", "gear_type" => "wetsuit"}
      {:ok, json} = ChatHandler.handle_get_feature_guide(args)
      data = Jason.decode!(json)

      required = data["required_fields"]["required"]
      assert Enum.member?(required, "brand")
      assert Enum.member?(required, "size (S/M/L/XL)")
      assert Enum.member?(required, "gender (M/F)")
    end

    test "returns bar (boom) required fields" do
      args = %{"feature" => "offer_gear", "gear_type" => "bar"}
      {:ok, json} = ChatHandler.handle_get_feature_guide(args)
      data = Jason.decode!(json)

      required = data["required_fields"]["required"]
      assert required == ["brand"]
      assert data["required_fields"]["optional"] == ["model", "size"]
    end

    test "returns all gear types when gear_type is nil" do
      args = %{"feature" => "offer_gear", "gear_type" => nil}
      {:ok, json} = ChatHandler.handle_get_feature_guide(args)
      data = Jason.decode!(json)

      types = data["required_fields"]["types"]
      assert Map.has_key?(types, "kite")
      assert Map.has_key?(types, "board")
      assert Map.has_key?(types, "harness")
      assert Map.has_key?(types, "wetsuit")
      assert Map.has_key?(types, "bar")
    end

    test "returns all gear types when gear_type is not provided" do
      args = %{"feature" => "offer_gear"}
      {:ok, json} = ChatHandler.handle_get_feature_guide(args)
      data = Jason.decode!(json)

      types = data["required_fields"]["types"]
      assert Map.has_key?(types, "kite")
      assert Map.has_key?(types, "board")
      assert Map.has_key?(types, "harness")
      assert Map.has_key?(types, "wetsuit")
      assert Map.has_key?(types, "bar")
    end

    test "handles unknown feature gracefully" do
      args = %{"feature" => "unknown_feature"}
      {:ok, json} = ChatHandler.handle_get_feature_guide(args)
      data = Jason.decode!(json)

      assert data["feature"] == "unknown_feature"
      assert data["description"] == "Unknown feature"
    end

    test "handles unknown gear_type gracefully" do
      args = %{"feature" => "offer_gear", "gear_type" => "unknown"}
      {:ok, json} = ChatHandler.handle_get_feature_guide(args)
      data = Jason.decode!(json)

      required = data["required_fields"]["required"]
      assert Enum.member?(required, "brand")
    end
  end
end
