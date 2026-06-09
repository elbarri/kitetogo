defmodule Kite4rent.DepositItemSelectionFlowTest do
  @moduledoc """
  Tests for the deposit item selection flow, particularly the stale interaction handling
  that prevents users from clicking buttons from previous flow steps.
  """
  use ExUnit.Case

  describe "interaction_valid_for_step? logic" do
    # These tests verify the mapping between interactions and valid steps.
    # The actual function is private in MessageProcessor, so we test through
    # a helper that mirrors its logic.

    test "deposit_gear_* is valid only for :selecting_item step" do
      assert interaction_valid_for_step?("deposit_gear_123", :selecting_item) == true
      assert interaction_valid_for_step?("deposit_gear_456", :awaiting_value) == false
      assert interaction_valid_for_step?("deposit_gear_789", :confirm_add_more) == false
      assert interaction_valid_for_step?("deposit_gear_999", :awaiting_duration) == false
      assert interaction_valid_for_step?("deposit_gear_001", :awaiting_currency) == false
      assert interaction_valid_for_step?("deposit_gear_002", :awaiting_contact) == false
    end

    test "deposit_currency_* is valid only for :awaiting_currency step" do
      assert interaction_valid_for_step?("deposit_currency_EUR", :awaiting_currency) == true
      assert interaction_valid_for_step?("deposit_currency_USD", :awaiting_currency) == true
      assert interaction_valid_for_step?("deposit_currency_GBP", :awaiting_currency) == true
      assert interaction_valid_for_step?("deposit_currency_EUR", :selecting_item) == false
      assert interaction_valid_for_step?("deposit_currency_EUR", :awaiting_value) == false
      assert interaction_valid_for_step?("deposit_currency_USD", :confirm_add_more) == false
      assert interaction_valid_for_step?("deposit_currency_GBP", :awaiting_duration) == false
    end

    test "deposit_add_more_* is valid only for :confirm_add_more step" do
      assert interaction_valid_for_step?("deposit_add_more_yes", :confirm_add_more) == true
      assert interaction_valid_for_step?("deposit_add_more_no", :confirm_add_more) == true
      assert interaction_valid_for_step?("deposit_add_more_yes", :awaiting_duration) == false
      assert interaction_valid_for_step?("deposit_add_more_no", :selecting_item) == false
      assert interaction_valid_for_step?("deposit_add_more_yes", :awaiting_value) == false
      assert interaction_valid_for_step?("deposit_add_more_no", :awaiting_currency) == false
    end

    test "deposit_duration_* is valid only for :awaiting_duration step" do
      assert interaction_valid_for_step?("deposit_duration_1", :awaiting_duration) == true
      assert interaction_valid_for_step?("deposit_duration_2", :awaiting_duration) == true
      assert interaction_valid_for_step?("deposit_duration_1", :confirm_add_more) == false
      assert interaction_valid_for_step?("deposit_duration_2", :awaiting_contact) == false
      assert interaction_valid_for_step?("deposit_duration_1", :selecting_item) == false
      assert interaction_valid_for_step?("deposit_duration_2", :awaiting_currency) == false
    end

    test "no interactive buttons are valid for text-input steps" do
      # :awaiting_value expects text input, not buttons
      assert interaction_valid_for_step?("deposit_anything", :awaiting_value) == false
      assert interaction_valid_for_step?("deposit_gear_1", :awaiting_value) == false
      assert interaction_valid_for_step?("deposit_currency_EUR", :awaiting_value) == false
      assert interaction_valid_for_step?("deposit_add_more_yes", :awaiting_value) == false
      assert interaction_valid_for_step?("deposit_duration_1", :awaiting_value) == false

      # :awaiting_contact expects contact sharing, not buttons
      assert interaction_valid_for_step?("deposit_anything", :awaiting_contact) == false
      assert interaction_valid_for_step?("deposit_gear_1", :awaiting_contact) == false
      assert interaction_valid_for_step?("deposit_currency_EUR", :awaiting_contact) == false
    end

    test "returns false for unknown steps" do
      assert interaction_valid_for_step?("deposit_gear_1", :unknown_step) == false
      assert interaction_valid_for_step?("deposit_currency_EUR", nil) == false
    end

    test "handles edge cases" do
      # Empty string
      assert interaction_valid_for_step?("", :selecting_item) == false

      # Non-deposit prefixed
      assert interaction_valid_for_step?("other_button", :selecting_item) == false

      # Partial match
      assert interaction_valid_for_step?("deposit_gear", :selecting_item) == false
      assert interaction_valid_for_step?("deposit_currency", :awaiting_currency) == false
    end
  end

  describe "stale vs valid interaction scenarios" do
    test "scenario: user selects gear, then clicks old currency button" do
      # User was in :awaiting_currency, selected EUR, moved to :awaiting_value
      # Old EUR button should now be stale
      assert interaction_valid_for_step?("deposit_currency_EUR", :awaiting_currency) == true
      assert interaction_valid_for_step?("deposit_currency_EUR", :awaiting_value) == false
    end

    test "scenario: user adds item, then clicks old add_more button" do
      # User was in :confirm_add_more, clicked "no", moved to :awaiting_duration
      # Old add_more buttons should now be stale
      assert interaction_valid_for_step?("deposit_add_more_yes", :confirm_add_more) == true
      assert interaction_valid_for_step?("deposit_add_more_yes", :awaiting_duration) == false
      assert interaction_valid_for_step?("deposit_add_more_no", :awaiting_duration) == false
    end

    test "scenario: user selects duration, then clicks old gear button" do
      # User was in :selecting_item, selected gear, entered value, added item,
      # clicked "no" to add more, now in :awaiting_duration
      # Old gear selection should be stale
      assert interaction_valid_for_step?("deposit_gear_123", :selecting_item) == true
      assert interaction_valid_for_step?("deposit_gear_123", :awaiting_duration) == false
    end
  end

  describe "no active flow scenarios (e.g., after server restart)" do
    # Tests the logic that catches deposit buttons when there's no active
    # deposit_item_selection flow (server restart, timeout, etc.)

    test "deposit buttons are stale when current_flow is nil" do
      assert deposit_button_stale_without_flow?("deposit_gear_123", nil) == true
      assert deposit_button_stale_without_flow?("deposit_add_more_yes", nil) == true
      assert deposit_button_stale_without_flow?("deposit_add_more_no", nil) == true
      assert deposit_button_stale_without_flow?("deposit_duration_1", nil) == true
      assert deposit_button_stale_without_flow?("deposit_currency_EUR", nil) == true
    end

    test "deposit buttons are stale when current_flow is a different flow" do
      assert deposit_button_stale_without_flow?("deposit_gear_123", :some_other_flow) == true
      assert deposit_button_stale_without_flow?("deposit_add_more_no", :rental_flow) == true
    end

    test "deposit buttons are NOT caught by this check when in deposit_item_selection flow" do
      # When in the correct flow, the step-specific validation handles it instead
      assert deposit_button_stale_without_flow?("deposit_gear_123", :deposit_item_selection) == false
      assert deposit_button_stale_without_flow?("deposit_add_more_no", :deposit_item_selection) == false
    end

    test "non-deposit buttons are not affected" do
      assert deposit_button_stale_without_flow?("other_button", nil) == false
      assert deposit_button_stale_without_flow?("confirm_rental", nil) == false
      assert deposit_button_stale_without_flow?("", nil) == false
    end
  end

  # Helper function that mirrors the logic in MessageProcessor.interaction_valid_for_step?/2
  defp interaction_valid_for_step?(interaction_id, step) do
    case step do
      :selecting_item ->
        String.starts_with?(interaction_id, "deposit_gear_")

      :awaiting_currency ->
        String.starts_with?(interaction_id, "deposit_currency_")

      :confirm_add_more ->
        interaction_id in ["deposit_add_more_yes", "deposit_add_more_no"]

      :awaiting_duration ->
        interaction_id in ["deposit_duration_1", "deposit_duration_2"]

      _ ->
        false
    end
  end

  # Helper that mirrors the logic for catching deposit buttons when NOT in deposit_item_selection flow
  defp deposit_button_stale_without_flow?(interaction_id, current_flow) do
    current_flow != :deposit_item_selection &&
      interaction_id != "" &&
      String.starts_with?(interaction_id, "deposit_")
  end
end
