defmodule Kite4rent.ReplyComposerTest do
  use Kite4rent.DataCase, async: false
  alias Kite4rent.ReplyComposer
  alias Kite4rent.Users.User
  alias Kite4rent.ResponseTemplates

  import Kite4rent.UsersFixtures

  describe "compose_reply/2" do
    test "handles successful gear offering" do
      gear = [
        %{"type" => "kite", "brand" => "Duotone", "size" => "12m"}
      ]

      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:offer_gear, gear}, %User{language: "en"})

      assert is_binary(reply)
      assert String.length(reply) > 10
      assert reply =~ ~r/gear|listing|thanks/i
    end

    test "handles successful gear offering with multiple gear items" do
      gear = [
        %{"type" => "kite", "brand" => "Duotone", "size" => "12m"},
        %{"type" => "board", "brand" => "North", "size" => "138cm"}
      ]

      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:offer_gear, gear}, %User{language: "en"})

      # Since LLM generates dynamic responses, just check it's a non-empty string
      assert is_binary(reply)
      assert String.length(reply) > 10
      assert reply =~ ~r/gear|listing|thanks/i
    end

    test "handles successful gear offering in Spanish" do
      gear = [%{"type" => "kite", "brand" => "Duotone", "size" => "12m"}]

      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:offer_gear, gear}, %User{language: "es"})

      # Check it's a reasonable Spanish response
      assert is_binary(reply)
      assert String.length(reply) > 10
      assert reply =~ ~r/gracias|equipo|gear/i
    end

    test "handles unsupported intention" do
      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply(
          {:error, {:intention_not_yet_supported, "unknown_intention"}},
          %User{language: "en"}
        )

      assert is_binary(reply)
      assert String.length(reply) > 5
    end

    test "handles gear offering with no language specified (defaults to English)" do
      gear = [%{"type" => "kite", "brand" => "Duotone", "size" => "12m"}]

      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:offer_gear, gear}, %User{language: "en"})

      assert is_binary(reply)
      assert String.length(reply) > 10
      assert reply =~ ~r/gear|listing|thanks/i
    end

    test "handles users_with_gear with multiple users and gear" do
      users_with_gear = [
        %{
          user: %{id: 1, name: "Facundo", location_name: nil},
          gear: [
            %{type: "board", brand: "Eleveight", size: "139x42"}
          ]
        },
        %{
          user: %{id: 2, name: "Andre", location_name: nil},
          gear: [
            %{type: "kite", brand: "Slingshot", model: "RPM", size: "11 meters"},
            %{type: "kite", brand: "Slingshot", model: "RPM", size: "9 meters"},
            %{type: "kite", brand: "Slingshot", model: "SST", size: "6 meters"}
          ]
        },
        %{
          user: %{id: 3, name: "Tim", location_name: nil},
          gear: [
            %{type: "kite", brand: "Duotone", model: "Rebel", year: "2021", size: "10 meters"}
          ]
        },
        %{
          user: %{id: 4, name: "Fourth Owner", location_name: nil},
          gear: [
            %{type: "harness", brand: "Mystic"}
          ]
        }
      ]

      {:ok, {:text, reply}, metadata} =
        ReplyComposer.compose_reply(
          %Kite4rent.IntentionHandler.RequestGear{users_with_gear: users_with_gear},
          %User{language: "en"}
        )

      # Check that it includes owner information
      assert String.contains?(reply, "1 - Facundo")
      assert String.contains?(reply, "2 - Andre")
      assert String.contains?(reply, "3 - Tim")
      # 4th owner is not displayed due to users_with_gear_limit: 3 in test config
      refute String.contains?(reply, "4 - Fourth Owner")

      # Check that it includes gear information
      assert String.contains?(reply, "Eleveight")
      assert String.contains?(reply, "Slingshot RPM")
      assert String.contains?(reply, "Duotone Rebel")

      # Check that it includes contact selection instruction
      assert String.contains?(reply, "Reply with the number")

      # Check metadata - should only include the first 3 owners
      assert metadata == %{listed_users_with_gear: %{1 => 1, 2 => 2, 3 => 3}}
    end

    test "handles RequestGear struct with no gear found" do
      request_gear = %Kite4rent.IntentionHandler.RequestGear{
        location_name: "Barcelona",
        latitude: 41.3851,
        longitude: 2.1734,
        radius_km: Application.get_env(:kite4rent, :geocoding, [])[:default_radius_km] || 25,
        users_with_gear: []
      }

      user = %User{language: "en"}

      {:ok, {:text, reply}} = ReplyComposer.compose_reply(request_gear, user)

      assert reply =~ "Barcelona"
      assert reply =~ ~r/couldn't find|no results|not found/i
    end

    test "handles RequestGear struct with gear found" do
      user1 = %User{id: 1, name: "Owner 1"}
      user2 = %User{id: 2, name: "Owner 2"}

      users_with_gear = [
        %{user: user1, gear: [%{type: "kite", brand: "Duotone"}]},
        %{user: user2, gear: [%{type: "board", brand: "North"}]}
      ]

      request_gear = %Kite4rent.IntentionHandler.RequestGear{
        location_name: "Miami",
        radius_km: 15,
        users_with_gear: users_with_gear
      }

      user = %User{language: "en"}

      {:ok, {:text, reply}, metadata} = ReplyComposer.compose_reply(request_gear, user)

      assert reply =~ "Owner 1"
      assert reply =~ "Owner 2"
      assert Map.has_key?(metadata, :listed_users_with_gear)
    end

    test "RequestGear struct properly replaces location placeholder when no gear found" do
      # This test simulates the exact scenario from the logs where "quilmes" was requested
      request_gear = %Kite4rent.IntentionHandler.RequestGear{
        location_name: "quilmes",
        radius_km: Application.get_env(:kite4rent, :geocoding, [])[:default_radius_km] || 25,
        users_with_gear: []
      }

      user = %User{language: "es"}

      {:ok, {:text, reply}} = ReplyComposer.compose_reply(request_gear, user)

      # Should contain the location name instead of placeholder
      assert reply =~ "quilmes"
      refute reply =~ "__LOCATION_NAME__"
      assert reply =~ ~r/no pude encontrar|couldn't find/i
    end

    test "uses user location_name in gear_offer_success template" do
      user = %User{location_name: "Barcelona", language: "en"}
      gear = [%{"type" => "kite", "brand" => "Duotone", "size" => "12m"}]

      {:ok, {:text, reply}} = ReplyComposer.compose_reply({:offer_gear, gear}, user)

      assert reply =~ "Barcelona"
    end

    test "missing_location template for request_gear doesn't substitute location (by design)" do
      user = %User{location_name: "Amsterdam", language: "nl"}
      llm_response = %Kite4rent.Messages.LLMResponse{intention: "request_gear"}

      {:ok, {:location_request, reply, extra_content}} =
        ReplyComposer.compose_reply({:error, :missing_location, llm_response}, user)

      # Location template shouldn't substitute location name (by design)
      assert is_binary(reply)
      assert String.length(reply) > 10
      # Verify extra_content includes llm_response
      assert extra_content == %{"llm_response" => llm_response}
    end

    test "missing_location template for offer_gear provides appropriate message" do
      user = %User{location_name: "Amsterdam", language: "nl"}
      llm_response = %Kite4rent.Messages.LLMResponse{intention: "offer_gear"}

      {:ok, {:location_request, reply, extra_content}} =
        ReplyComposer.compose_reply({:error, :missing_location, llm_response}, user)

      # Should provide appropriate message for gear offering
      assert is_binary(reply)
      assert String.length(reply) > 10
      # Verify extra_content includes llm_response
      assert extra_content == %{"llm_response" => llm_response}
    end

    test "location_not_found error provides helpful message" do
      user = %User{language: "en"}

      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:error, {:location_not_found, "NonExistentPlace"}}, user)

      assert is_binary(reply)
      assert String.length(reply) > 10
      assert reply =~ "NonExistentPlace"

      assert String.contains?(String.downcase(reply), "couldn't find") or
               String.contains?(String.downcase(reply), "not found")
    end

    test "location_not_found error in Spanish" do
      user = %User{language: "es"}

      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:error, {:location_not_found, "LugarInexistente"}}, user)

      assert is_binary(reply)
      assert reply =~ "LugarInexistente"

      assert String.contains?(String.downcase(reply), "no pude encontrar") or
               String.contains?(String.downcase(reply), "ubicación")
    end

    test "location_updated with user location_name and coordinates" do
      user = %User{location_name: "Test Location", language: "en"}

      location = %Kite4rent.Location{
        latitude: 41.3825802,
        longitude: 2.177073,
        name: "Test Location"
      }

      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:location_updated, location}, user)

      assert reply =~ String.replace(to_string(location.latitude), "\.", "\.")
      assert reply =~ String.replace(to_string(location.longitude), "\.", "\.")
      assert reply =~ location.name
    end

    test "handles list_own_inventory with gear" do
      user = %User{location_name: "Barcelona", language: "en"}

      gear = [
        %{type: "kite", brand: "Duotone", size: "12m", model: "Evo", year: "2023"},
        %{type: "board", brand: "North", model: "X-Ride"}
      ]

      {:ok, {:text, reply}} = ReplyComposer.compose_reply({:list_own_inventory, gear}, user)

      assert reply =~ "your gear inventory"

      # Should contain gear information (formatted by GearFormatter)
      assert reply =~ "Duotone" or reply =~ "North"
    end

    test "handles list_own_inventory with empty gear list" do
      user = %User{location_name: "Madrid", language: "en"}

      {:ok, {:text, reply}} = ReplyComposer.compose_reply({:list_own_inventory, []}, user)

      # Should indicate no gear is listed (matches the actual template)
      assert reply =~ "You don't have any gear listed"
      assert reply =~ "Use 'offer gear' to add"
    end

    test "handles list_own_inventory in Spanish" do
      user = %User{location_name: "Tarifa", language: "es"}

      gear = [
        %{type: "kite", brand: "Duotone", size: "12m"}
      ]

      {:ok, {:text, reply}} = ReplyComposer.compose_reply({:list_own_inventory, gear}, user)

      assert reply =~ "inventario de equipo"
    end

    test "handles unsupported message type" do
      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:error, :unsupported_message_type}, %User{language: "en"})

      assert reply == ResponseTemplates.get_template(:unsupported_message_type, "en")

      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:error, :unsupported_message_type}, %User{language: "de"})

      assert reply == ResponseTemplates.get_template(:unsupported_message_type, "de")
    end

    test "handles contact selection invalid" do
      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:contact_selection_invalid}, %User{language: "en"})

      assert reply =~ "Please reply with a valid number"
      assert reply =~ "from the list"
    end

    test "handles contact selection invalid in Spanish" do
      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:contact_selection_invalid}, %User{language: "es"})

      assert reply =~ "Por favor, responde con un número válido"
      assert reply =~ "de la lista"
    end

    test "handles contact payment CTA" do
      {:ok, replies} =
        ReplyComposer.compose_reply(
          {:contact_payment_cta, "+1234567890", "user123"},
          %User{language: "en"}
        )

      # Returns a list with CTA and test mode notice
      assert is_list(replies)
      assert {:cta_url, cta_data} = Enum.find(replies, fn {type, _} -> type == :cta_url end)
      assert {:text, test_notice} = Enum.find(replies, fn {type, _} -> type == :text end)

      assert is_binary(cta_data.body_text)
      assert is_binary(cta_data.button_text)
      assert is_binary(cta_data.button_url)
      assert is_binary(cta_data.header_text)
      assert is_binary(cta_data.footer_text)
      assert is_binary(test_notice)

      assert cta_data.button_url =~ "contact_id=user123"
      assert cta_data.button_url =~ "phone=1234567890"
    end

    test "handles contact payment CTA without contact ID" do
      {:ok, replies} =
        ReplyComposer.compose_reply(
          {:contact_payment_cta, "+1234567890", nil},
          %User{language: "en"}
        )

      assert is_list(replies)
      assert {:cta_url, cta_data} = Enum.find(replies, fn {type, _} -> type == :cta_url end)

      assert is_binary(cta_data.body_text)
      assert is_binary(cta_data.button_text)
      assert is_binary(cta_data.button_url)
      assert is_binary(cta_data.header_text)
      assert is_binary(cta_data.footer_text)

      refute cta_data.button_url =~ "contact_id="
      assert cta_data.button_url =~ "phone=1234567890"
    end

    test "uses configured base URL for payment CTA" do
      # Test that the base URL from config is used
      base_url = Application.get_env(:kite4rent, :base_url)
      assert is_binary(base_url)

      {:ok, replies} =
        ReplyComposer.compose_reply(
          {:contact_payment_cta, "+1234567890", "user123"},
          %User{language: "en"}
        )

      assert is_list(replies)
      assert {:cta_url, cta_data} = Enum.find(replies, fn {type, _} -> type == :cta_url end)

      assert String.starts_with?(cta_data.button_url, base_url)
      assert cta_data.button_url =~ "/checkout-session/new"
      assert cta_data.button_url =~ "phone=1234567890"
      assert cta_data.button_url =~ "contact_id=user123"
    end

    test "handles first time user welcome message" do
      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:first_time_user_welcome}, %User{language: "en"})

      assert reply == ResponseTemplates.get_template(:welcome_message, "en")

      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:first_time_user_welcome}, %User{language: "es"})

      assert reply == ResponseTemplates.get_template(:welcome_message, "es")
    end

    test "handles contact_sharing_consent request in English" do
      user = %User{id: 1, language: "en"}

      {:ok, {:text, reply}, extra_content} =
        ReplyComposer.compose_reply({:contact_sharing_consent, []}, user)

      assert is_binary(reply)
      assert String.contains?(reply, "Your gear has been saved!")
      assert String.contains?(reply, "WhatsApp contact")
      assert String.contains?(reply, "👍")
      # Verify intent is included
      assert extra_content == %{intent: "contact_sharing_consent_request"}
    end

    test "handles conversational_response with text" do
      user = %User{id: 1, language: "en"}

      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:conversational_response, "Hello! How can I help you today?"}, user)

      assert reply == "Hello! How can I help you today?"
    end

    test "handles conversational_response in Spanish" do
      user = %User{id: 1, language: "es"}

      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:conversational_response, "¡Hola! ¿En qué puedo ayudarte?"}, user)

      assert reply == "¡Hola! ¿En qué puedo ayudarte?"
    end

    test "handles conversational_response passes through LLM response unchanged" do
      user = %User{id: 1, language: "en"}
      llm_response = "I don't have information about that specific topic, but I'm here to help with kitesurf gear rentals!"

      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:conversational_response, llm_response}, user)

      assert reply == llm_response
    end

    test "handles gear_offer_completed when user has given consent" do
      user = %User{
        id: 1,
        language: "en",
        contact_sharing_consent: true,
        location_name: "Barcelona"
      }

      gear = [%{"type" => "kite", "brand" => "Duotone", "size" => "12m"}]

      {:ok, {:text, reply}} = ReplyComposer.compose_reply({:gear_offer_completed, gear}, user)

      assert is_binary(reply)
      assert String.length(reply) > 5
    end

    test "handles gear_offer_completed when user has not given consent" do
      user = %User{id: 1, language: "en", contact_sharing_consent: false}
      gear = [%{"type" => "kite", "brand" => "Duotone", "size" => "12m"}]

      {:ok, {:text, reply}, extra} =
        ReplyComposer.compose_reply({:gear_offer_completed, gear}, user)

      assert is_binary(reply)
      assert extra == %{intent: "contact_sharing_consent_request"}
    end

    test "handles availability_countries with list of countries" do
      user = %User{language: "en"}

      countries = [
        %{country_code: "ES", location_count: 3},
        %{country_code: "PT", location_count: 1}
      ]

      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:availability_countries, countries}, user)

      assert reply =~ "Spain"
      assert reply =~ "Portugal"
    end

    test "handles availability_locations with country and locations list" do
      user = %User{language: "en"}

      data = %{country_name: "Spain", locations: ["Tarifa", "Barcelona"]}

      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply({:availability_locations, data}, user)

      assert reply =~ "Spain"
      assert reply =~ "Tarifa"
      assert reply =~ "Barcelona"
    end

    test "handles availability_no_gear" do
      user = %User{language: "en"}

      {:ok, {:text, reply}} = ReplyComposer.compose_reply({:availability_no_gear, nil}, user)

      assert is_binary(reply)
      assert String.length(reply) > 5
    end

    test "handles availability_no_gear_in_country" do
      user = %User{language: "en"}

      {:ok, {:text, reply}} =
        ReplyComposer.compose_reply(
          {:availability_no_gear_in_country, %{country_name: "Spain"}},
          user
        )

      assert reply =~ "Spain"
    end

    test "handles offer_gear_incomplete and starts gear completion flow" do
      # Requires real DB user because FlowManager.start_flow is called
      user = user_fixture(%{location_name: "Barcelona", language: "en"})

      incomplete = [
        %{
          type: "kite",
          data: %{"type" => "kite", "brand" => "Duotone"},
          missing_fields: [:model, :size, :year]
        }
      ]

      {:ok, {:text, prompt}} =
        ReplyComposer.compose_reply(
          {:offer_gear_incomplete, %{stored: [], incomplete: incomplete}},
          user
        )

      assert prompt =~ ~r/kite/i
    end
  end

  describe "compose_reply/3" do
    test "handles ambiguous_location_in_offer with location name and countries" do
      user = %User{language: "en"}

      llm_response = %Kite4rent.Messages.LLMResponse{
        intention: "offer_gear",
        language: "en"
      }

      countries_data = [
        %{
          country_code: "ES",
          country_name: "Spain",
          lat: 41.3825802,
          lng: 2.177073,
          display_name: "Barcelona, Spain"
        },
        %{
          country_code: "VE",
          country_name: "Venezuela",
          lat: 10.4634975,
          lng: -66.8016918,
          display_name: "Barcelona, Venezuela"
        }
      ]

      result =
        ReplyComposer.compose_reply(
          {:error, {:ambiguous_location_in_offer, "Barcelona", countries_data}},
          user,
          llm_response
        )

      assert {:ok, [{:text, ambiguity_msg}, {:location_request, _, extra}]} = result
      assert ambiguity_msg =~ "Barcelona"
      assert extra["llm_response"] == llm_response
    end
  end
end
