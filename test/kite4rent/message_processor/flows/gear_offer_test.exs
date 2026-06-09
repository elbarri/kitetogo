defmodule Kite4rent.MessageProcessor.Flows.GearOfferTest do
  use Kite4rent.DataCase, async: false
  use Mimic

  alias Kite4rent.Conversation.Manager, as: FlowManager
  alias Kite4rent.Conversation.State, as: FlowState
  alias Kite4rent.Geocoding
  alias Kite4rent.MessageProcessor.Flows.GearOffer
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.NominatimRateLimiter

  import Kite4rent.UsersFixtures

  @saved_response %{
    "intention" => "offer_gear",
    "language" => "en",
    "gear" => [
      %{
        "type" => "kite",
        "brand" => "Duotone",
        "model" => "Evo",
        "size" => "12m",
        "year" => "2022"
      }
    ],
    "location" => nil,
    "location_radius_km" => nil,
    "security_deposit" => nil
  }

  setup do
    user = user_fixture()
    Geocoding.clear_cache()
    Mimic.stub(NominatimRateLimiter, :throttle, fn fun -> fun.() end)
    {:ok, user: user}
  end

  describe "handle_gear_offer_text_as_location/2" do
    test "returns :not_in_flow for text shorter than 2 chars", %{user: user} do
      message = %WhatsappMessage{
        type: "text",
        content: %{"body" => "A"},
        user: user
      }

      state = %FlowState{
        user_id: user.id,
        current_flow: :gear_offer,
        flow_step: {:awaiting, :location},
        llm_response: @saved_response
      }

      assert :not_in_flow = GearOffer.handle_gear_offer_text_as_location(message, state)
    end

    test "returns interactive list and keeps flow active when geocoding is ambiguous",
         %{user: user} do
      # Start a flow in the DB so FlowManager state is consistent
      {:ok, _state} =
        FlowManager.start_flow(
          user.id,
          :gear_offer,
          {:awaiting, :location},
          llm_response: @saved_response
        )

      # Mock HTTPClient to return 2 results with different country codes
      expect(Kite4rent.Utils.HTTPClient, :request, fn :get, _url, _headers ->
        response_body =
          Jason.encode!([
            %{
              "lat" => "41.3825802",
              "lon" => "2.177073",
              "display_name" => "Barcelona, Catalonia, Spain",
              "address" => %{
                "city" => "Barcelona",
                "state" => "Catalonia",
                "country" => "Spain",
                "country_code" => "es"
              }
            },
            %{
              "lat" => "10.4634975",
              "lon" => "-66.8016918",
              "display_name" => "Barcelona, Anzoátegui, Venezuela",
              "address" => %{
                "city" => "Barcelona",
                "state" => "Anzoátegui",
                "country" => "Venezuela",
                "country_code" => "ve"
              }
            }
          ])

        {:ok, response_body}
      end)

      message = %WhatsappMessage{
        type: "text",
        content: %{"body" => "Barcelona"},
        user: user
      }

      state = %FlowState{
        user_id: user.id,
        current_flow: :gear_offer,
        flow_step: {:awaiting, :location},
        llm_response: @saved_response
      }

      result = GearOffer.handle_gear_offer_text_as_location(message, state)

      assert {:handled, {:ok, {:interactive_list, body_text, _button_text, sections}, extra}} = result
      assert body_text =~ "Barcelona"
      assert extra.action == "disambiguate_location"
      assert extra.original_location_name == "Barcelona"
      assert length(extra.countries) == 2

      [%{rows: rows}] = sections
      assert length(rows) == 2
      assert Enum.any?(rows, fn row -> row.title == "Spain" end)
      assert Enum.any?(rows, fn row -> row.title == "Venezuela" end)

      # Flow should still be active
      {:ok, current_state} = FlowManager.get_state(user.id)
      assert current_state.current_flow == :gear_offer
    end

    @tag :capture_log
    test "returns :not_in_flow and clears flow when geocoding fails", %{user: user} do
      # Start a flow in the DB first
      {:ok, _state} =
        FlowManager.start_flow(
          user.id,
          :gear_offer,
          {:awaiting, :location},
          llm_response: @saved_response
        )

      # Mock HTTPClient to return empty list (no results found)
      expect(Kite4rent.Utils.HTTPClient, :request, fn :get, _url, _headers ->
        response_body = Jason.encode!([])
        {:ok, response_body}
      end)

      message = %WhatsappMessage{
        type: "text",
        content: %{"body" => "Nonexistent Place XYZ"},
        user: user
      }

      state = %FlowState{
        user_id: user.id,
        current_flow: :gear_offer,
        flow_step: {:awaiting, :location},
        llm_response: @saved_response
      }

      result = GearOffer.handle_gear_offer_text_as_location(message, state)

      assert :not_in_flow = result

      # Flow should be cleared
      {:ok, current_state} = FlowManager.get_state(user.id)
      assert current_state.current_flow == nil
    end
  end
end
