defmodule Kite4rent.MessageProcessor.Flows.GearCompletionTest do
  use Kite4rent.DataCase, async: false
  use Mimic

  alias Kite4rent.Conversation.Manager, as: FlowManager
  alias Kite4rent.Conversation.State, as: FlowState
  alias Kite4rent.MessageProcessor.Flows.GearCompletion
  alias Kite4rent.Messages.WhatsappMessage

  import Kite4rent.UsersFixtures

  setup do
    user = user_fixture(%{contact_sharing_consent: true, location_name: "Barcelona"})

    {:ok, user: user}
  end

  describe "handle_gear_completion_response/2" do
    test "returns :not_in_flow for empty text", %{user: user} do
      message = %WhatsappMessage{
        type: "text",
        content: %{"body" => ""},
        user: user
      }

      state = %FlowState{
        user_id: user.id,
        current_flow: :gear_completion,
        flow_step: {:awaiting, :gear_fields},
        collected_data: %{
          "gear_data" => %{"type" => "kite", "brand" => "Duotone", "model" => "Evo", "size" => "12m"},
          "stored_gear_ids" => [],
          "remaining_incomplete" => []
        },
        missing_fields: [:year]
      }

      assert :not_in_flow = GearCompletion.handle_gear_completion_response(message, state)
    end

    @tag :capture_log
    test "returns error message when LLM fails", %{user: user} do
      expect(Kite4rent.LLMProcessor, :generate_response, fn _text, _prompt ->
        {:error, :timeout, "Request timed out"}
      end)

      message = %WhatsappMessage{
        type: "text",
        content: %{"body" => "It's from 2022"},
        user: user
      }

      state = %FlowState{
        user_id: user.id,
        current_flow: :gear_completion,
        flow_step: {:awaiting, :gear_fields},
        collected_data: %{
          "gear_data" => %{"type" => "kite", "brand" => "Duotone", "model" => "Evo", "size" => "12m"},
          "stored_gear_ids" => [],
          "remaining_incomplete" => []
        },
        missing_fields: [:year]
      }

      assert {:handled, {:ok, {:text, error_msg}}} =
               GearCompletion.handle_gear_completion_response(message, state)

      assert is_binary(error_msg)
      assert String.length(error_msg) > 5
    end

    test "returns followup prompt when LLM extracts brand but year still missing", %{user: user} do
      # Start flow so FlowManager write ops work
      {:ok, _} =
        FlowManager.start_flow(
          user.id,
          :gear_completion,
          {:awaiting, :gear_fields},
          initial_data: %{
            "gear_data" => %{
              "type" => "kite",
              "brand" => nil,
              "model" => "Evo",
              "size" => "12m"
            },
            "stored_gear_ids" => [],
            "remaining_incomplete" => []
          },
          missing_fields: [:brand, :year]
        )

      # LLM extracts brand but not year
      expect(Kite4rent.LLMProcessor, :generate_response, fn _text, _prompt ->
        {:ok, ~s({"brand": "Duotone", "year": null})}
      end)

      message = %WhatsappMessage{
        type: "text",
        content: %{"body" => "It's a Duotone"},
        user: user
      }

      state = %FlowState{
        user_id: user.id,
        current_flow: :gear_completion,
        flow_step: {:awaiting, :gear_fields},
        collected_data: %{
          "gear_data" => %{
            "type" => "kite",
            "brand" => nil,
            "model" => "Evo",
            "size" => "12m"
          },
          "stored_gear_ids" => [],
          "remaining_incomplete" => []
        },
        missing_fields: [:brand, :year]
      }

      result = GearCompletion.handle_gear_completion_response(message, state)

      assert {:handled, {:ok, {:text, followup_prompt}}} = result
      assert is_binary(followup_prompt)
      # Should ask for year, which is still missing
      assert followup_prompt =~ ~r/year|año/i
    end

    test "creates gear in DB and returns reply when all fields extracted", %{user: user} do
      # Start flow so FlowManager.clear_flow works
      {:ok, _} =
        FlowManager.start_flow(
          user.id,
          :gear_completion,
          {:awaiting, :gear_fields},
          initial_data: %{
            "gear_data" => %{
              "type" => "kite",
              "brand" => "Duotone",
              "model" => "Evo",
              "size" => "12m"
            },
            "stored_gear_ids" => [],
            "remaining_incomplete" => []
          },
          missing_fields: [:year]
        )

      # LLM extracts year - all fields now complete
      expect(Kite4rent.LLMProcessor, :generate_response, fn _text, _prompt ->
        {:ok, ~s({"year": "2022"})}
      end)

      message = %WhatsappMessage{
        type: "text",
        content: %{"body" => "It's from 2022"},
        user: user
      }

      state = %FlowState{
        user_id: user.id,
        current_flow: :gear_completion,
        flow_step: {:awaiting, :gear_fields},
        collected_data: %{
          "gear_data" => %{
            "type" => "kite",
            "brand" => "Duotone",
            "model" => "Evo",
            "size" => "12m"
          },
          "stored_gear_ids" => [],
          "remaining_incomplete" => []
        },
        missing_fields: [:year]
      }

      assert {:handled, {:ok, _reply}} =
               GearCompletion.handle_gear_completion_response(message, state)

      # Flow should be cleared after completion
      {:ok, current_state} = FlowManager.get_state(user.id)
      assert current_state.current_flow == nil
    end
  end

  describe "get_still_missing_fields/2" do
    test "returns fields with nil values as still missing" do
      gear_data = %{"brand" => nil, "year" => "2022", "model" => ""}
      missing = [:brand, :year, :model]

      result = GearCompletion.get_still_missing_fields(gear_data, missing)

      assert :brand in result
      assert :model in result
      refute :year in result
    end

    test "returns empty list when all fields are present" do
      gear_data = %{"brand" => "Duotone", "model" => "Evo", "year" => "2022"}
      missing = [:brand, :model, :year]

      assert [] = GearCompletion.get_still_missing_fields(gear_data, missing)
    end

    test "treats null/None/none string values as missing" do
      gear_data = %{"brand" => "null", "model" => "None", "year" => "none"}
      missing = [:brand, :model, :year]

      result = GearCompletion.get_still_missing_fields(gear_data, missing)

      assert :brand in result
      assert :model in result
      assert :year in result
    end
  end
end
