defmodule Kite4rent.AgreementAuth do
  @moduledoc """
  Handles secure authentication for rental agreement access.

  Generates signed tokens to prevent URL tampering - users cannot
  change their role (owner/renter) by modifying query parameters.
  """

  @salt "agreement_access_token"
  # Tokens valid for 90 days (rental agreements may be long-term)
  @max_age 90 * 24 * 60 * 60

  @doc """
  Generates a signed access token for an agreement.

  ## Parameters
    - agreement_uuid: The UUID of the rental agreement
    - user_id: The ID of the user being granted access
    - role: :owner or :renter

  ## Returns
    A signed token string that can be appended to the URL
  """
  def generate_token(agreement_uuid, user_id, role) when role in [:owner, :renter] do
    data = %{
      agreement_uuid: agreement_uuid,
      user_id: user_id,
      role: role
    }

    Phoenix.Token.sign(Kite4rentWeb.Endpoint, @salt, data)
  end

  @doc """
  Verifies a signed access token and extracts the role.

  ## Parameters
    - token: The signed token from the URL parameter

  ## Returns
    - `{:ok, %{agreement_uuid: uuid, user_id: id, role: role}}` if valid
    - `{:error, reason}` if invalid or expired
  """
  def verify_token(token) when is_binary(token) do
    case Phoenix.Token.verify(Kite4rentWeb.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, %{agreement_uuid: uuid, user_id: user_id, role: role} = data}
        when role in [:owner, :renter] and is_binary(uuid) and is_integer(user_id) ->
        {:ok, data}

      {:ok, _invalid_data} ->
        {:error, :invalid_token_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def verify_token(_), do: {:error, :invalid_token}

  @doc """
  Generates a secure agreement URL with signed token.

  ## Parameters
    - base_url: The base URL of the application
    - agreement_uuid: The UUID of the rental agreement
    - user_id: The ID of the user being granted access
    - role: :owner or :renter

  ## Returns
    Full URL with signed token parameter
  """
  def generate_agreement_url(base_url, agreement_uuid, user_id, role) do
    token = generate_token(agreement_uuid, user_id, role)
    "#{base_url}/agreement/#{agreement_uuid}?token=#{URI.encode_www_form(token)}"
  end
end
