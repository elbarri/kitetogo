defmodule Kite4rent.ResponseTemplatesTest do
  use ExUnit.Case
  doctest Kite4rent.ResponseTemplates

  alias Kite4rent.ResponseTemplates

  describe "get_template/2" do
    setup do
      default_radius = Application.get_env(:kite4rent, :geocoding, [])[:default_radius_km] || 25
      %{default_radius: default_radius}
    end

    test "returns English template by default" do
      refute is_nil(ResponseTemplates.get_template(:gear_offer_success))
    end

    test "returns Spanish template when requested" do
      refute is_nil(ResponseTemplates.get_template(:gear_offer_success, "es"))
    end

    test "falls back to default message for unknown template key" do
      result = ResponseTemplates.get_template(:unknown_key, "en")
      assert result =~ "Sorry, there was an issue processing your message"
    end

    test "contains closest location info placeholder" do
      result = ResponseTemplates.get_template(:gear_request_no_results, "en")
      assert result =~ "__CLOSEST_LOCATION_INFO__"
    end
  end

  describe "get_template/3 with substitutions" do
    test "substitutes location name in gear_offer_success template" do
      result =
        ResponseTemplates.get_template(:gear_offer_success, "en", %{location_name: "Barcelona"})

      assert result =~ "Barcelona"
      refute result =~ "__LOCATION_NAME__"
    end

    test "substitutes location name in Spanish template" do
      result =
        ResponseTemplates.get_template(:gear_offer_success, "es", %{location_name: "Madrid"})

      assert result =~ "Madrid"
      assert result =~ "¡Genial!"
      refute result =~ "__LOCATION_NAME__"
    end

    test "substitutes location name in Dutch template" do
      result =
        ResponseTemplates.get_template(:gear_offer_success, "nl", %{location_name: "Amsterdam"})

      assert result =~ "Amsterdam"
      assert result =~ "Geweldig!"
      refute result =~ "__LOCATION_NAME__"
    end

    test "substitutes location name in Italian template" do
      result = ResponseTemplates.get_template(:gear_offer_success, "it", %{location_name: "Roma"})
      assert result =~ "Roma"
      refute result =~ "__LOCATION_NAME__"
    end

    test "substitutes location name in location_updated template" do
      result =
        ResponseTemplates.get_template(:location_updated, "en", %{
          location_name: "Barcelona",
          lat: "41.3851",
          lng: "2.1734"
        })

      assert result =~ "Barcelona"
      assert result =~ "41.3851"
      assert result =~ "2.1734"
      refute result =~ "__LOCATION_NAME__"
      refute result =~ "__LAT__"
      refute result =~ "__LNG__"
    end

    test "handles empty substitutions map" do
      result = ResponseTemplates.get_template(:gear_offer_success, "en", %{})
      # should remain as placeholder
      assert result =~ "__LOCATION_NAME__"
    end

    test "handles nil substitution values" do
      result = ResponseTemplates.get_template(:gear_offer_success, "en", %{location_name: nil})
      # nil becomes empty string
      assert result =~ ""
      refute result =~ "__LOCATION_NAME__"
    end

    test "handles atom keys in substitutions" do
      result =
        ResponseTemplates.get_template(:gear_offer_success, "en", %{location_name: "Barcelona"})

      assert result =~ "Barcelona"
      refute result =~ "__LOCATION_NAME__"
    end

    test "handles string keys in substitutions" do
      result =
        ResponseTemplates.get_template(:gear_offer_success, "en", %{
          "location_name" => "Barcelona"
        })

      assert result =~ "Barcelona"
      refute result =~ "__LOCATION_NAME__"
    end
  end

  describe "available_languages/1" do
    test "returns all available languages for a template" do
      languages = ResponseTemplates.available_languages(:gear_offer_success)
      assert Enum.sort(languages) == ["de", "en", "es", "fr", "it", "nl"]
    end

    test "returns empty list for unknown template" do
      languages = ResponseTemplates.available_languages(:unknown_template)
      assert languages == []
    end
  end

  describe "available_templates/0" do
    test "returns all available template keys" do
      templates = ResponseTemplates.available_templates()

      # Check that key templates are present
      assert :gear_offer_success in templates
      assert :gear_request_no_results in templates
      assert :location_updated in templates
      assert :gear_request_missing_location in templates
      assert :gear_offer_missing_location in templates

      # Should have all the templates we defined
      assert length(templates) >= 15
    end
  end

  describe "all language support" do
    @complete_template_keys [
      :gear_offer_success,
      :gear_request_no_results,
      :gear_request_missing_location,
      :gear_offer_missing_location,
      :location_updated,
      :intention_not_supported,
      :unsupported_message_type,
      :generic_error
    ]

    test "major templates support all 6 languages" do
      languages = ["en", "es", "fr", "de", "nl", "it"]

      for template_key <- @complete_template_keys,
          language <- languages do
        result = ResponseTemplates.get_template(template_key, language)

        # Should not fall back to default error message
        refute result =~ "Sorry, there was an issue processing your message"
        # Should have meaningful content
        assert String.length(result) > 10
      end
    end

    test "all templates support at least English" do
      templates = ResponseTemplates.available_templates()

      for template_key <- templates do
        result = ResponseTemplates.get_template(template_key, "en")
        # Should have meaningful content (allow short field labels like "Size", "Year", "gear")
        assert String.length(result) > 2
      end
    end
  end
end
