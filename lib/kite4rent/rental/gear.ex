defmodule Kite4rent.Rental.Gear do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          size: String.t() | nil,
          type: String.t() | nil,
          year: String.t() | nil,
          model: String.t() | nil,
          brand: String.t() | nil,
          gender: String.t() | nil,
          condition: String.t() | nil,
          additional_details: String.t() | nil,
          value: integer() | nil,
          user_id: integer() | nil,
          user: Kite4rent.Users.User.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "kite_gear" do
    field :size, :string
    field :type, :string
    field :year, :string
    field :model, :string
    field :brand, :string
    field :gender, :string
    field :condition, :string
    field :additional_details, :string
    field :value, :integer, default: 0

    belongs_to :user, Kite4rent.Users.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(gear, attrs) do
    gear
    |> cast(attrs, [
      :type,
      :model,
      :brand,
      :year,
      :size,
      :gender,
      :condition,
      :additional_details,
      :value,
      :user_id
    ])
    |> capitalize_field(:brand)
    |> capitalize_field(:model)
    |> validate_required([:type, :brand, :user_id])
    |> validate_required_fields_for_kite_and_board()
    |> validate_required_fields_for_harness_and_wetsuit()
    |> validate_kite_size()
    |> validate_gender()
    |> validate_number(:value, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
  end

  # Validates that kites and boards have all required fields: brand, model, size, year
  defp validate_required_fields_for_kite_and_board(%Ecto.Changeset{} = changeset) do
    type = get_field(changeset, :type)

    if type in ["kite", "board"] do
      changeset
      |> validate_required([:model, :size, :year], message: "is required for #{type}s")
    else
      changeset
    end
  end

  # Validates that when type is "kite", size should be a number (integer or with one decimal)
  defp validate_kite_size(%Ecto.Changeset{} = changeset) do
    type = get_field(changeset, :type)
    size = get_field(changeset, :size)

    if type == "kite" and is_binary(size) and size != "" do
      case extract_and_validate_kite_size(size) do
        {:ok, _extracted_number} ->
          changeset

        {:error, _reason} ->
          add_error(
            changeset,
            :size,
            "must contain a valid number (integer or with one decimal) when type is kite"
          )
      end
    else
      changeset
    end
  end

  # Extracts and validates the numeric part from a kite size string
  defp extract_and_validate_kite_size(size) do
    cond do
      # Reject board-style sizes (e.g., "139x42")
      Regex.match?(~r/\d+\s*[xX]\s*\d+/, size) ->
        {:error, :board_style_format}

      # Reject if it contains a number with more than one decimal place
      Regex.match?(~r/\d+\.\d\d/, size) ->
        {:error, :too_many_decimal_places}

      true ->
        case Regex.run(~r/(\d+(?:\.\d)?)/, size) do
          [_full_match, extracted_number] -> {:ok, extracted_number}
          nil -> {:error, :no_valid_number_found}
        end
    end
  end

  # Validates that harnesses and wetsuits have all required fields
  defp validate_required_fields_for_harness_and_wetsuit(%Ecto.Changeset{} = changeset) do
    type = get_field(changeset, :type)

    cond do
      type == "harness" ->
        changeset
        |> validate_required([:size, :gender], message: "is required for harnesss")

      type == "wetsuit" ->
        changeset
        |> validate_required([:size, :gender], message: "is required for wetsuits")

      true ->
        changeset
    end
  end

  # Validates that gender is either "F" or "M" when present
  defp validate_gender(%Ecto.Changeset{} = changeset) do
    gender = get_field(changeset, :gender)

    if gender != nil and gender != "" do
      validate_inclusion(changeset, :gender, ["F", "M"],
        message: "must be F (Female) or M (Male)"
      )
    else
      changeset
    end
  end

  # Capitalizes each word in a string field (e.g. "duotone" -> "Duotone", "team series" -> "Team Series")
  defp capitalize_field(%Ecto.Changeset{} = changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      value when is_binary(value) and value != "" ->
        capitalized =
          value
          |> String.split(~r/(\s+|-)/u, include_captures: true)
          |> Enum.map(fn
            " " <> _ = space -> space
            "-" -> "-"
            word -> String.capitalize(word)
          end)
          |> Enum.join()

        put_change(changeset, field, capitalized)
      _ -> changeset
    end
  end
end
