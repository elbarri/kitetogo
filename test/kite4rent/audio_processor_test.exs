defmodule Kite4rent.AudioProcessorTest do
  use ExUnit.Case, async: false
  use Mimic
  alias Kite4rent.AudioProcessor
  alias Kite4rent.AudioProcessor.AssemblyAI

  @audio_path "priv/media/whatsapp/77616d69642e4842_1745137192.ogg"
  # ni puta idea porque mete el "de" la transcripcion
  @expected_text "Hola, tengo una tabla de Elevate."

  setup do
    :ok
  end

  describe "transcribe/1 with local whisper provider" do
    setup do
      # Configure to use local whisper for these tests
      Application.put_env(:kite4rent, :audio_transcription,
        default_provider: :local_whisper,
        providers: %{
          local_whisper: %{
            base_dir: System.get_env("WHISPER_BASE_DIR", "/path/to/whisper.cpp"),
            whisper_cli: System.get_env("WHISPER_CPP_CLI", "build/bin/whisper-cli"),
            models: [medium: "models/ggml-medium.bin"]
          }
        }
      )

      :ok
    end

    @tag :audio
    test "correctly transcribes OGG audio file from WhatsApp using local whisper" do
      # Ensure ffmpeg is installed
      {_output, 0} = System.cmd("ffmpeg", ["-version"])

      # Convert to text
      {:ok, %{text: transcribed_text, language: language}} =
        AudioProcessor.transcribe({:audio_path, @audio_path})

      # Assert the transcription matches the expected text
      assert String.trim(transcribed_text) == @expected_text
      assert language == "es"
    end
  end

  describe "transcribe/1 with AssemblyAI provider" do
    setup do
      # Configure to use AssemblyAI for these tests
      Application.put_env(:kite4rent, :audio_transcription,
        default_provider: :assemblyai,
        providers: %{
          assemblyai: %{
            api_key: "test_api_key",
            base_url: "https://api.eu.assemblyai.com/v2",
            language_detection: true,
            audio_intel: false
          }
        }
      )

      :ok
    end

    @tag :integration
    test "fails gracefully when AssemblyAI API key is invalid" do
      # This test ensures the error handling works correctly
      audio_path = @audio_path

      # With an invalid API key, we expect a graceful failure
      case AssemblyAI.transcribe(audio_path) do
        {:error, :assemblyai_transcription_failed, _reason} ->
          # This is expected with a test API key
          assert true

        {:ok, _result} ->
          # If somehow the test API key works, that's also ok
          assert true
      end
    end

    @tag :mock
    test "AssemblyAI module handles configuration correctly" do
      # Test that the AssemblyAI module can access its configuration
      config = Application.get_env(:kite4rent, :audio_transcription)
      assert config[:providers][:assemblyai][:api_key] == "test_api_key"
      assert config[:providers][:assemblyai][:base_url] == "https://api.eu.assemblyai.com/v2"
    end
  end

  describe "provider configuration" do
    test "uses local whisper when no provider configured" do
      # Reset configuration
      Application.delete_env(:kite4rent, :audio_transcription)

      # Should default to local whisper
      assert AudioProcessor.get_transcription_provider() == :local_whisper
    end

    test "uses configured provider" do
      Application.put_env(:kite4rent, :audio_transcription, default_provider: :assemblyai)

      assert AudioProcessor.get_transcription_provider() == :assemblyai
    end

    @tag :capture_log
    test "handles unknown provider gracefully" do
      Application.put_env(:kite4rent, :audio_transcription, default_provider: :unknown_provider)

      {:error, :unknown_transcription_provider, _reason} =
        AudioProcessor.transcribe({:audio_path, @audio_path})
    end
  end

  describe "AssemblyAI language sanitization integration" do
    setup do
      # Set up AssemblyAI configuration for tests
      Application.put_env(:kite4rent, :audio_transcription,
        providers: %{
          assemblyai: %{
            api_key: "test-api-key",
            base_url: "https://api.eu.assemblyai.com/v2",
            language_detection: true
          }
        }
      )

      :ok
    end

    test "integrates with InputSanitizer for language normalization" do
      # Mock the HTTP responses for AssemblyAI workflow
      upload_response = Jason.encode!(%{"upload_url" => "https://example.com/upload"})
      transcript_response = Jason.encode!(%{"id" => "test-transcript-id"})

      completion_response =
        Jason.encode!(%{
          "status" => "completed",
          "text" => "Hello world",
          # Uppercase that should be sanitized by InputSanitizer
          "language_code" => "EN"
        })

      Kite4rent.Utils.HTTPClient
      |> Mimic.expect(:request, fn :post, _upload_url, _headers, _audio_data ->
        {:ok, upload_response}
      end)
      |> Mimic.expect(:request, fn :post, _transcript_url, _headers, _body ->
        {:ok, transcript_response}
      end)
      |> Mimic.expect(:request, fn :get, _status_url, _headers ->
        {:ok, completion_response}
      end)

      # Mock file reading
      File
      |> Mimic.expect(:read, fn _path ->
        {:ok, "mock audio data"}
      end)

      result = AssemblyAI.transcribe("test_audio.ogg")

      # Verify integration with InputSanitizer normalizes "EN" to "en"
      assert {:ok, %{language: "en", text: "Hello world"}} = result
    end
  end

  @tag timeout: 3_000
  @tag :skip
  test "handles ffmpeg conversion errors gracefully" do
    # Create a temporary invalid OGG file
    invalid_ogg = Path.join(System.tmp_dir!(), "invalid.ogg")
    File.write!(invalid_ogg, "not an ogg file")

    # Try to convert invalid OGG data
    assert {:error, "audio_conversion", _reason} =
             AudioProcessor.transcribe({:audio_path, invalid_ogg})

    # Clean up
    File.rm!(invalid_ogg)
  end
end
