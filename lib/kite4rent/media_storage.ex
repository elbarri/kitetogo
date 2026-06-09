defmodule Kite4rent.MediaStorage do
  @moduledoc """
  Handles storage of media files from WhatsApp messages.
  """

  require Logger
  alias Kite4rent.Messages
  alias Kite4rent.WhatsappClient

  @media_dir "priv/media/whatsapp"

  @doc """
  Downloads and stores a media file from WhatsApp.
  Returns the path to the stored file.
  """
  def download_and_store_media(message_id, media_id) do
    # Create media directory if it doesn't exist
    File.mkdir_p!(@media_dir)

    with {:ok, media_data} <- WhatsappClient.download_media(media_id),
         filename = generate_filename(message_id, media_data),
         filepath = Path.join(@media_dir, filename),
         :ok <- File.write(filepath, media_data) do
      Messages.update_message_media_path(message_id, filepath)

      {:ok, {:media_path, filepath}}
    else
      {:error, reason} ->
        Logger.error("Failed to download and store media: #{inspect(reason)}",
          error: :media_storage_failed,
          message_id: message_id,
          media_id: media_id,
          media_dir: @media_dir,
          reason: reason
        )

        {:error, :media_storage_failed, "Failed to download and store media: #{inspect(reason)}"}
    end
  end

  @doc """
  Generates a unique filename for a media file.
  """
  def generate_filename(message_id, media_data) do
    # Extract a short hash from the message ID
    hash =
      message_id
      |> String.slice(0, 8)
      |> Base.encode16(case: :lower)

    # Get file extension based on content
    extension =
      case media_data do
        # JPEG magic bytes
        <<255, 216, 255, _rest::binary>> -> ".jpg"
        # PNG magic bytes
        <<137, 80, 78, 71, _rest::binary>> -> ".png"
        # GIF magic bytes
        <<71, 73, 70, _rest::binary>> -> ".gif"
        # WEBP magic bytes
        <<82, 73, 70, 70, _rest::binary>> -> ".webp"
        # OGG magic bytes
        <<79, 103, 103, 83, _rest::binary>> -> ".ogg"
        # Default binary
        _ -> ".bin"
      end

    # Generate timestamp
    timestamp = DateTime.utc_now() |> DateTime.to_unix()

    # Combine into filename
    "#{hash}_#{timestamp}#{extension}"
  end

  @doc """
  Gets the path to a media file for a given message.
  """
  def get_media_path(message_id) do
    case Messages.get_message_by_whatsapp_id!(message_id) do
      %{content: %{"media_path" => path}} when is_binary(path) and path != "" -> {:ok, path}
      _ -> {:error, :not_found}
    end
  end
end
