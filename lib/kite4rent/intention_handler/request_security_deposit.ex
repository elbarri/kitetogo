defmodule Kite4rent.IntentionHandler.RequestSecurityDeposit do
  @moduledoc """
  Handles the request_security_deposit intention.

  This handler processes requests from gear owners who want to request
  a security deposit from someone renting their equipment.

  The flow is:
  1. Owner says they want a deposit
  2. Bot shows list of owner's gear items
  3. Owner selects items and specifies replacement value for each
  4. Owner selects duration (1 or 2 days)
  5. Owner sends renter's contact
  6. Deposit is created and checkout link sent to renter
  """

  @behaviour Kite4rent.IntentionHandler

  require Logger
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.Users.User
  alias Kite4rent.Rental
  alias Kite4rent.Conversation.Manager, as: FlowManager

  @impl true
  def handle_intention(
        %LLMResponse{} = _llm_response,
        %User{} = user
      ) do
    # Verify user has gear to rent (is an owner)
    case Rental.list_available_gear_for_user(user.id) do
      {:ok, []} ->
        Logger.warning("User #{user.id} tried to request deposit but has no gear listed")
        {:ok, {:no_gear_to_rent, nil, user}}

      {:ok, gear_list} ->
        # Start the item selection flow
        start_item_selection_flow(user, gear_list)
    end
  end

  defp start_item_selection_flow(user, gear_list) do
    Logger.info("User #{user.id} starting deposit item selection flow with #{length(gear_list)} items")

    # Initialize the conversation flow for item selection
    FlowManager.start_flow(
      user.id,
      :deposit_item_selection,
      :selecting_item,
      initial_data: %{
        "selected_items" => [],
        "current_item" => nil,
        "total_value" => 0,
        "currency" => user.currency || "EUR",
        "available_gear_ids" => Enum.map(gear_list, & &1.id)
      }
    )

    # Return action to show the gear selection list
    total_count = length(gear_list)
    {:ok, {:deposit_select_gear, %{gear_list: gear_list, total_count: total_count}, user}}
  end
end
