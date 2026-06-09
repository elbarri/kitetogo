defmodule Kite4rent.MessageProcessor.ConsentHandler do
  @moduledoc false

  require Logger

  alias Kite4rent.Messages
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.ReplyComposer
  alias Kite4rent.ResponseTemplates
  alias Kite4rent.Users
  alias Kite4rent.WhatsappClient

  @doc """
  Handles a thumbs-up reply that grants contact-sharing consent.
  Updates the user record, shows their inventory, and schedules a deposit reminder.
  """
  def handle_grant_consent(message) do
    user = Users.get_user!(message.user_id)

    case Users.update_user(user, %{
           contact_sharing_consent: true,
           contact_sharing_consent_at: DateTime.utc_now()
         }) do
      {:ok, updated_user} ->
        Logger.info("User #{user.id} gave consent for contact sharing via thumbs up reaction")

        {:ok, gear} = Kite4rent.Rental.list_available_gear_for_user(user.id)

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

  @doc """
  Returns true if the given message is a direct reply to a consent request message.
  """
  def replied_to_consent_request?(%WhatsappMessage{context: %{"id" => replied_to_id}}) do
    case Messages.get_message_by_whatsapp_id(replied_to_id) do
      {:ok, replied_message} ->
        replied_message.content["intent"] == "contact_sharing_consent_request"

      _ ->
        false
    end
  end

  def replied_to_consent_request?(%WhatsappMessage{user_id: user_id}) do
    case Messages.get_last_outgoing_message(user_id) do
      {:ok, last_message} ->
        last_message.content["intent"] == "contact_sharing_consent_request"

      _ ->
        false
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
end
