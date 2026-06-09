defmodule Kite4rent.AudioProcessor.AssemblyAI do
  @moduledoc """
  AssemblyAI transcription provider for audio files.
  Uses the European endpoint: api.eu.assemblyai.com
  """
  require Logger
  alias Kite4rent.Utils.HTTPClient
  alias Kite4rent.InputSanitizer

  @doc """
  Transcribe audio using AssemblyAI API.
  """
  @spec transcribe(binary()) ::
          {:ok, %{language: binary(), text: binary()}} | {:error, atom(), binary()}
  def transcribe(audio_path) do
    config = get_config()

    with {:ok, upload_url} <- upload_audio(audio_path, config),
         {:ok, transcript_id} <- create_transcript(upload_url, config),
         {:ok, result} <- poll_transcript_result(transcript_id, config) do
      {:ok,
       %{
         language: InputSanitizer.sanitize_language(result["language_code"] || "auto"),
         text: result["text"] || ""
       }}
    else
      {:error, reason} ->
        Logger.error("AssemblyAI transcription failed: #{inspect(reason)}",
          error: :assemblyai_transcription_failed,
          audio_path: audio_path,
          reason: reason
        )

        {:error, :assemblyai_transcription_failed, "AssemblyAI transcription failed: #{inspect(reason)}"}
    end
  end

  defp get_config do
    Application.get_env(:kite4rent, :audio_transcription)
    |> get_in([:providers, :assemblyai])
  end

  defp http_client do
    Application.get_env(:kite4rent, :http_client, HTTPClient)
  end

  defp upload_audio(audio_path, config) do
    Logger.info("Uploading audio file to AssemblyAI: #{audio_path}")

    case File.read(audio_path) do
      {:ok, audio_data} ->
        headers = [
          {"Authorization", config.api_key},
          {"Content-Type", "application/octet-stream"}
        ]

        url = "#{config.base_url}/upload"

        case http_client().request(:post, url, headers, audio_data) do
          {:ok, response_body} ->
            case Jason.decode(response_body) do
              {:ok, %{"upload_url" => upload_url}} ->
                {:ok, upload_url}

              {:ok, response} ->
                {:error, "Invalid upload response: #{inspect(response)}"}

              {:error, reason} ->
                {:error, "Failed to parse upload response: #{reason}"}
            end

          {:error, reason} ->
            {:error, "Upload failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read audio file: #{reason}"}
    end
  end

  defp create_transcript(upload_url, config) do
    Logger.info("Creating transcript for uploaded audio")

    body = %{
      audio_url: upload_url,
      language_detection: config.language_detection
    }

    headers = [
      {"Authorization", config.api_key},
      {"Content-Type", "application/json"}
    ]

    url = "#{config.base_url}/transcript"

    case http_client().request(:post, url, headers, body) do
      {:ok, response_body} ->
        case Jason.decode(response_body) do
          {:ok, %{"id" => transcript_id}} ->
            Logger.info("Transcript created with ID: #{transcript_id}")
            {:ok, transcript_id}

          {:ok, response} ->
            {:error, "Invalid transcript response: #{inspect(response)}"}

          {:error, reason} ->
            {:error, "Failed to parse transcript response: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Create transcript failed: #{inspect(reason)}"}
    end
  end

  defp poll_transcript_result(transcript_id, config, retry_count \\ 0) do
    # Max 5 minutes with 10-second intervals
    max_retries = 30
    # 10 seconds
    retry_interval = 10_000

    if retry_count >= max_retries do
      {:error, "Transcript polling timeout after #{max_retries} retries"}
    else
      headers = [
        {"Authorization", config.api_key}
      ]

      url = "#{config.base_url}/transcript/#{transcript_id}"

      case http_client().request(:get, url, headers) do
        {:ok, response_body} ->
          case Jason.decode(response_body) do
            {:ok, %{"status" => "completed"} = result} ->
              Logger.info("Transcript completed successfully")
              {:ok, result}

            {:ok, %{"status" => "error", "error" => error}} ->
              {:error, "Transcript processing error: #{error}"}

            {:ok, %{"status" => status}} when status in ["queued", "processing"] ->
              Logger.info("Transcript status: #{status}, retrying in #{retry_interval}ms...")
              Process.sleep(retry_interval)
              poll_transcript_result(transcript_id, config, retry_count + 1)

            {:ok, response} ->
              {:error, "Unknown transcript status: #{inspect(response)}"}

            {:error, reason} ->
              {:error, "Failed to parse transcript status: #{reason}"}
          end

        {:error, reason} ->
          {:error, "Failed to poll transcript: #{inspect(reason)}"}
      end
    end
  end
end
