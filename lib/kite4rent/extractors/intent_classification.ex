defmodule Kite4rent.Extractors.IntentClassification do
  use Ecto.Schema
  use InstructorLite.Instruction

  @notes """
  Classification result for a WhatsApp message in a kitesurfing gear rental marketplace.
  - intent: The user's resolved action intent
  - intent_confidence: Confidence score from 0.0 to 1.0
  - doubt_asked_likelihood: How likely the user is asking a question/doubt rather than making a direct request (0.0 = direct request, 1.0 = clearly asking/wondering)
  - language: 2-letter ISO language code (e.g. "es", "en")
  - location: Specific location name if mentioned or resolved from context, null otherwise
  - is_school: true if the user identifies as a kite school or surf school in the message, false otherwise
  """

  @supported_intents ~w(offer_gear request_gear list_own_inventory edit_gear request_security_deposit check_availability feedback other)

  @primary_key false
  embedded_schema do
    field :intent, :string
    field :intent_confidence, :float
    field :doubt_asked_likelihood, :float
    field :language, :string
    field :location, :string
    field :is_school, :boolean
  end

  @impl true
  def validate_changeset(changeset, _opts) do
    changeset
    |> Ecto.Changeset.validate_required([:intent, :intent_confidence, :doubt_asked_likelihood, :language])
    |> Ecto.Changeset.validate_inclusion(:intent, @supported_intents)
    |> Ecto.Changeset.validate_number(:intent_confidence,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> Ecto.Changeset.validate_number(:doubt_asked_likelihood,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> Ecto.Changeset.validate_length(:language, is: 2)
    |> normalize_language()
  end

  defp normalize_language(changeset) do
    case Ecto.Changeset.get_change(changeset, :language) do
      nil -> changeset
      lang -> Ecto.Changeset.put_change(changeset, :language, String.downcase(String.slice(lang, 0, 2)))
    end
  end

  def supported_intents, do: @supported_intents
end
