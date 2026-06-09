defmodule Kite4rent.IntentionHandler do
  @moduledoc """
  Defines the behaviour for handling different LLM intentions and provides
  a dispatch mechanism to route intentions to their appropriate handlers.

  This module implements the strategy pattern to decouple intention handling
  from the MessageProcessor, making it easier to add new intentions without
  modifying the core processing logic.
  """

  require Logger
  alias Kite4rent.Intentions
  alias Kite4rent.Messages.LLMResponse
  alias Kite4rent.Users.User

  @offer_gear Intentions.offer_gear()
  @request_gear Intentions.request_gear()
  @check_availability Intentions.check_availability()
  @list_own_inventory Intentions.list_own_inventory()
  @request_security_deposit Intentions.request_security_deposit()
  @edit_gear Intentions.edit_gear()
  @feedback Intentions.feedback()
  @other Intentions.other()

  @intent_ambiguity_threshold Application.compile_env(:kite4rent, :intent_ambiguity_threshold, 0.75)

  @callback handle_intention(LLMResponse.t(), User.t()) ::
              {:ok, {atom(), term(), User.t()}} | {:ok, {struct(), User.t()}} | {:error, term()}

  @doc """
  Dispatches an intention to its appropriate handler.

  ## Parameters
    - llm_response: The complete LLM response struct containing the intention
    - user: The User struct of the user making the request

  ## Returns
    - {:ok, result} on successful handling
    - {:error, reason} on failure or unsupported intention
  """
  def handle(llm_response, user, opts \\ [])

  def handle(%LLMResponse{intention: @feedback} = _llm_response, user, _opts) do
    {:ok, {:feedback_thanks, nil, user}}
  end

  def handle(%LLMResponse{} = llm_response, user, opts) do
    if doubt_redirect?(llm_response) or incomplete_read?(llm_response) or
         ambiguous_offer_request?(llm_response) do
      Kite4rent.IntentionHandler.ChatHandler.handle_intention(llm_response, user, opts)
    else
      handler = Map.get(handlers(), llm_response.intention, Kite4rent.IntentionHandler.DefaultHandler)

      if handler == Kite4rent.IntentionHandler.ChatHandler do
        handler.handle_intention(llm_response, user, opts)
      else
        handler.handle_intention(llm_response, user)
      end
    end
  end

  # Redirect to ChatHandler when the user is asking a doubt/question
  # about an actionable intent rather than making a direct request
  defp doubt_redirect?(%LLMResponse{doubt_asked_likelihood: doubt, intention: intention})
       when is_float(doubt) and doubt >= 0.6 and intention not in [@other, @feedback] do
    true
  end

  defp doubt_redirect?(_), do: false

  defp incomplete_read?(%LLMResponse{intention: intention, location: loc})
       when intention in [@check_availability, @request_gear] and (is_nil(loc) or loc == "") do
    true
  end

  defp incomplete_read?(_), do: false

  # "alquilar" and similar verbs are ambiguous — the user might want to
  # publish their gear OR find gear to rent. When the classifier isn't
  # confident, let ChatHandler ask a clarifying question.
  defp ambiguous_offer_request?(%LLMResponse{
         intention: intention,
         intent_confidence: confidence
       })
       when intention in [@offer_gear, @request_gear] and is_float(confidence) and
              confidence < @intent_ambiguity_threshold do
    true
  end

  defp ambiguous_offer_request?(_), do: false

  defp handlers do
    %{
      @offer_gear => Kite4rent.IntentionHandler.OfferGear,
      @request_gear => Kite4rent.IntentionHandler.RequestGear,
      @list_own_inventory => Kite4rent.IntentionHandler.ListOwnInventory,
      @edit_gear => Kite4rent.IntentionHandler.EditGear,
      @request_security_deposit => Kite4rent.IntentionHandler.RequestSecurityDeposit,
      @check_availability => Kite4rent.IntentionHandler.CheckAvailability,
      # Conversational fallback for greetings, questions, and anything that doesn't match core intents
      @other => Kite4rent.IntentionHandler.ChatHandler
    }
  end

  @doc """
  Returns a list of all supported intentions.
  """
  def supported_intentions do
    Map.keys(handlers())
  end
end
