defmodule Kite4rent.Conversation.Manager do
  @moduledoc """
  Manages conversation state for users with database persistence.

  This replaces the previous in-memory GenServer implementation to ensure
  conversation flows survive application restarts.

  Flow state is stored in the conversation_flows table and automatically
  expires after 1 hour of inactivity.
  """

  require Logger

  alias Kite4rent.Conversation.Flow
  alias Kite4rent.Conversation.State
  alias Kite4rent.Repo

  import Ecto.Query

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Gets the current conversation state for a user.

  Returns a State struct for compatibility with existing code.
  If no active flow exists, returns a new empty state.
  """
  def get_state(user_id) do
    case get_active_flow(user_id) do
      nil ->
        {:ok, State.new(user_id)}

      flow ->
        {:ok, flow_to_state(flow)}
    end
  end

  @doc """
  Starts a new flow for collecting data.

  Options:
  - :initial_data - Map of already collected data
  - :missing_fields - List of fields that still need to be collected
  - :llm_response - The original LLM response to preserve context
  """
  def start_flow(user_id, flow_type, step, opts \\ []) do
    # Delete any existing flow for this user first
    delete_flow(user_id)

    attrs = %{
      user_id: user_id,
      flow_type: to_string(flow_type),
      flow_step: encode_step(step),
      collected_data: Keyword.get(opts, :initial_data, %{}),
      missing_fields: encode_missing_fields(Keyword.get(opts, :missing_fields, [])),
      llm_response: Keyword.get(opts, :llm_response)
    }

    case Flow.start_changeset(attrs) |> Repo.insert() do
      {:ok, flow} ->
        Logger.info("User #{user_id}: Started flow #{flow_type}, step: #{inspect(step)}")
        {:ok, flow_to_state(flow)}

      {:error, changeset} ->
        Logger.error("Failed to start flow for user #{user_id}: #{inspect(changeset.errors)}")
        {:error, :failed_to_start_flow}
    end
  end

  @doc """
  Adds data to the collected_data map for the current flow.
  """
  def add_data(user_id, data) when is_map(data) do
    case get_active_flow(user_id) do
      nil ->
        {:error, :no_active_flow}

      flow ->
        updated_data = Map.merge(flow.collected_data || %{}, data)

        case flow
             |> Flow.update_changeset(%{collected_data: updated_data})
             |> Repo.update() do
          {:ok, updated_flow} ->
            {:ok, flow_to_state(updated_flow)}

          {:error, _changeset} ->
            {:error, :failed_to_update_flow}
        end
    end
  end

  @doc """
  Updates the current flow step.
  """
  def update_step(user_id, step) do
    case get_active_flow(user_id) do
      nil ->
        {:error, :no_active_flow}

      flow ->
        case flow
             |> Flow.update_changeset(%{flow_step: encode_step(step)})
             |> Repo.update() do
          {:ok, updated_flow} ->
            Logger.debug("User #{user_id}: Updated step to #{inspect(step)}")
            {:ok, flow_to_state(updated_flow)}

          {:error, _changeset} ->
            {:error, :failed_to_update_flow}
        end
    end
  end

  @doc """
  Replaces the missing_fields list for the current flow.
  """
  def update_missing_fields(user_id, fields) when is_list(fields) do
    case get_active_flow(user_id) do
      nil ->
        {:error, :no_active_flow}

      flow ->
        case flow
             |> Flow.update_changeset(%{missing_fields: encode_missing_fields(fields)})
             |> Repo.update() do
          {:ok, updated_flow} ->
            {:ok, flow_to_state(updated_flow)}

          {:error, _changeset} ->
            {:error, :failed_to_update_flow}
        end
    end
  end

  @doc """
  Marks a field as collected and removes it from missing_fields.
  """
  def mark_field_collected(user_id, field) do
    case get_active_flow(user_id) do
      nil ->
        {:error, :no_active_flow}

      flow ->
        updated_fields = List.delete(flow.missing_fields || [], to_string(field))

        case flow
             |> Flow.update_changeset(%{missing_fields: updated_fields})
             |> Repo.update() do
          {:ok, updated_flow} ->
            {:ok, flow_to_state(updated_flow)}

          {:error, _changeset} ->
            {:error, :failed_to_update_flow}
        end
    end
  end

  @doc """
  Clears the current flow, resetting to idle state.
  """
  def clear_flow(user_id) do
    delete_flow(user_id)
    Logger.debug("User #{user_id}: Cleared flow")
    {:ok, State.new(user_id)}
  end

  @doc """
  Checks if the user has an active flow.
  """
  def has_active_flow?(user_id) do
    {:ok, get_active_flow(user_id) != nil}
  end

  @doc """
  Cleans up expired flows from the database.
  Called periodically by a background job.
  """
  def cleanup_expired_flows do
    now = DateTime.utc_now()

    {count, _} =
      from(f in Flow, where: f.expires_at < ^now)
      |> Repo.delete_all()

    if count > 0 do
      Logger.info("Cleaned up #{count} expired conversation flows")
    end

    {:ok, count}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_active_flow(nil), do: nil

  defp get_active_flow(user_id) do
    now = DateTime.utc_now()

    from(f in Flow,
      where: f.user_id == ^user_id and f.expires_at > ^now
    )
    |> Repo.one()
  end

  defp delete_flow(nil), do: {0, nil}

  defp delete_flow(user_id) do
    from(f in Flow, where: f.user_id == ^user_id)
    |> Repo.delete_all()
  end

  defp flow_to_state(%Flow{} = flow) do
    %State{
      user_id: flow.user_id,
      current_flow: decode_flow_type(flow.flow_type),
      flow_step: decode_step(flow.flow_step),
      collected_data: flow.collected_data || %{},
      missing_fields: decode_missing_fields(flow.missing_fields || []),
      llm_response: flow.llm_response,
      last_activity: flow.updated_at
    }
  end

  # Encode step tuple to string for storage
  defp encode_step({:awaiting, field}) when is_atom(field) do
    "awaiting:#{field}"
  end

  defp encode_step(step) when is_atom(step) do
    to_string(step)
  end

  defp encode_step(step) do
    inspect(step)
  end

  # Decode step string back to tuple/atom
  defp decode_step("awaiting:" <> field) do
    {:awaiting, safe_string_to_atom(field)}
  end

  defp decode_step(step) when is_binary(step) do
    safe_string_to_atom(step)
  end

  defp decode_flow_type(nil), do: nil

  defp decode_flow_type(type) when is_binary(type) do
    safe_string_to_atom(type)
  end

  defp encode_missing_fields(fields) do
    Enum.map(fields, &to_string/1)
  end

  defp decode_missing_fields(fields) do
    Enum.map(fields, &safe_string_to_atom/1)
  end

  defp safe_string_to_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> String.to_atom(str)
  end
end
