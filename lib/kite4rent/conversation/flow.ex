defmodule Kite4rent.Conversation.Flow do
  @moduledoc """
  Ecto schema for persisting conversation flow state.

  This allows conversation flows to survive application restarts,
  which is critical for multi-step interactions like gear offers
  that require location input.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @flow_expiry_hours 24
  @flow_expiry_minutes @flow_expiry_hours * 60

  schema "conversation_flows" do
    field :flow_type, :string
    field :flow_step, :string
    field :collected_data, :map, default: %{}
    field :llm_response, :map
    field :missing_fields, {:array, :string}, default: []
    field :expires_at, :utc_datetime

    belongs_to :user, Kite4rent.Users.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(flow, attrs) do
    flow
    |> cast(attrs, [:user_id, :flow_type, :flow_step, :collected_data, :llm_response, :missing_fields, :expires_at])
    |> validate_required([:user_id, :flow_type, :flow_step, :expires_at])
    |> unique_constraint(:user_id)
  end

  @doc """
  Creates a changeset for starting a new flow.
  """
  def start_changeset(attrs) do
    expires_at = DateTime.utc_now() |> DateTime.add(@flow_expiry_minutes, :minute)

    %__MODULE__{}
    |> cast(attrs, [:user_id, :flow_type, :flow_step, :collected_data, :llm_response, :missing_fields])
    |> put_change(:expires_at, DateTime.truncate(expires_at, :second))
    |> validate_required([:user_id, :flow_type, :flow_step])
    |> unique_constraint(:user_id)
  end

  @doc """
  Creates a changeset for updating an existing flow.
  """
  def update_changeset(flow, attrs) do
    # Refresh expiry on any update
    expires_at = DateTime.utc_now() |> DateTime.add(@flow_expiry_minutes, :minute)

    flow
    |> cast(attrs, [:flow_step, :collected_data, :missing_fields])
    |> put_change(:expires_at, DateTime.truncate(expires_at, :second))
  end
end
