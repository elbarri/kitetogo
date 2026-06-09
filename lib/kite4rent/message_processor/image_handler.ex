defmodule Kite4rent.MessageProcessor.ImageHandler do
  @moduledoc """
  Handles image message processing - gear condition photos for rental agreements.
  """
  require Logger

  alias Kite4rent.Agreements
  alias Kite4rent.MediaStorage
  alias Kite4rent.Messages.WhatsappMessage
  alias Kite4rent.Repo
  alias Kite4rent.ResponseTemplates
  alias Kite4rent.Users.User
  alias Kite4rent.WhatsappClient

  def handle_image_message(
        %WhatsappMessage{content: content, message_id: message_id} = message,
        %User{} = user
      ) do
    case get_disputed_deposit_for_user(user.id) do
      {:ok, _deposit} ->
        Logger.info(
          "User #{user.id} sent photo during active dispute - reacting with salute emoji"
        )

        WhatsappClient.send_reaction(user.whatsapp, message_id, "🫡")
        {:ok, :acknowledged}

      :no_disputed_deposit ->
        case get_draft_agreement_for_owner(user.id) do
          {:ok, agreement} ->
            handle_agreement_photo(message, user, agreement, content)

          :no_draft_agreement ->
            Logger.info(
              "Ignoring image message #{message_id} from user #{user.id} - no draft agreement"
            )

            {:ok, :ignored}
        end
    end
  end

  defp get_disputed_deposit_for_user(user_id) do
    import Ecto.Query

    query =
      from(d in Kite4rent.Deposits.SecurityDeposit,
        where:
          (d.owner_id == ^user_id or d.renter_id == ^user_id) and
            d.status == "disputed",
        order_by: [desc: d.inserted_at],
        limit: 1
      )

    case Repo.one(query) do
      nil -> :no_disputed_deposit
      deposit -> {:ok, deposit}
    end
  end

  defp get_draft_agreement_for_owner(user_id) do
    import Ecto.Query

    query =
      from(a in Kite4rent.Agreements.RentalAgreement,
        join: d in assoc(a, :security_deposit),
        where: d.owner_id == ^user_id and a.status in ["draft", "negotiating"],
        order_by: [desc: a.inserted_at],
        limit: 1,
        preload: [security_deposit: d]
      )

    case Repo.one(query) do
      nil -> :no_draft_agreement
      agreement -> {:ok, agreement}
    end
  end

  defp handle_agreement_photo(
         %WhatsappMessage{message_id: message_id} = _message,
         %User{} = user,
         agreement,
         content
       ) do
    media_id = content["id"]

    case MediaStorage.download_and_store_media(message_id, media_id) do
      {:ok, {:media_path, file_path}} ->
        caption = content["caption"]

        photo_attrs = %{
          rental_agreement_id: agreement.id,
          file_path: file_path,
          description: caption,
          uploaded_by_id: user.id
        }

        case Agreements.add_photo(photo_attrs) do
          {:ok, photo} ->
            Logger.info(
              "Added photo #{photo.id} to rental agreement #{agreement.id} for user #{user.id}"
            )

            Phoenix.PubSub.broadcast(
              Kite4rent.PubSub,
              "agreement:#{agreement.id}",
              {:photo_added, photo}
            )

            photos_count = length(Agreements.list_photos(agreement.id))
            language = User.get_language(user)

            confirmation =
              ResponseTemplates.get_template(:photo_added_to_agreement, language, %{
                photos_count: photos_count
              })

            {:ok, {:text, confirmation}}

          {:error, changeset} ->
            Logger.error(
              "Failed to create photo record for agreement #{agreement.id}: #{inspect(changeset.errors)}"
            )

            language = User.get_language(user)
            error_msg = ResponseTemplates.get_template(:generic_error, language)
            {:ok, {:text, error_msg}}
        end

      {:error, reason} ->
        Logger.error("Failed to download image for agreement: #{inspect(reason)}")
        language = User.get_language(user)
        error_msg = ResponseTemplates.get_template(:generic_error, language)
        {:ok, {:text, error_msg}}
    end
  end
end
