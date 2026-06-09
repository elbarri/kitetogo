defmodule Kite4rent.MessageProcessor.Flows.GearEdit do
  @moduledoc """
  Handles the gear edit conversation flow — selecting an item,
  choosing a field to edit (brand/model/delete), and applying changes.
  """

  require Logger

  alias Kite4rent.Conversation.Manager, as: FlowManager
  alias Kite4rent.Deposits
  alias Kite4rent.GearFormatter
  alias Kite4rent.MessageProcessor.TextUtils
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.Rental
  alias Kite4rent.ReplyComposer

  @doc "Handle item selection from interactive list"
  def handle_gear_edit_selection(%WhatsappMessage{user: user, content: content}) do
    list_reply = content["list_reply"]

    case list_reply do
      %{"id" => "edit_gear_delete_all"} ->
        handle_delete_all(user)

      %{"id" => "edit_gear_" <> gear_id_str} ->
        case Integer.parse(gear_id_str) do
          {gear_id, ""} ->
            select_gear_item(user, gear_id)

          _ ->
            :not_in_flow
        end

      _ ->
        :not_in_flow
    end
  end

  @doc "Handle field selection from interactive buttons"
  def handle_gear_edit_field_selection(%WhatsappMessage{user: user, content: content}, collected_data) do
    button_reply = content["button_reply"]

    case button_reply do
      %{"id" => "edit_field_delete"} ->
        handle_delete(user, collected_data)

      %{"id" => "edit_field_brand"} ->
        set_awaiting_value(user, "brand", collected_data)

      %{"id" => "edit_field_model"} ->
        set_awaiting_value(user, "model", collected_data)

      _ ->
        :not_in_flow
    end
  end

  @doc "Handle text/audio value input for editing a field"
  def handle_gear_edit_value_input(%WhatsappMessage{user: user} = message, collected_data) do
    text = TextUtils.extract_text_from_message(message)

    if text && String.trim(text) != "" do
      field = collected_data["edit_field"]
      gear_id = collected_data["gear_id"]

      gear = Rental.get_gear!(gear_id)

      if gear.user_id != user.id do
        FlowManager.clear_flow(user.id)
        :not_in_flow
      else
        attrs = build_update_attrs(field, String.trim(text))

        case Rental.update_gear(gear, attrs) do
          {:ok, updated_gear} ->
            Logger.info("User #{user.id} edited gear #{gear_id} field=#{field}")
            FlowManager.clear_flow(user.id)
            {:handled, ReplyComposer.compose_reply({:edit_gear_success, updated_gear}, user)}

          {:error, _changeset} ->
            FlowManager.clear_flow(user.id)
            {:handled, {:ok, {:reaction, "❌"}}}
        end
      end
    else
      :not_in_flow
    end
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp handle_delete_all(user) do
    {:ok, deleted_count} = Rental.delete_all_gear_for_user(user.id)
    Logger.info("User #{user.id} deleted all gear (#{deleted_count} items)")
    FlowManager.clear_flow(user.id)

    language = Kite4rent.Users.User.get_language(user)

    message =
      Kite4rent.ResponseTemplates.get_template(:inventory_deleted, language, %{
        count: deleted_count
      })

    {:handled, {:ok, {:text, message}}}
  end

  defp select_gear_item(user, gear_id) do
    gear = Rental.get_gear!(gear_id)

    cond do
      gear.user_id != user.id ->
        FlowManager.clear_flow(user.id)
        :not_in_flow

      Deposits.has_active_deposit_for_gear?(gear_id) ->
        FlowManager.clear_flow(user.id)
        {:handled, ReplyComposer.compose_reply({:edit_gear_active_deposit, gear}, user)}

      true ->
        FlowManager.add_data(user.id, %{"gear_id" => gear_id})
        FlowManager.update_step(user.id, :selecting_field)
        {:handled, ReplyComposer.compose_reply({:edit_gear_select_field, gear}, user)}
    end
  rescue
    Ecto.NoResultsError ->
      FlowManager.clear_flow(user.id)
      :not_in_flow
  end

  defp handle_delete(user, collected_data) do
    gear_id = collected_data["gear_id"]
    gear = Rental.get_gear!(gear_id)

    cond do
      gear.user_id != user.id ->
        FlowManager.clear_flow(user.id)
        :not_in_flow

      Deposits.has_active_deposit_for_gear?(gear_id) ->
        FlowManager.clear_flow(user.id)
        {:handled, ReplyComposer.compose_reply({:edit_gear_active_deposit, gear}, user)}

      true ->
        case Rental.delete_gear(gear) do
          {:ok, _deleted} ->
            Logger.info("User #{user.id} deleted gear #{gear_id}")
            FlowManager.clear_flow(user.id)

            formatted = GearFormatter.format_gear(gear)
            {:handled, {:ok, {:text, "✅ #{formatted}"}}}

          {:error, _} ->
            FlowManager.clear_flow(user.id)
            {:handled, {:ok, {:reaction, "❌"}}}
        end
    end
  rescue
    Ecto.NoResultsError ->
      FlowManager.clear_flow(user.id)
      :not_in_flow
  end

  defp set_awaiting_value(user, field, collected_data) do
    gear_id = collected_data["gear_id"]
    gear = Rental.get_gear!(gear_id)

    FlowManager.add_data(user.id, %{"edit_field" => field})
    FlowManager.update_step(user.id, :awaiting_value)

    current_value =
      case field do
        "brand" -> gear.brand
        "model" -> gear.model
      end

    {:handled,
     ReplyComposer.compose_reply({:edit_gear_ask_value, %{field: field, current_value: current_value}}, user)}
  rescue
    Ecto.NoResultsError ->
      FlowManager.clear_flow(user.id)
      :not_in_flow
  end

  defp build_update_attrs("brand", text), do: %{brand: text}
  defp build_update_attrs("model", text), do: %{model: text}
end
