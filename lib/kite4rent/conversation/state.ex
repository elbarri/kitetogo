defmodule Kite4rent.Conversation.State do
  @moduledoc """
  Represents the conversation state for a user.

  This struct tracks multi-step flows like gear offers that require
  sequential data collection (e.g., asking for location, then gear details).

  State is persisted to the database via the conversation_flows table,
  ensuring flows survive application restarts (e.g., deployments).
  Flows automatically expire after 1 hour of inactivity.
  """

  @type flow_type :: :gear_offer | :gear_request | nil
  @type flow_step :: {:awaiting, atom()} | nil

  @type t :: %__MODULE__{
          user_id: integer(),
          current_flow: flow_type(),
          flow_step: flow_step(),
          collected_data: map(),
          missing_fields: [atom()],
          last_activity: DateTime.t() | nil,
          llm_response: map() | nil
        }

  defstruct [
    :user_id,
    current_flow: nil,
    flow_step: nil,
    collected_data: %{},
    missing_fields: [],
    last_activity: nil,
    llm_response: nil
  ]

  @doc """
  Creates a new conversation state for a user.
  """
  def new(user_id) when is_integer(user_id) do
    %__MODULE__{
      user_id: user_id,
      last_activity: DateTime.utc_now()
    }
  end

  @doc """
  Updates the last activity timestamp.
  """
  def touch(%__MODULE__{} = state) do
    %{state | last_activity: DateTime.utc_now()}
  end

  @doc """
  Starts a new flow for collecting data.
  """
  def start_flow(%__MODULE__{} = state, flow_type, step, opts \\ []) do
    %{state |
      current_flow: flow_type,
      flow_step: step,
      collected_data: Keyword.get(opts, :initial_data, %{}),
      missing_fields: Keyword.get(opts, :missing_fields, []),
      llm_response: Keyword.get(opts, :llm_response),
      last_activity: DateTime.utc_now()
    }
  end

  @doc """
  Adds data to the collected_data map.
  """
  def add_data(%__MODULE__{collected_data: existing} = state, new_data) when is_map(new_data) do
    %{state |
      collected_data: Map.merge(existing, new_data),
      last_activity: DateTime.utc_now()
    }
  end

  @doc """
  Updates the current flow step.
  """
  def update_step(%__MODULE__{} = state, step) do
    %{state |
      flow_step: step,
      last_activity: DateTime.utc_now()
    }
  end

  @doc """
  Removes a field from the missing_fields list.
  """
  def mark_field_collected(%__MODULE__{missing_fields: fields} = state, field) do
    %{state |
      missing_fields: List.delete(fields, field),
      last_activity: DateTime.utc_now()
    }
  end

  @doc """
  Clears the current flow, resetting to idle state.
  """
  def clear_flow(%__MODULE__{} = state) do
    %{state |
      current_flow: nil,
      flow_step: nil,
      collected_data: %{},
      missing_fields: [],
      llm_response: nil,
      last_activity: DateTime.utc_now()
    }
  end

  @doc """
  Checks if the state is stale (no activity for given duration).

  Default timeout is 1 hour.
  """
  def stale?(%__MODULE__{last_activity: nil}), do: true

  def stale?(%__MODULE__{last_activity: last_activity}, timeout_minutes \\ 60) do
    diff = DateTime.diff(DateTime.utc_now(), last_activity, :minute)
    diff >= timeout_minutes
  end

  @doc """
  Checks if there's an active flow.
  """
  def has_active_flow?(%__MODULE__{current_flow: nil}), do: false
  def has_active_flow?(%__MODULE__{current_flow: _}), do: true
end
