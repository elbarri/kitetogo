defmodule Kite4rent.InputSanitizer do
  @moduledoc """
  Centralizes input sanitization logic for consistent data normalization across the application.
  
  This module provides functions to sanitize user inputs before validation, ensuring
  consistent data formats while preserving invalid inputs for proper validation errors.
  
  ## Design Philosophy
  
  - **Conservative sanitization**: Only sanitize inputs that are likely formatting issues
  - **Preserve validation**: Don't "fix" clearly invalid inputs - let validation handle them
  - **Consistent behavior**: Same sanitization logic used everywhere in the application
  
  ## Examples
  
      iex> Kite4rent.InputSanitizer.sanitize_language("ES")
      "es"
      
      iex> Kite4rent.InputSanitizer.sanitize_language("english")
      "english"  # Preserved for validation to handle
      
      iex> Kite4rent.InputSanitizer.sanitize_country_code("us")
      "US"
      
      iex> Kite4rent.InputSanitizer.sanitize_country_code("united states")
      "united states"  # Preserved for validation to handle
  """

  @doc """
  Sanitizes language codes to always be 2 lowercase letters when the input is exactly 2 alphabetic characters.
  
  This function only sanitizes case for 2-character alphabetic inputs, assuming they are valid ISO 639-1
  language codes that just need case correction. Inputs with non-alphabetic characters or other 
  lengths are preserved unchanged so validation can properly reject them.
  
  ## Examples
  
      iex> Kite4rent.InputSanitizer.sanitize_language("ES")
      "es"
      
      iex> Kite4rent.InputSanitizer.sanitize_language("En")
      "en"
      
      iex> Kite4rent.InputSanitizer.sanitize_language("es")
      "es"
      
      iex> Kite4rent.InputSanitizer.sanitize_language("english")
      "english"
      
      iex> Kite4rent.InputSanitizer.sanitize_language("e")
      "e"
      
      iex> Kite4rent.InputSanitizer.sanitize_language(nil)
      nil
      
      iex> Kite4rent.InputSanitizer.sanitize_language("")
      ""
  """
  @spec sanitize_language(String.t() | nil) :: String.t() | nil
  def sanitize_language(nil), do: nil
  def sanitize_language(language) when is_binary(language) do
    trimmed = String.trim(language)
    
    # Only sanitize if it's exactly 2 alphabetic characters (likely valid ISO 639-1 code)
    if String.length(trimmed) == 2 and String.match?(trimmed, ~r/^[A-Za-z]{2}$/) do
      String.downcase(trimmed)
    else
      language
    end
  end
  def sanitize_language(language), do: language

  @doc """
  Sanitizes country codes to always be 2 uppercase letters when the input is exactly 2 alphabetic characters.
  
  This function only sanitizes case for 2-character alphabetic inputs, assuming they are valid ISO 3166-1
  country codes that just need case correction. Inputs with non-alphabetic characters or other 
  lengths are preserved unchanged so validation can properly reject them.
  
  ## Examples
  
      iex> Kite4rent.InputSanitizer.sanitize_country_code("us")
      "US"
      
      iex> Kite4rent.InputSanitizer.sanitize_country_code("Es")
      "ES"
      
      iex> Kite4rent.InputSanitizer.sanitize_country_code("US")
      "US"
      
      iex> Kite4rent.InputSanitizer.sanitize_country_code("united states")
      "united states"
      
      iex> Kite4rent.InputSanitizer.sanitize_country_code("u")
      "u"
      
      iex> Kite4rent.InputSanitizer.sanitize_country_code(nil)
      nil
      
      iex> Kite4rent.InputSanitizer.sanitize_country_code("")
      ""
  """
  @spec sanitize_country_code(String.t() | nil) :: String.t() | nil
  def sanitize_country_code(nil), do: nil
  def sanitize_country_code(country_code) when is_binary(country_code) do
    trimmed = String.trim(country_code)
    
    # Only sanitize if it's exactly 2 alphabetic characters (likely valid ISO 3166-1 code)
    if String.length(trimmed) == 2 and String.match?(trimmed, ~r/^[A-Za-z]{2}$/) do
      String.upcase(trimmed)
    else
      country_code
    end
  end
  def sanitize_country_code(country_code), do: country_code
end