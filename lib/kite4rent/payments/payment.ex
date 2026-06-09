defmodule Kite4rent.Payments.Payment do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          amount: Decimal.t() | nil,
          currency: String.t() | nil,
          status: String.t() | nil,
          stripe_payment_intent_id: String.t() | nil,
          stripe_session_id: String.t() | nil,
          metadata: map() | nil,
          user_id: integer() | nil,
          user: Kite4rent.Users.User.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "payments" do
    field :amount, :decimal
    field :currency, :string, default: "EUR"
    field :status, :string, default: "pending"
    field :stripe_payment_intent_id, :string
    field :stripe_session_id, :string
    field :metadata, :map, default: %{}

    belongs_to :user, Kite4rent.Users.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [
      :amount,
      :currency,
      :status,
      :stripe_payment_intent_id,
      :stripe_session_id,
      :metadata,
      :user_id
    ])
    |> validate_required([:amount, :currency, :status, :user_id])
    |> validate_inclusion(:status, [
      "pending",
      "processing",
      "succeeded",
      "failed",
      "canceled",
      "refunded"
    ])
    |> validate_inclusion(:currency, ["EUR", "USD", "GBP"])
    |> validate_number(:amount, greater_than: 0)
    |> validate_length(:currency, is: 3)
    |> unique_constraint(:stripe_payment_intent_id)
    |> unique_constraint(:stripe_session_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Returns the default price for contact marketplace access.
  """
  def default_price, do: Decimal.new("3.00")

  @european_country_codes ~w(
    AL AD AT BY BE BA BG HR CY CZ DK EE FI FR DE GR HU IS IE IT
    XK LV LI LT LU MT MD MC ME NL MK NO PL PT RO RU SM RS SK SI
    ES SE CH UA VA GE AM AZ
  )

  @uk_country_code "GB"

  @doc """
  Returns the currency to charge based on the user's ISO 3166-1 alpha-2 country code.

  - European countries → EUR (including non-Eurozone like Poland, Sweden, etc.)
  - United Kingdom (GB) → GBP
  - All others → USD
  """
  def currency_for_country(@uk_country_code), do: "GBP"

  def currency_for_country(country_code) when country_code in @european_country_codes, do: "EUR"

  def currency_for_country(_), do: "USD"

  @doc """
  Returns a display string like "€3", "£3", or "$3" for the given currency.
  """
  def price_label(currency) do
    symbol =
      case currency do
        "EUR" -> "€"
        "GBP" -> "£"
        "USD" -> "$"
        _ -> "$"
      end

    "#{symbol}#{default_price() |> Decimal.to_integer()}"
  end
end
