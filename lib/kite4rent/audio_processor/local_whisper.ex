defmodule Kite4rent.AudioProcessor.LocalWhisper do
  @moduledoc """
  Local Whisper transcription provider for audio files.
  Uses Whisper C++ implementation via CLI.
  """
  require Logger

  @transcriptions_dir "priv/media/transcriptions"

  @doc """
  Transcribe audio using local Whisper CLI.
  """
  @spec transcribe(binary()) ::
          {:ok, %{language: binary(), text: binary()}} | {:error, atom(), binary()}
  def transcribe(audio_path) do
    config = get_config()

    extensionless_transcription_path =
      (@transcriptions_dir <> "/" <> audio_path)
      |> String.split("/")
      |> List.last()
      |> String.split(".")
      |> hd()

    dest_file = Path.expand(@transcriptions_dir <> "/" <> extensionless_transcription_path)

    language = "auto"
    whisper_cli = Path.join([config.base_dir, config.whisper_cli])
    medium_model = Path.join([config.base_dir, config.models[:medium]])

    System.cmd(whisper_cli, [
      "-m",
      medium_model,
      "-f",
      audio_path,
      "-of",
      dest_file,
      "-l",
      language,
      "-oj"
    ])

    with {:ok, json_content} <- File.read(dest_file <> ".json"),
         {:ok, result_json} <- Jason.decode(json_content) do
      {:ok, extract_text_from_transcription_json(result_json)}
    else
      {:error, reason} ->
        Logger.error("Local Whisper transcription failed: #{inspect(reason)}",
          error: :local_whisper_transcription_failed,
          audio_path: audio_path,
          dest_file: dest_file,
          whisper_cli: whisper_cli,
          model: medium_model,
          reason: reason
        )

        {:error, :local_whisper_transcription_failed, "Local Whisper transcription failed: #{inspect(reason)}"}
    end
  end

  defp get_config do
    Application.get_env(:kite4rent, :audio_transcription)
    |> get_in([:providers, :local_whisper])
  end

  def extract_text_from_transcription_json(json_content) do
    %{
      language: json_content["result"]["language"],
      text:
        json_content
        |> Map.get("transcription", json_content)
        |> Enum.map(fn x -> x["text"] end)
        |> Enum.join("")
    }
  end
end
