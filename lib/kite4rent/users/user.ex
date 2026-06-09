defmodule Kite4rent.Users.User do
  use Ecto.Schema
  import Ecto.Changeset
  alias Kite4rent.InputSanitizer

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          email: String.t() | nil,
          whatsapp: String.t() | nil,
          language: String.t() | nil,
          location_name: String.t() | nil,
          location_point: Geo.PostGIS.Geometry.t() | nil,
          country_code: String.t() | nil,
          contact_sharing_consent: boolean() | nil,
          contact_sharing_consent_at: DateTime.t() | nil,
          stripe_customer_id: String.t() | nil,
          currency: String.t() | nil,
          last_used_fullname: String.t() | nil,
          last_used_email: String.t() | nil,
          is_school: boolean(),
          is_renting_full_gear: boolean(),
          kite_gear: [Kite4rent.Rental.Gear.t()] | nil,
          payments: [Kite4rent.Payments.Payment.t()] | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "users" do
    field :name, :string
    field :email, :string
    field :whatsapp, :string
    field :language, :string

    # Location fields
    field :location_name, :string
    field :location_point, Geo.PostGIS.Geometry
    field :country_code, :string

    # Contact sharing consent fields
    field :contact_sharing_consent, :boolean, default: false
    field :contact_sharing_consent_at, :utc_datetime

    # Stripe integration
    field :stripe_customer_id, :string
    field :currency, :string, default: "USD"

    # Last used full name and email from rental agreements
    field :last_used_fullname, :string
    field :last_used_email, :string

    # School and renting flags
    field :is_school, :boolean, default: false
    field :is_renting_full_gear, :boolean, default: false

    has_many :kite_gear, Kite4rent.Rental.Gear
    has_many :payments, Kite4rent.Payments.Payment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :name,
      :email,
      :whatsapp,
      :language,
      :location_name,
      :location_point,
      :country_code,
      :contact_sharing_consent,
      :contact_sharing_consent_at,
      :stripe_customer_id,
      :currency,
      :last_used_fullname,
      :last_used_email,
      :is_school,
      :is_renting_full_gear
    ])
    |> sanitize_language()
    |> sanitize_country_code()
    |> sanitize_currency()
    |> validate_required([:name])
    |> validate_length(:language, is: 2)
    |> validate_format(:language, ~r/^[a-z]{2}$/,
      message: "must be a 2-letter ISO 639 language code"
    )
    |> validate_length(:country_code, is: 2)
    |> validate_format(:country_code, ~r/^[A-Z]{2}$/,
      message: "must be a 2-letter ISO 3166 country code"
    )
    |> validate_length(:currency, is: 3)
    |> validate_format(:currency, ~r/^[A-Z]{3}$/,
      message: "must be a 3-letter ISO 4217 currency code"
    )
    |> validate_at_least_one_contact()
    |> cast_assoc(:kite_gear)
  end

  @doc """
  Gets the user's language, falling back to default language if not set
  """
  def get_language(%__MODULE__{language: language}) when is_binary(language), do: language
  def get_language(_user), do: "en"

  @doc """
  Sanitizes language field using centralized InputSanitizer.
  """
  def sanitize_language(changeset) do
    case get_field(changeset, :language) do
      nil -> changeset
      language ->
        sanitized = InputSanitizer.sanitize_language(language)
        put_change(changeset, :language, sanitized)
    end
  end

  @doc """
  Sanitizes country_code field using centralized InputSanitizer.
  """
  def sanitize_country_code(changeset) do
    case get_field(changeset, :country_code) do
      nil -> changeset
      country_code ->
        sanitized = InputSanitizer.sanitize_country_code(country_code)
        put_change(changeset, :country_code, sanitized)
    end
  end

  @doc """
  Sanitizes currency field by uppercasing and trimming.
  """
  def sanitize_currency(changeset) do
    case get_field(changeset, :currency) do
      nil -> changeset
      currency when is_binary(currency) ->
        sanitized = currency |> String.trim() |> String.upcase()
        put_change(changeset, :currency, sanitized)
      _ -> changeset
    end
  end

  defp validate_at_least_one_contact(changeset) do
    if get_field(changeset, :email) || get_field(changeset, :whatsapp) do
      changeset
    else
      add_error(
        changeset,
        :base,
        "At least one contact method (email or whatsapp) must be provided"
      )
    end
  end
end
