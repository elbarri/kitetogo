defmodule Kite4rent.AudioProcessor do
  @moduledoc """
  Handles processing of audio files, including conversion to text.
  Supports multiple transcription providers: local Whisper and AssemblyAI.
  """
  require Logger

  alias Kite4rent.AudioProcessor.LocalWhisper
  alias Kite4rent.AudioProcessor.AssemblyAI

  @doc """
  Convert audio binary data to text.
  Expects OGG/Opus audio data from WhatsApp.
  Uses the configured transcription provider.
  """
  @spec transcribe({:audio_path, binary()}) ::
          {:ok, %{language: binary(), text: binary()}} | {:error, binary()}
  def transcribe({:audio_path, audio_path}) do
    provider = get_transcription_provider()

    case provider do
      :local_whisper ->
        LocalWhisper.transcribe(audio_path)

      :assemblyai ->
        AssemblyAI.transcribe(audio_path)

      _ ->
        Logger.error("Unknown transcription provider: #{provider}",
          error: :unknown_transcription_provider,
          provider: provider,
          available_providers: [:local_whisper, :assemblyai]
        )

        {:error, :unknown_transcription_provider, "Unknown transcription provider: #{provider}"}
    end
  end

  def transcribe({:audio_binary, _audio_binary}) do
    # TODO: implement this
    Logger.error("Audio binary transcription not yet supported",
      error: :audio_binary_not_supported,
      feature: "audio_binary_transcription",
      status: "not_implemented"
    )

    {:error, :audio_binary_not_supported, "Audio binary transcription not yet supported"}
  end

  def get_transcription_provider do
    Application.get_env(:kite4rent, :audio_transcription)
    |> get_in([:default_provider])
    |> case do
      # fallback to local whisper
      nil -> :local_whisper
      provider -> provider
    end
  end

  # Kept for backward compatibility - this function is used in the original AudioProcessor
  def extract_text_from_transcription_json(json_content) do
    LocalWhisper.extract_text_from_transcription_json(json_content)
  end
end
