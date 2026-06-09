defmodule Kite4rent.MessageProcessor.ActionHandler do
  @moduledoc """
  Dispatches rules engine actions to appropriate handlers.
  """
  require Logger

  alias Kite4rent.AudioProcessor
  alias Kite4rent.Deposits
  alias Kite4rent.IntentionHandler
  alias Kite4rent.MediaStorage
  alias Kite4rent.Messages
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.MessageProcessor.Flows.DepositItemSelection
  alias Kite4rent.Rental
  alias Kite4rent.ReplyComposer
  alias Kite4rent.Repo
  alias Kite4rent.ResponseTemplates
  alias Kite4rent.Users
  alias Kite4rent.Users.User
  alias Kite4rent.WhatsappClient
  alias Wongi.Engine

  @doc "Dispatch actions from the rules engine"
  def dispatch(engine, message) do
    case query_actions(engine) do
      [{:grant_consent, _priority} | _] ->
        handle_grant_consent_action(message)

      [{:acknowledge_reaction, _priority} | _] ->
        {:ok, :reaction_acknowledged}

      [{:find_gear_around_location, _priority} | _] ->
        handle_find_gear_action(engine, message)

      [{:search_in_closest_location, _priority} | _] ->
        handle_search_in_closest_location_action(engine, message)

      [{:update_user_location, _priority} | _] ->
        handle_update_location_action(engine, message)

      [{:update_location_and_act_on_intention, _priority} | _] ->
        handle_update_location_and_act_on_intention_action(engine, message)

      [{:show_location_options, _priority} | _] ->
        handle_show_location_options_action(engine, message)

      [{:invalid_location_coordinates, _priority} | _] ->
        {:error, :invalid_coordinates}

      [{:handle_contact_selection, _priority} | _] ->
        handle_contact_selection_action(engine, message)

      [{:process_with_llm, _priority} | _] ->
        handle_process_with_llm_action(message)

      [{:process_audio_with_llm, _priority} | _] ->
        handle_process_audio_with_llm_action(engine, message)

      [{:disambiguate_location, _priority} | _] ->
        handle_disambiguate_location_action(engine, message)

      [{:handle_list_reply_not_implemented, _priority} | _] ->
        handle_list_reply_not_implemented_action(engine, message)

      [{:attach_renter_to_deposit, _priority} | _] ->
        handle_attach_renter_to_deposit_action(engine, message)

      [{:contacts_no_pending_deposit, _priority} | _] ->
        handle_contacts_no_pending_deposit_action(message)

      [{:release_deposit, _priority} | _] ->
        handle_release_deposit_action(engine, message)

      [{:initiate_dispute, _priority} | _] ->
        handle_initiate_dispute_action(engine, message)

      [{:confirm_return_ok, _priority} | _] ->
        handle_confirm_return_ok_action(engine, message)

      [{:deposit_add_more_item, _priority} | _] ->
        DepositItemSelection.handle_deposit_add_more_item_action(message)

      [{:deposit_proceed_to_duration, _priority} | _] ->
        DepositItemSelection.handle_deposit_proceed_to_duration_action(message)

      [] ->
        handle_unsupported_message(message)
    end
  end

  # ============================================================================
  # Query Actions
  # ============================================================================

  defp query_actions(engine) do
    Engine.select(engine, {:_, :action_type, :_})
    |> Enum.map(fn wme ->
      action_type = wme.object
      priority = get_action_priority(engine, wme.subject)
      {action_type, priority}
    end)
    |> Enum.sort_by(fn {_type, priority} -> priority end, :desc)
  end

  defp get_action_priority(engine, subject) do
    case Engine.select(engine, {subject, :priority, :_}) |> Enum.to_list() do
      [wme | _] -> wme.object
      [] -> 0
    end
  end

  defp get_action_data(engine, predicate) do
    case Engine.select(engine, {:_, predicate, :_}) |> Enum.to_list() do
      [wme | _] -> wme.object
      [] -> nil
    end
  end

  # ============================================================================
  # Action Handlers
  # ============================================================================

  defp handle_grant_consent_action(message) do
    user = Users.get_user!(message.user_id)

    case Users.update_user(user, %{
           contact_sharing_consent: true,
           contact_sharing_consent_at: DateTime.utc_now()
         }) do
      {:ok, updated_user} ->
        Logger.info("User #{user.id} gave consent for contact sharing via thumbs up reaction")

        {:ok, gear} = Rental.list_available_gear_for_user(user.id)

        case ReplyComposer.compose_reply({:list_own_inventory, gear}, updated_user) do
          {:ok, {response_type, response_content}} ->
            schedule_deposit_reminder(updated_user)
            {:ok, {response_type, response_content}}

          error ->
            Logger.error("Failed to compose reply after consent: #{inspect(error)}")
            {:ok, :reaction_acknowledged}
        end

      {:error, changeset} ->
        Logger.error("Failed to update user consent: #{inspect(changeset.errors)}")
        {:ok, :reaction_acknowledged}
    end
  end

  defp schedule_deposit_reminder(user) do
    Task.start(fn ->
      Process.sleep(1500)

      reminder_message =
        ResponseTemplates.get_template(:deposit_reminder_after_consent, user.language)

      WhatsappClient.send_message(user.whatsapp, reminder_message)
    end)
  end

  defp handle_find_gear_action(engine, message) do
    location = get_action_data(engine, :location)

    location
    |> IntentionHandler.RequestGear.find_near(message.user)
    |> case do
      {:ok, {request_gear, user}} ->
        ReplyComposer.compose_reply(request_gear, user)

      {:error, reason} ->
        compose_error_reply(reason, message)
    end
  end

  defp handle_search_in_closest_location_action(engine, message) do
    closest_location = get_action_data(engine, :closest_location)

    closest_location
    |> IntentionHandler.RequestGear.find_near(message.user)
    |> case do
      {:ok, {request_gear, user}} ->
        ReplyComposer.compose_reply(request_gear, user)

      {:error, reason} ->
        compose_error_reply(reason, message)
    end
  end

  defp handle_update_location_action(engine, message) do
    location = get_action_data(engine, :location)

    case Users.update_user_location(message.user, location) do
      {:ok, user} ->
        ReplyComposer.compose_reply({:location_updated, location}, user)

      {:error, reason} ->
        compose_error_reply(reason, message)
    end
  end

  defp handle_update_location_and_act_on_intention_action(engine, message) do
    location = get_action_data(engine, :location)
    llm_response = get_action_data(engine, :llm_response)

    case llm_response.intention do
      "offer_gear" ->
        case Users.update_user_location(message.user, location) do
          {:ok, user} ->
            updated_llm_response = %{llm_response | location: nil}
            Kite4rent.MessageProcessor.act_on_intention(updated_llm_response, %{message | user: user})

          {:error, reason} ->
            compose_error_reply(reason, llm_response, message)
        end

      "request_gear" ->
        updated_llm_response = %{llm_response | location: location.name}
        Kite4rent.MessageProcessor.act_on_intention(updated_llm_response, message)

      _ ->
        updated_llm_response = %{llm_response | location: location.name}

        case Users.update_user_location(message.user, location) do
          {:ok, user} ->
            Kite4rent.MessageProcessor.act_on_intention(updated_llm_response, %{message | user: user})

          {:error, reason} ->
            compose_error_reply(reason, updated_llm_response, message)
        end
    end
  end

  defp handle_show_location_options_action(engine, message) do
    location = get_action_data(engine, :location)
    ReplyComposer.compose_reply({:location_options, location}, message.user)
  end

  defp handle_contact_selection_action(engine, message) do
    selection_number = get_action_data(engine, :selection_number)
    gear_list_users = get_action_data(engine, :gear_list_users)
    has_paid_access = get_action_data(engine, :has_paid_access)

    listed_users_with_int_keys =
      gear_list_users
      |> Enum.map(fn {key, value} ->
        case key do
          key when is_binary(key) ->
            case Integer.parse(key) do
              {int_key, ""} -> {int_key, value}
              _ -> {key, value}
            end

          key when is_integer(key) ->
            {key, value}
        end
      end)
      |> Map.new()

    case Map.get(listed_users_with_int_keys, selection_number) do
      nil ->
        ReplyComposer.compose_reply({:contact_selection_invalid}, message.user)

      selected_user_id ->
        case has_paid_access do
          true ->
            {:ok, {:contact, selected_user_id}}

          false ->
            ReplyComposer.compose_reply(
              {:contact_payment_cta, message.phone_number, selected_user_id},
              message.user
            )
        end
    end
  end

  defp handle_process_with_llm_action(message) do
    message_body = get_in(message.content, ["body"]) || ""
    Kite4rent.MessageProcessor.LLMProcessing.process_llm_content(message, message_body, :text)
  end

  defp handle_process_audio_with_llm_action(engine, message) do
    media_id = get_action_data(engine, :media_id)

    with {:ok, {:media_path, audio_path}} <-
           MediaStorage.download_and_store_media(message.message_id, media_id),
         {:ok, %{text: text, language: lang} = transcription} <-
           AudioProcessor.transcribe({:audio_path, audio_path}) do
      Kite4rent.MessageProcessor.LLMProcessing.process_llm_content(message, text, :audio,
        language: lang,
        media_id: media_id,
        transcription: transcription
      )
    else
      error ->
        Kite4rent.MessageProcessor.LLMProcessing.handle_processing_error(error, message, :audio, media_id: media_id)
    end
  end

  defp handle_disambiguate_location_action(engine, message) do
    selection_id = get_action_data(engine, :selection_id)

    case String.split(selection_id, "_") do
      ["disambiguate", _country_code, lat_str, lng_str] ->
        lat = String.to_float(lat_str)
        lng = String.to_float(lng_str)

        original_location_name =
          case message.context do
            %{"id" => context_message_id} ->
              case Messages.get_message_by_whatsapp_id(context_message_id) do
                {:ok, context_message} ->
                  get_in(context_message.content, ["original_location_name"]) || "Unknown"

                _ ->
                  "Unknown"
              end

            _ ->
              "Unknown"
          end

        location = %Kite4rent.Location{
          name: original_location_name,
          latitude: lat,
          longitude: lng,
          radius_km: 25
        }

        IntentionHandler.RequestGear.find_near(location, message.user)
        |> case do
          {:ok, {request_gear, user}} ->
            ReplyComposer.compose_reply(request_gear, user)

          {:error, reason} ->
            compose_error_reply(reason, message)
        end

      _ ->
        Logger.error("Invalid disambiguation selection_id format: #{selection_id}")
        compose_error_reply(:invalid_selection, message)
    end
  end

  defp handle_list_reply_not_implemented_action(engine, message) do
    selection_id = get_action_data(engine, :selection_id)

    Logger.error("List reply not implemented yet",
      error: :list_reply_not_implemented_yet,
      phone_number: message.phone_number,
      user_id: message.user_id,
      message_id: message.message_id,
      type: "list_reply",
      selection_id: selection_id
    )

    compose_error_reply(:unsupported_message_type, message)
  end

  defp handle_unsupported_message(%WhatsappMessage{type: type, content: content} = message) do
    case type do
      "interactive" ->
        interactive_type = content["type"]
        Logger.warning("Unknown interactive message type: #{interactive_type}")
        compose_error_reply(:unsupported_message_type, message)

      _ ->
        Logger.info(
          "Ignoring unsupported message. id: #{message.message_id}, type: #{type} from #{message.phone_number}"
        )

        {:ok, :ignored}
    end
  end

  # =============================================================================
  # Contacts Message Handlers
  # =============================================================================

  defp handle_attach_renter_to_deposit_action(engine, %WhatsappMessage{} = message) do
    deposit_id = get_action_data(engine, :deposit_id)
    contacts = message.content["contacts"] || []

    case contacts do
      [] ->
        Logger.warning("No contacts found in message")
        {:error, :no_contacts}

      [first_contact | _] ->
        phones = get_in(first_contact, ["phones"]) || []
        first_phone = get_in(phones, [Access.at(0), "phone"])
        contact_name = get_in(first_contact, ["name", "formatted_name"])

        if first_phone do
          normalized_phone = String.replace(first_phone, ~r/[^\d]/, "")

          case Users.get_user_by_phone(normalized_phone) do
            {:ok, renter} ->
              case Deposits.attach_renter(deposit_id, renter.id) do
                {:ok, deposit} ->
                  Logger.info("Attached renter #{renter.id} to deposit #{deposit_id}")
                  ReplyComposer.compose_reply({:renter_attached, deposit}, message.user)

                {:error, reason} ->
                  Logger.error("Failed to attach renter to deposit: #{inspect(reason)}")
                  {:error, :attach_renter_failed}
              end

            {:error, :not_found} ->
              Logger.info("Contact #{contact_name} (#{first_phone}) not found in system")

              ReplyComposer.compose_reply(
                {:contact_not_registered, contact_name, first_phone},
                message.user
              )
          end
        else
          Logger.warning("Contact has no phone number")
          {:error, :contact_no_phone}
        end
    end
  end

  defp handle_contacts_no_pending_deposit_action(%WhatsappMessage{} = message) do
    Logger.info(
      "Received contacts message but user has no pending deposit request. user_id: #{message.user_id}"
    )

    {:ok, :contacts_received_no_action}
  end

  # =============================================================================
  # Deposit Action Handlers
  # =============================================================================

  defp handle_release_deposit_action(engine, %WhatsappMessage{} = message) do
    deposit_id = get_action_data(engine, :deposit_id)
    deposit = Deposits.get_security_deposit!(deposit_id)

    case cancel_stripe_authorization(deposit) do
      :ok ->
        case Deposits.release_deposit(deposit_id) do
          {:ok, released_deposit} ->
            Logger.info("Owner released deposit #{deposit_id}")
            released_deposit = Repo.preload(released_deposit, [:owner, :renter])
            owner_result =
              ReplyComposer.compose_reply({:deposit_released, released_deposit}, message.user)
            notify_renter_deposit_released(released_deposit)
            owner_result

          {:error, reason} ->
            Logger.error(
              "Failed to update deposit status after Stripe cancellation: #{inspect(reason)}"
            )
            {:error, :deposit_release_db_failed}
        end

      {:error, reason} ->
        Logger.error(
          "Failed to cancel Stripe authorization for deposit #{deposit_id}: #{inspect(reason)}"
        )
        {:error, :stripe_cancel_failed}
    end
  end

  defp cancel_stripe_authorization(%{stripe_payment_intent_id: nil}), do: :ok

  defp cancel_stripe_authorization(%{stripe_payment_intent_id: intent_id}) do
    case Stripe.PaymentIntent.cancel(intent_id) do
      {:ok, _cancelled_intent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp notify_renter_deposit_released(deposit) do
    language = User.get_language(deposit.renter)
    amount_formatted = "#{deposit.amount} #{deposit.currency}"
    owner_name = deposit.owner.name || "the owner"

    message =
      ResponseTemplates.get_template(:deposit_released_renter, language, %{
        amount: amount_formatted,
        owner_name: owner_name
      })

    WhatsappClient.send_message(deposit.renter.whatsapp, message)
    Logger.info("Renter #{deposit.renter_id} notified of deposit release")
  end

  # =============================================================================
  # Dispute Handlers
  # =============================================================================

  defp handle_initiate_dispute_action(engine, %WhatsappMessage{} = _message) do
    deposit_id = get_action_data(engine, :deposit_id)
    initiator_role = get_action_data(engine, :initiator_role)

    deposit = Deposits.get_deposit_with_items_and_users(deposit_id)

    case Deposits.mark_as_disputed(deposit_id) do
      {:ok, _disputed_deposit} ->
        Logger.info("Deposit #{deposit_id} marked as disputed by #{initiator_role}")

        amount_formatted = "#{deposit.amount} #{deposit.currency}"

        {initiator, counterparty} =
          if initiator_role == :owner do
            {deposit.owner, deposit.renter}
          else
            {deposit.renter, deposit.owner}
          end

        initiator_language = User.get_language(initiator)
        initiator_message = ResponseTemplates.get_template(:deposit_dispute_initiated, initiator_language, %{
          amount: amount_formatted
        })
        WhatsappClient.send_message(initiator.whatsapp, initiator_message)

        notify_counterparty_dispute(counterparty, deposit, initiator)
        notify_admin_dispute(deposit, initiator, initiator_role)

        {:ok, :dispute_initiated}

      {:error, reason} ->
        Logger.error("Failed to mark deposit #{deposit_id} as disputed: #{inspect(reason)}")
        {:error, :dispute_failed}
    end
  end

  defp notify_counterparty_dispute(counterparty, deposit, initiator) do
    language = User.get_language(counterparty)
    amount_formatted = "#{deposit.amount} #{deposit.currency}"
    initiator_name = initiator.name || "the other party"

    message = ResponseTemplates.get_template(:deposit_dispute_notif_counterparty, language, %{
      initiator_name: initiator_name,
      amount: amount_formatted
    })

    WhatsappClient.send_message(counterparty.whatsapp, message)
    Logger.info("Counterparty #{counterparty.id} notified of dispute")
  end

  defp notify_admin_dispute(deposit, initiator, initiator_role) do
    admin_phone = Application.get_env(:kite4rent, :admin_phone)

    if admin_phone do
      amount_formatted = "#{deposit.amount} #{deposit.currency}"
      initiator_name = initiator.name || "Unknown"
      role_text = if initiator_role == :owner, do: "Owner", else: "Renter"

      message = """
      🚨 DEPOSIT DISPUTE OPENED

      Deposit ID: #{deposit.id}
      Amount: #{amount_formatted}
      Duration: #{deposit.duration_hours} hours

      Initiated by: #{initiator_name} (#{role_text})
      Owner: #{deposit.owner.name || "Unknown"} (#{deposit.owner.whatsapp})
      Renter: #{deposit.renter.name || "Unknown"} (#{deposit.renter.whatsapp})

      Both parties have been asked to send photos and explanations.
      """

      WhatsappClient.send_message(admin_phone, message)
      Logger.info("Admin notified of dispute for deposit #{deposit.id}")
    else
      Logger.warning("Admin phone not configured - cannot notify admin of dispute")
    end
  end

  # =============================================================================
  # Return OK Handler
  # =============================================================================

  defp handle_confirm_return_ok_action(engine, %WhatsappMessage{} = message) do
    deposit_id = get_action_data(engine, :deposit_id)
    deposit = Deposits.get_deposit_with_items_and_users(deposit_id)

    if deposit.status == "released" do
      language = User.get_language(message.user)
      amount_formatted = "#{deposit.amount} #{deposit.currency}"
      owner_name = deposit.owner.name || "the owner"

      response_message = ResponseTemplates.get_template(:deposit_return_ok_already_released, language, %{
        amount: amount_formatted,
        owner_name: owner_name
      })

      WhatsappClient.send_message(message.user.whatsapp, response_message)
      Logger.info("Renter #{message.user.id} confirmed return OK but deposit already released")

      {:ok, :already_released}
    else
      language = User.get_language(message.user)
      owner_name = deposit.owner.name || "the owner"

      response_message = ResponseTemplates.get_template(:deposit_return_ok_waiting, language, %{
        owner_name: owner_name
      })

      WhatsappClient.send_message(message.user.whatsapp, response_message)
      Logger.info("Renter #{message.user.id} confirmed return OK, waiting for owner to release")

      notify_owner_renter_confirmed_return_ok(deposit)

      {:ok, :waiting_for_owner}
    end
  end

  defp notify_owner_renter_confirmed_return_ok(deposit) do
    language = User.get_language(deposit.owner)
    amount_formatted = "#{deposit.amount} #{deposit.currency}"
    renter_name = deposit.renter.name || "the renter"

    message = ResponseTemplates.get_template(:deposit_return_ok_owner_notification, language, %{
      renter_name: renter_name,
      amount: amount_formatted
    })

    WhatsappClient.send_message(deposit.owner.whatsapp, message)
    Logger.info("Owner #{deposit.owner_id} notified that renter confirmed return OK")
  end

  # =============================================================================
  # Error Reply Helpers
  # =============================================================================

  defp compose_error_reply(reason, %WhatsappMessage{user: user} = _message) do
    Logger.warning("Failed to compose error reply for reason: #{inspect(reason)}")
    ReplyComposer.compose_reply({:error, reason}, user)
  end

  defp compose_error_reply(reason, _llm_response, %WhatsappMessage{user: user} = _message) do
    Logger.warning("Unhandled error in compose_error_reply/3: #{inspect(reason)}")
    ReplyComposer.compose_reply({:error, reason}, user)
  end
end
