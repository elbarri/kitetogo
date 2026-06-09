defmodule Kite4rent.Extractors.LocationExtraction do
  use Ecto.Schema
  use InstructorLite.Instruction

  @notes """
  Location extraction result for a kitesurfing gear rental marketplace message.
  - location: Specific place name (city, beach, spot), or null if none found or too vague
  - confidence: Confidence score from 0.0 to 1.0 (higher for well-known kiting spots)
  """

  @primary_key false
  embedded_schema do
    field :location, :string
    field :confidence, :float
  end

  @impl true
  def validate_changeset(changeset, _opts) do
    changeset
    |> Ecto.Changeset.validate_required([:confidence])
    |> Ecto.Changeset.validate_number(:confidence,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> validate_location_consistency()
  end

  defp validate_location_consistency(changeset) do
    location = Ecto.Changeset.get_field(changeset, :location)
    confidence = Ecto.Changeset.get_field(changeset, :confidence)

    cond do
      is_nil(location) and is_number(confidence) and confidence > 0.3 ->
        Ecto.Changeset.add_error(changeset, :confidence, "must be <= 0.3 when location is null")

      not is_nil(location) and is_binary(location) and String.trim(location) == "" ->
        Ecto.Changeset.put_change(changeset, :location, nil)

      true ->
        changeset
    end
  end
end
