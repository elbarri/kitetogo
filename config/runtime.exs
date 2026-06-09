import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/kite4rent start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :kite4rent, Kite4rentWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # DATABASE_SSL=true   → strict SSL with cert verification (Neon/remote DBs)
  # DATABASE_SSL=require → SSL without cert verification (local self-signed certs)
  # unset/false         → no SSL (plain local Postgres)
  ssl_opts =
    case System.get_env("DATABASE_SSL") do
      val when val in ~w(true 1) ->
        [
          verify: :verify_peer,
          cacertfile: "/etc/ssl/certs/ca-certificates.crt",
          server_name_indication: String.to_charlist(URI.parse(database_url).host),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
      "require" ->
        [verify: :verify_none]
      _ ->
        false
    end

  config :kite4rent, Kite4rent.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2"),
    socket_options: maybe_ipv6,
    types: Kite4rent.PostgresTypes,
    ssl: ssl_opts

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  # Treat empty string same as nil — empty string is truthy in Elixir so
  # "" || :ignore would produce "" instead of :ignore, causing DNSCluster to crash.
  dns_cluster_query =
    case System.get_env("DNS_CLUSTER_QUERY") do
      val when val in [nil, ""] -> nil
      val -> val
    end

  config :kite4rent, :dns_cluster_query, dns_cluster_query

  config :kite4rent, Kite4rentWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # Configure base URL for external links (payment URLs, etc.)
  # Can be overridden with BASE_URL environment variable
  base_url = System.get_env("BASE_URL") || "https://#{host}"
  config :kite4rent, :base_url, base_url

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :kite4rent, Kite4rentWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :kite4rent, Kite4rentWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :kite4rent, Kite4rent.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.

  # Configure Axiom logging
  axiom_api_token = System.get_env("AXIOM_API_TOKEN")
  axiom_dataset = System.get_env("AXIOM_DATASET")
  axiom_http_dataset = System.get_env("AXIOM_DATASET_HTTP")
  axiom_org_id = System.get_env("AXIOM_ORG_ID")

  if axiom_api_token && axiom_dataset do
    config :logger, Kite4rent.AxiomLoggerBackend,
      url: "https://api.axiom.co",
      api_token: axiom_api_token,
      dataset: axiom_dataset,
      http_dataset: axiom_http_dataset,
      org_id: axiom_org_id,
      level: :info,
      metadata: :all,
      buffer_size: 50,
      flush_interval: 5_000
  end
end

# WhatsApp API Configuration
config :kite4rent,
  whatsapp_phone_id: System.get_env("WHATSAPP_PHONE_ID"),
  whatsapp_business_account_id: System.get_env("WHATSAPP_BUSINESS_ACCOUNT_ID"),
  whatsapp_access_token: System.get_env("WHATSAPP_ACCESS_TOKEN"),
  whatsapp_verify_token: System.get_env("WHATSAPP_VERIFY_TOKEN"),
  kitetogo_whatsapp: System.get_env("KITETOGO_WHATSAPP")

# LLM Provider Configuration
config :kite4rent,
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  openrouter_api_key: System.get_env("OPENROUTER_API_KEY"),
  gemini_api_key: System.get_env("GEMINI_API_KEY"),
  mistral_api_key: System.get_env("MISTRAL_API_KEY"),
  huggingface_api_key: System.get_env("HUGGINGFACE_API_KEY"),
  groq_api_key: System.get_env("GROQ_API_KEY"),
  together_api_key: System.get_env("TOGETHER_API_KEY"),
  cerebras_api_key: System.get_env("CEREBRAS_API_KEY")

# Translation Configuration
config :kite4rent, :translation,
  default_provider: System.get_env("TRANSLATION_PROVIDER", "google"),
  google: [
    api_key: System.get_env("GOOGLE_TRANSLATE_API_KEY"),
    project_id: System.get_env("GOOGLE_CLOUD_PROJECT_ID")
  ],
  deepl: [
    api_key: System.get_env("DEEPL_API_KEY")
  ]

# Admin phone for internal notifications (overridable via env)
config :kite4rent, :admin_phone, System.get_env("ADMIN_WHATSAPP")

config :stripity_stripe, api_key: System.get_env("STRIPE_API_KEY")
