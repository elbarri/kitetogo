defmodule Kite4rent.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Setup rules engine before starting children
    Kite4rent.RulesEngine.setup()

    # Add Axiom logging backend if configured
    setup_axiom_logging()

    children =
      [
        Kite4rentWeb.Telemetry,
        Kite4rent.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:kite4rent, :ecto_repos), skip: skip_migrations?()},
        # DNSCluster removed — not needed for single-server Coolify deployment
        # {DNSCluster, query: Application.get_env(:kite4rent, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Kite4rent.PubSub},
        # Start the Finch HTTP client for sending emails and API requests
        {Finch, name: Kite4rent.Finch},
        # Start the geocoding cache
        {Cachex, name: :geocoding_cache},
        # Start the Nominatim rate limiter (1 req/sec limit)
        Kite4rent.NominatimRateLimiter,
        # Clean up expired conversation flows hourly
        Kite4rent.Conversation.FlowCleanupWorker,
      ] ++ maybe_expiration_worker() ++ [
        # Start to serve requests, typically the last entry
        Kite4rentWeb.Endpoint
      ] ++ dev_only_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Kite4rent.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Kite4rentWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # Run migrations at startup in all environments (including releases).
    # This replaces the pre-deployment command which was unreliable on Coolify.
    System.get_env("SKIP_MIGRATIONS") == "true"
  end

  # Start the deposit expiration worker only if enabled in config
  defp maybe_expiration_worker do
    if Application.get_env(:kite4rent, :deposit_expiration_worker)[:enabled] do
      [Kite4rent.Deposits.ExpirationWorker]
    else
      require Logger
      Logger.warning("Deposit expiration worker is DISABLED - expired deposits will NOT be automatically released")
      []
    end
  end

  # Start StripeListener only in dev to auto-run `stripe listen`
  # NOTE: Disabled because we're using Stripe Dashboard webhooks via ngrok
  defp dev_only_children do
    # if Application.get_env(:kite4rent, :dev_routes) do
    #   [Kite4rent.StripeListener]
    # else
    #   []
    # end
    []
  end

  # Setup Axiom logging backend if configured
  defp setup_axiom_logging do
    axiom_token = System.get_env("AXIOM_API_TOKEN")
    axiom_dataset = System.get_env("AXIOM_DATASET")

    # Only enable Axiom in production (when PHX_SERVER is set, which Fly.io does)
    is_production = System.get_env("PHX_SERVER") == "true"

    if axiom_token && axiom_dataset && is_production do
      require Logger
      Logger.info("Adding Axiom logging backend...")

      case Logger.add_backend(Kite4rent.AxiomLoggerBackend) do
        {:ok, _} ->
          Logger.info("Axiom logging backend added successfully")
        {:error, reason} ->
          Logger.warning("Failed to add Axiom logging backend: #{inspect(reason)}")
      end
    end
  end
end
