defmodule Kite4rent.IntentionHandler.ListOwnInventory do
  @moduledoc """
  Handles the "list_own_inventory" intention by retrieving and displaying
  gear items owned by the user.
  """

  @behaviour Kite4rent.IntentionHandler

  require Logger
  alias Kite4rent.Intentions
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.Rental
  alias Kite4rent.Users.User

  @intention Intentions.list_own_inventory()

  @impl Kite4rent.IntentionHandler
  def handle_intention(%LLMResponse{intention: @intention}, %User{} = user) do
    {:ok, gear_list} = Rental.list_available_gear_for_user(user.id)
    Logger.info("Retrieved #{length(gear_list)} gear items for user #{user.id}")
    {:ok, {:list_own_inventory, gear_list, user}}
  end

  @impl Kite4rent.IntentionHandler
  def handle_intention(%LLMResponse{}, %User{}) do
    {:error, :invalid_intention_for_handler}
  end
end
