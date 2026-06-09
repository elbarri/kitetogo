# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :kite4rent,
  ecto_repos: [Kite4rent.Repo],
  generators: [timestamp_type: :utc_datetime]

config :ex_cldr,
  default_backend: Kite4rent.Cldr

# Configures the endpoint
config :kite4rent, Kite4rentWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: Kite4rentWeb.ErrorHTML, json: Kite4rentWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Kite4rent.PubSub,
  live_view: [signing_salt: "EiuVgJY6"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :kite4rent, Kite4rent.Mailer, adapter: Swoosh.Adapters.Local

# Default LLM provider (can be: :openrouter, :gemini, :mistral, :huggingface, :groq, :together, :cerebras)
config :kite4rent, :default_llm_provider, :openrouter

# Fallback providers list (in order of preference)
# Set to empty list [] to disable fallback
config :kite4rent, :fallback_llm_providers, [:openrouter]

# LLM Providers Configuration
config :kite4rent, :llm_providers, %{
  openrouter: %{
    url: "https://openrouter.ai/api/v1/chat/completions",
    models: [
      "openai/gpt-5-mini",
      "openai/gpt-5-nano",
      "anthropic/claude-3.5-haiku:beta",
      "google/gemini-2.5-flash-lite",
      "google/gemini-2.5-flash",
      "mistralai/devstral-medium",
      "mistralai/devstral-small-2505:free",
      "qwen/qwen2.5-vl-32b-instruct",
      "deepseek/deepseek-r1-distill-llama-70b",
      "meta-llama/llama-3.3-70b-instruct:free",
      "qwen/qwen3-30b-a3b-instruct-2507",
      "qwen/qwen3-30b-a3b:free"
    ],
    default_model: "google/gemini-2.5-flash-lite"
  },
  gemini: %{
    url: "https://generativelanguage.googleapis.com/v1/models/gemini-2.5-flash:generateContent",
    models: ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash-lite"],
    default_model: "gemini-2.5-flash"
  },
  mistral: %{
    url: "https://api.mistral.ai/v1/chat/completions",
    models: ["mistral-small-latest", "mistral-7b-instruct", "codestral-latest"],
    default_model: "mistral-small-latest"
  },
  huggingface: %{
    url: "https://api-inference.huggingface.co/models",
    models: [
      "microsoft/DialoGPT-medium",
      "microsoft/CodeBERT-base",
      "Qwen/Qwen2.5-7B-Instruct",
      "microsoft/codebert-base-mlm"
    ],
    default_model: "Qwen/Qwen2.5-7B-Instruct"
  },
  groq: %{
    url: "https://api.groq.com/openai/v1/chat/completions",
    models: [
      "llama-3.3-70b-versatile",
      "llama-3.1-8b-instant",
      "mixtral-8x7b-32768",
      "gemma2-9b-it"
    ],
    default_model: "llama-3.1-8b-instant"
  },
  together: %{
    url: "https://api.together.xyz/v1/chat/completions",
    models: [
      "meta-llama/Llama-3.2-11B-Vision-Instruct-Turbo",
      "meta-llama/Llama-3.3-70B-Instruct-Turbo",
      "deepseek-ai/DeepSeek-R1-Distill-Llama-70B"
    ],
    default_model: "meta-llama/Llama-3.2-11B-Vision-Instruct-Turbo"
  },
  cerebras: %{
    url: "https://api.cerebras.ai/v1/chat/completions",
    models: [
      "llama3.1-8b",
      "llama3.3-70b",
      "qwen3-32b"
    ],
    default_model: "llama3.1-8b"
  }
}

# Audio transcription configuration
config :kite4rent, :audio_transcription,
  default_provider: :assemblyai,
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

config :kite4rent, :whisper,
  base_dir: System.get_env("WHISPER_BASE_DIR", "/path/to/whisper.cpp"),
  whisper_cli: System.get_env("WHISPER_CPP_CLI", "build/bin/whisper-cli"),
  models: [medium: "models/ggml-medium.bin"]

config :kite4rent, Kite4rent.Repo, log: false

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  kite4rent: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  kite4rent: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Geocoding configuration
config :kite4rent, :geocoding,
  provider: :nominatim,
  default_radius_km: 50

# Optional: Add API keys for paid services
config :kite4rent, :google_maps_api_key, System.get_env("GOOGLE_MAPS_API_KEY")
config :kite4rent, :mapbox_api_key, System.get_env("MAPBOX_API_KEY")

config :kite4rent, :display, users_with_gear_limit: 30

# Base URL configuration for external links (payment URLs, etc.)
# This will be overridden in runtime.exs for production
config :kite4rent, :base_url, "http://localhost:4000"

# Supported currencies for security deposits and gear valuations
config :kite4rent, :supported_currencies, ["EUR", "USD", "GBP"]

# Minimum intent confidence required to act on offer_gear / request_gear without clarifying.
# Below this threshold the message is treated as ambiguous and ChatHandler asks a question.
config :kite4rent, :intent_ambiguity_threshold, 0.75

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
