defmodule Kite4rent.Extractors.GearExtraction do
  use Ecto.Schema
  use InstructorLite.Instruction

  @notes """
  Gear extraction result for a kitesurfing gear rental marketplace message.
  - gear: List of gear items found in the message (can be empty)
  - extraction_confidence: Overall confidence in the extraction from 0.0 to 1.0
  - needs_clarification: Whether the user should be asked for more details
  - clarification_request: The user-facing question to ask when clarification is needed, or null
  - offers_full_gear: true if the user mentions offering complete/full kitesurfing gear for rent (e.g. "equipo completo", "full gear"), false otherwise
  """

  @primary_key false
  embedded_schema do
    embeds_many :gear, GearItem, primary_key: false do
      field :type, :string
      field :brand, :string
      field :model, :string
      field :size, :string
      field :year, :string
      field :gender, :string
      field :condition, :string
      field :additional_details, :string
    end

    field :extraction_confidence, :float
    field :needs_clarification, :boolean
    field :clarification_request, :string
    field :offers_full_gear, :boolean
  end

  @impl true
  def validate_changeset(changeset, _opts) do
    changeset
    |> Ecto.Changeset.validate_required([:extraction_confidence, :needs_clarification])
    |> Ecto.Changeset.validate_number(:extraction_confidence,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
  end
end
