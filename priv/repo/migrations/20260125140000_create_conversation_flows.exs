defmodule Kite4rent.Repo.Migrations.CreateConversationFlows do
  use Ecto.Migration

  def change do
    create table(:conversation_flows) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :flow_type, :string, null: false
      add :flow_step, :string, null: false
      add :collected_data, :map, default: %{}
      add :llm_response, :map
      add :missing_fields, {:array, :string}, default: []
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:conversation_flows, [:user_id])
    create index(:conversation_flows, [:expires_at])
  end
end
