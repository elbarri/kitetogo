import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :kite4rent, Kite4rent.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "kite4rent_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  types: Kite4rent.PostgresTypes

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :kite4rent, Kite4rentWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "KOLxX1sRCksboJyZL5FvdfsU0OcNVG4c7wO2DqEx69A2Iay1NXhO3/QP9+nDftd5",
  server: false

# In test we don't send emails
config :kite4rent, Kite4rent.Mailer, adapter: Swoosh.Adapters.Test

# In test we don't integrate with llms. TODO: integration tests that do so
config :kite4rent, :llm_providers, %{
  my_mock_provider: %{
    url: "https://my-mock-provider.com/v1/chat/completions",
    models: ["my-mock-model"],
    default_model: "my-mock-model"
  },
  openrouter: %{
    url: "https://openrouter.ai/api/v1/chat/completions",
    models: [
      "qwen/qwen-2.5-7b-instruct:free",
      "google/gemma-3-27b-it:free"
    ],
    default_model: "qwen/qwen-2.5-7b-instruct:free"
  }
}

config :kite4rent, :display, users_with_gear_limit: 3

# Mock API keys for testing
config :kite4rent,
  openrouter_api_key: "test-openrouter-key"

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
