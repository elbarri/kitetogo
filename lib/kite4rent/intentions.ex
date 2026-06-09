defmodule Kite4rent.Intentions do
  @moduledoc """
  Defines all recognized LLM intention names as constants.

  Use these in consuming modules via compile-time module attributes so that
  typos are caught at compile time rather than silently failing at runtime:

      @intention Kite4rent.Intentions.offer_gear()
      def handle(%LLMResponse{intention: @intention}, user), do: ...
  """

  @offer_gear "offer_gear"
  @request_gear "request_gear"
  @check_availability "check_availability"
  @list_own_inventory "list_own_inventory"
  @request_security_deposit "request_security_deposit"
  @edit_gear "edit_gear"
  @feedback "feedback"
  @other "other"

  def offer_gear, do: @offer_gear
  def request_gear, do: @request_gear
  def check_availability, do: @check_availability
  def list_own_inventory, do: @list_own_inventory
  def request_security_deposit, do: @request_security_deposit
  def edit_gear, do: @edit_gear
  def feedback, do: @feedback
  def other, do: @other
end
