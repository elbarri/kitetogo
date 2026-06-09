# Audio Transcription Demo
#
# This script demonstrates how to use the configurable audio transcription system
# with both local Whisper and AssemblyAI providers.
#
# Usage:
#   mix run examples/audio_transcription_demo.exs

# Configure for local whisper
Application.put_env(:kite4rent, :audio_transcription,
  default_provider: :local_whisper,
  providers: %{
    local_whisper: %{
      base_dir: System.get_env("WHISPER_BASE_DIR", "/path/to/whisper.cpp"),
      whisper_cli: System.get_env("WHISPER_CPP_CLI", "build/bin/whisper-cli"),
      models: [medium: "models/ggml-medium.bin"]
    },
    assemblyai: %{
      api_key: System.get_env("ASSEMBLYAI_API_KEY"),
      base_url: "https://api.eu.assemblyai.com/v2",
      language_detection: true,
      audio_intel: false
    }
  }
)

IO.puts("=== Audio Transcription Configuration Demo ===")
IO.puts("")

# Test local whisper configuration
IO.puts("Current provider: #{Kite4rent.AudioProcessor.get_transcription_provider()}")
IO.puts("")

IO.puts("Available providers:")
config = Application.get_env(:kite4rent, :audio_transcription)
config[:providers]
|> Map.keys()
|> Enum.each(fn provider -> IO.puts("  - #{provider}") end)

IO.puts("")

# Switch to AssemblyAI
IO.puts("Switching to AssemblyAI...")
Application.put_env(:kite4rent, :audio_transcription,
  Keyword.put(config, :default_provider, :assemblyai)
)

IO.puts("Current provider: #{Kite4rent.AudioProcessor.get_transcription_provider()}")
IO.puts("")

# Test audio file path (using the test file if it exists)
audio_test_file = "priv/media/whatsapp/77616d69642e4842_1745137192.ogg"

if File.exists?(audio_test_file) do
  IO.puts("Test audio file found: #{audio_test_file}")
  IO.puts("File size: #{File.stat!(audio_test_file).size} bytes")
  IO.puts("")
  IO.puts("To test transcription (with valid API key):")
  IO.puts("  Kite4rent.AudioProcessor.transcribe({:audio_path, \"#{audio_test_file}\"})")
else
  IO.puts("Test audio file not found at: #{audio_test_file}")
  IO.puts("Create an audio file there to test transcription.")
end

IO.puts("")
IO.puts("=== Configuration Summary ===")
IO.puts("Local Whisper:")
IO.puts("  Base directory: #{config[:providers][:local_whisper][:base_dir]}")
IO.puts("  CLI path: #{config[:providers][:local_whisper][:whisper_cli]}")
IO.puts("")
IO.puts("AssemblyAI:")
IO.puts("  Base URL: #{config[:providers][:assemblyai][:base_url]}")
IO.puts("  API Key configured: #{if config[:providers][:assemblyai][:api_key], do: "Yes", else: "No (set ASSEMBLYAI_API_KEY env var)"}")
IO.puts("  Language detection: #{config[:providers][:assemblyai][:language_detection]}")
IO.puts("")
IO.puts("Production environment will use AssemblyAI by default.")
IO.puts("Development environment uses local Whisper by default.")
IO.puts("")
IO.puts("Demo completed!")
