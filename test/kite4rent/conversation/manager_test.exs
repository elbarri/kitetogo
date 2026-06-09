defmodule Kite4rent.Conversation.ManagerTest do
  use Kite4rent.DataCase, async: true

  alias Kite4rent.Conversation.Manager
  alias Kite4rent.Conversation.State
  alias Kite4rent.Users

  describe "start_flow/4" do
    test "creates a new flow in the database" do
      {:ok, user} = create_user()

      {:ok, state} =
        Manager.start_flow(user.id, :gear_offer, {:awaiting, :location},
          llm_response: %{"intention" => "offer_gear", "gear" => []},
          missing_fields: [:location]
        )

      assert %State{} = state
      assert state.user_id == user.id
      assert state.current_flow == :gear_offer
      assert state.flow_step == {:awaiting, :location}
      assert state.llm_response == %{"intention" => "offer_gear", "gear" => []}
      assert state.missing_fields == [:location]
    end

    test "replaces existing flow when starting a new one" do
      {:ok, user} = create_user()

      {:ok, _} = Manager.start_flow(user.id, :gear_offer, {:awaiting, :location})
      {:ok, state} = Manager.start_flow(user.id, :gear_request, {:awaiting, :details})

      assert state.current_flow == :gear_request
      assert state.flow_step == {:awaiting, :details}
    end
  end

  describe "get_state/1" do
    test "returns empty state when no active flow" do
      {:ok, user} = create_user()

      {:ok, state} = Manager.get_state(user.id)

      assert %State{} = state
      assert state.current_flow == nil
      assert state.flow_step == nil
    end

    test "returns flow state when active flow exists" do
      {:ok, user} = create_user()
      {:ok, _} = Manager.start_flow(user.id, :gear_offer, {:awaiting, :location})

      {:ok, state} = Manager.get_state(user.id)

      assert state.current_flow == :gear_offer
      assert state.flow_step == {:awaiting, :location}
    end

    test "flow survives simulated app restart (database persistence)" do
      {:ok, user} = create_user()

      # Start a flow
      {:ok, _} =
        Manager.start_flow(user.id, :gear_offer, {:awaiting, :location},
          llm_response: %{"intention" => "offer_gear", "gear" => [%{"type" => "kite"}]}
        )

      # Simulate app restart by directly querying the database
      # (in the old GenServer implementation, this would have been lost)
      {:ok, state} = Manager.get_state(user.id)

      assert state.current_flow == :gear_offer
      assert state.flow_step == {:awaiting, :location}
      assert state.llm_response == %{"intention" => "offer_gear", "gear" => [%{"type" => "kite"}]}
    end
  end

  describe "add_data/2" do
    test "adds data to existing flow" do
      {:ok, user} = create_user()
      {:ok, _} = Manager.start_flow(user.id, :gear_offer, {:awaiting, :location})

      {:ok, state} = Manager.add_data(user.id, %{"location" => "Barcelona"})

      assert state.collected_data == %{"location" => "Barcelona"}
    end

    test "merges new data with existing data" do
      {:ok, user} = create_user()

      {:ok, _} =
        Manager.start_flow(user.id, :gear_offer, {:awaiting, :location},
          initial_data: %{"gear_type" => "kite"}
        )

      {:ok, state} = Manager.add_data(user.id, %{"location" => "Barcelona"})

      assert state.collected_data == %{"gear_type" => "kite", "location" => "Barcelona"}
    end

    test "returns error when no active flow" do
      {:ok, user} = create_user()

      result = Manager.add_data(user.id, %{"location" => "Barcelona"})

      assert result == {:error, :no_active_flow}
    end
  end

  describe "update_step/2" do
    test "updates flow step" do
      {:ok, user} = create_user()
      {:ok, _} = Manager.start_flow(user.id, :gear_offer, {:awaiting, :location})

      {:ok, state} = Manager.update_step(user.id, {:awaiting, :details})

      assert state.flow_step == {:awaiting, :details}
    end
  end

  describe "clear_flow/1" do
    test "removes the flow from database" do
      {:ok, user} = create_user()
      {:ok, _} = Manager.start_flow(user.id, :gear_offer, {:awaiting, :location})

      {:ok, state} = Manager.clear_flow(user.id)

      assert state.current_flow == nil

      # Verify it's gone from database too
      {:ok, fresh_state} = Manager.get_state(user.id)
      assert fresh_state.current_flow == nil
    end
  end

  describe "has_active_flow?/1" do
    test "returns true when flow exists" do
      {:ok, user} = create_user()
      {:ok, _} = Manager.start_flow(user.id, :gear_offer, {:awaiting, :location})

      assert {:ok, true} = Manager.has_active_flow?(user.id)
    end

    test "returns false when no flow exists" do
      {:ok, user} = create_user()

      assert {:ok, false} = Manager.has_active_flow?(user.id)
    end
  end

  describe "cleanup_expired_flows/0" do
    test "removes expired flows" do
      {:ok, user} = create_user()
      {:ok, _} = Manager.start_flow(user.id, :gear_offer, {:awaiting, :location})

      # Manually expire the flow by updating expires_at in the database
      alias Kite4rent.Conversation.Flow
      alias Kite4rent.Repo
      import Ecto.Query

      past_time = DateTime.utc_now() |> DateTime.add(-2, :hour)

      from(f in Flow, where: f.user_id == ^user.id)
      |> Repo.update_all(set: [expires_at: past_time])

      # Verify flow is now expired
      {:ok, count} = Manager.cleanup_expired_flows()
      assert count == 1

      # Verify flow is gone
      {:ok, state} = Manager.get_state(user.id)
      assert state.current_flow == nil
    end
  end

  # Helper functions

  defp create_user do
    unique_id = System.unique_integer([:positive])

    Users.create_user(%{
      whatsapp: "346446#{unique_id}",
      name: "Test User #{unique_id}"
    })
  end
end
