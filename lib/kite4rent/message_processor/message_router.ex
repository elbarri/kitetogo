defmodule Kite4rent.MessageProcessor.MessageRouter do
  @moduledoc """
  Two-tier message routing:

    1. FlowRouter — if the user has an active multi-step flow (gear_offer,
       deposit_item_selection, etc.), delegate to that flow's handler.
    2. RulesEngine — assert facts from the message and dispatch the first
       matching action (classify intent, find gear, handle audio, etc.).

  Adding a new routing tier means adding a clause here, not touching
  MessageProcessor or either downstream system.
  """

  alias Kite4rent.MessageProcessor.ActionHandler
  alias Kite4rent.MessageProcessor.FactAssertion
  alias Kite4rent.MessageProcessor.FlowRouter
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.RulesEngine

  @doc """
  Routes an incoming message through the two-tier dispatch chain.
  Returns the same values as the individual handlers.
  """
  def route(%WhatsappMessage{user: user} = message) do
    case FlowRouter.maybe_handle(message, user) do
      {:handled, result} -> result
      :not_in_flow -> dispatch_via_rules_engine(message)
    end
  end

  defp dispatch_via_rules_engine(%WhatsappMessage{} = message) do
    engine =
      RulesEngine.get_engine()
      |> FactAssertion.assert_message_facts(message)
      |> FactAssertion.assert_user_facts(message.user)
      |> FactAssertion.assert_context_facts(message)

    ActionHandler.dispatch(engine, message)
  end
end
