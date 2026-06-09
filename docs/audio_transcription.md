# Audio Transcription System

The Kite4Rent application supports configurable audio transcription with two providers:

1. **Local Whisper** - Uses Whisper C++ implementation locally
2. **AssemblyAI** - Uses AssemblyAI's European endpoint for cloud-based transcription

## Configuration

### Environment Variables

- `ASSEMBLYAI_API_KEY` - API key for AssemblyAI service
- `WHISPER_BASE_DIR` - Base directory for local Whisper installation (default: `/path/to/whisper.cpp`)
- `WHISPER_CPP_CLI` - Path to Whisper CLI relative to base dir (default: `build/bin/whisper-cli`)

### Provider Configuration

The system is configured in `config/config.exs`:

```elixir
config :kite4rent, :audio_transcription,
  default_provider: :local_whisper,  # or :assemblyai
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
```

### Environment-Specific Defaults

- **Development**: Uses `local_whisper` by default
- **Production**: Uses `assemblyai` by default (configured in `config/prod.exs`)

## Usage

### Basic Usage

```elixir
# Transcribe an audio file using the configured provider
{:ok, %{text: text, language: language}} = 
  Kite4rent.AudioProcessor.transcribe({:audio_path, "path/to/audio.ogg"})
```

### Provider-Specific Usage

```elixir
# Use local Whisper directly
{:ok, result} = Kite4rent.AudioProcessor.LocalWhisper.transcribe("path/to/audio.ogg")

# Use AssemblyAI directly  
{:ok, result} = Kite4rent.AudioProcessor.AssemblyAI.transcribe("path/to/audio.ogg")
```

### Runtime Provider Switching

```elixir
# Check current provider
provider = Kite4rent.AudioProcessor.get_transcription_provider()

# Switch provider at runtime
Application.put_env(:kite4rent, :audio_transcription, 
  default_provider: :assemblyai)
```

## Provider Details

### Local Whisper

- **Pros**: No API costs, works offline, privacy-focused
- **Cons**: Requires local installation, slower processing, more CPU intensive
- **Requirements**: Whisper C++ installed and compiled locally

### AssemblyAI

- **Pros**: Fast processing, high accuracy, supports many languages
- **Cons**: Requires API key, costs per usage, requires internet connection
- **Features**: Uses European endpoint (`api.eu.assemblyai.com`) for EU data compliance

## Testing

### Running Tests

```bash
# Run all audio transcription tests (excluding integration)
mix test test/kite4rent/audio_processor_test.exs --exclude audio --exclude integration

# Run with mocked AssemblyAI calls
mix test test/kite4rent/audio_processor_test.exs --only mock
```

### Demo Script

Run the demo to see provider switching in action:

```bash
mix run examples/audio_transcription_demo.exs
```

## Error Handling

The system gracefully handles errors from both providers:

- **File read errors**: Invalid or missing audio files
- **API errors**: Invalid API keys, network issues, service unavailable
- **Processing errors**: Transcription failures, timeout issues
- **Configuration errors**: Missing or invalid provider configuration

All errors are logged with context and return structured error tuples:

```elixir
{:error, :assemblyai_transcription_failed, reason}
{:error, :local_whisper_transcription_failed, reason}
{:error, :unknown_transcription_provider, reason}
```

## Production Setup

1. Set the `ASSEMBLYAI_API_KEY` environment variable
2. AssemblyAI will be used automatically in production
3. Monitor transcription costs through AssemblyAI dashboard
4. Set up error monitoring for transcription failures

## Development Setup

1. Install Whisper C++ locally (optional)
2. Set `WHISPER_BASE_DIR` and `WHISPER_CPP_CLI` if needed
3. Local Whisper will be used by default in development
4. AssemblyAI can be tested with a valid API key 