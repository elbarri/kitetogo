defmodule Kite4rent.IntentionHandler.EditGear do
  @moduledoc """
  Handles the "edit_gear" intention by letting users correct or delete
  specific gear items they already listed.
  """

  @behaviour Kite4rent.IntentionHandler

  require Logger
  alias Kite4rent.Conversation.Manager, as: FlowManager
  alias Kite4rent.Deposits
  alias Kite4rent.Intentions
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.Rental
  alias Kite4rent.Users.User

  @intention Intentions.edit_gear()

  @impl true
  def handle_intention(%LLMResponse{intention: @intention}, %User{} = user) do
    case Rental.list_available_gear_for_user(user.id) do
      {:ok, []} ->
        {:ok, {:edit_gear_no_items, nil, user}}

      {:ok, [single_gear]} ->
        if Deposits.has_active_deposit_for_gear?(single_gear.id) do
          {:ok, {:edit_gear_active_deposit, single_gear, user}}
        else
          # Skip item selection, go directly to field selection
          FlowManager.start_flow(
            user.id,
            :gear_edit,
            :selecting_field,
            initial_data: %{"gear_id" => single_gear.id}
          )

          {:ok, {:edit_gear_select_field, single_gear, user}}
        end

      {:ok, gear_list} ->
        FlowManager.start_flow(
          user.id,
          :gear_edit,
          :selecting_item,
          initial_data: %{}
        )

        {:ok, {:edit_gear_select_item, gear_list, user}}
    end
  end

  @impl true
  def handle_intention(%LLMResponse{}, %User{}) do
    {:error, :invalid_intention_for_handler}
  end
end
