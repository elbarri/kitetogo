defmodule Kite4rent.IntentionHandler.DefaultHandler do
  @moduledoc """
  Default handler for unsupported or unrecognized intentions.
  This handler is used as a fallback when no specific handler is found
  for an intention.
  """

  @behaviour Kite4rent.IntentionHandler

  require Logger
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.Users.User

  @impl Kite4rent.IntentionHandler
  def handle_intention(%LLMResponse{intention: intention}, %User{}) do
    Logger.info("No specific handler found for intention: #{intention}")
    {:error, :intention_not_yet_supported}
  end
end
