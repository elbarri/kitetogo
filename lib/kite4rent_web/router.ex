defmodule Kite4rentWeb.Router do
  use Kite4rentWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Kite4rentWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Pipeline for WhatsApp webhook - filters logging for status updates
  pipeline :whatsapp_webhook do
    plug :accepts, ["json"]
    plug Kite4rentWeb.Plugs.WebhookLogFilter
  end

  pipeline :stripe_webhook do
    plug Kite4rentWeb.Plugs.StripeWebhookPlug
  end

  # Health check — verifies DB connectivity
  scope "/api", Kite4rentWeb do
    pipe_through :api
    get "/health", HealthController, :index, log: false
  end

  # WhatsApp webhook - logging handled by custom plug
  scope "/api", Kite4rentWeb do
    pipe_through :whatsapp_webhook

    get "/whatsapp/webhook", WhatsappController, :verify, log: false
    post "/whatsapp/webhook", WhatsappController, :webhook, log: false
  end

  # Other API routes
  scope "/api", Kite4rentWeb do
    pipe_through :api

    # Stripe webhook - ensure this uses the webhook plug
    post "/stripe/webhook", StripeWebhookController, :handle_webhook
  end

  # Payment routes
  scope "/", Kite4rentWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/success", PageController, :success
    get "/cancel", PageController, :cancel
    get "/privacy-policy", PageController, :privacy_policy
    get "/terms-of-service", PageController, :terms_of_service
    get "/faq", PageController, :faq
    get "/llms.txt", PageController, :llms_txt
    get "/llms-full.txt", PageController, :llms_full_txt

    # Contact access checkout
    get "/checkout-session/new", CheckoutSessionController, :new

    # Security deposit checkout
    get "/deposit-checkout/:id", DepositCheckoutController, :show
    post "/deposit-checkout/:id", DepositCheckoutController, :create
    get "/deposit-checkout/:id/success", DepositCheckoutController, :success
    get "/deposit-checkout/:id/cancel", DepositCheckoutController, :cancel

    # Rental agreements (accessed via UUID for security)
    # Uses LiveView for real-time photo updates
    live "/agreement/:uuid", AgreementLive
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:kite4rent, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: Kite4rentWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
