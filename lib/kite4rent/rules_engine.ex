defmodule Kite4rent.RulesEngine do
  @moduledoc """
  Manages the Wongi rules engine with rules stored in persistent_term.
  Rules are loaded once at application startup for maximum performance.

  The engine is immutable, so each request uses the base engine and asserts
  facts, which returns a new engine instance with those facts.

  To change rules, restart the application.
  """
  alias Wongi.Engine
  require Logger

  @engine_key {__MODULE__, :base_engine}

  @doc """
  Initialize rules at application startup.
  Stores the engine with all rules loaded in persistent_term.
  """
  def setup do
    Logger.info("Setting up Rules Engine...")

    # Each load operation returns a NEW engine with rules added
    engine =
      Engine.new()
      |> Kite4rent.Rules.ConversationRules.load()

    # Store the final engine in persistent_term for fast, immutable access
    :persistent_term.put(@engine_key, engine)

    Logger.info("Rules Engine initialized")
    :ok
  end

  @doc """
  Get the base engine with all rules loaded.
  Returns the immutable engine from persistent_term.
  """
  def get_engine do
    :persistent_term.get(@engine_key)
  end

  if Mix.env() == :dev do
    @doc """
    Hot reload rules in development only.
    WARNING: This is for development convenience. In production, restart the app.
    """
    def reload! do
      Logger.warning("Hot reloading rules (dev only)...")
      setup()
      Logger.info("Rules reloaded")
      :ok
    end
  end
end
