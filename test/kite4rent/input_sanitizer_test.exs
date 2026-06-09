defmodule Kite4rent.InputSanitizerTest do
  use ExUnit.Case, async: true
  doctest Kite4rent.InputSanitizer
  alias Kite4rent.InputSanitizer

  describe "sanitize_language/1" do
    test "converts 2-character uppercase language to lowercase" do
      assert InputSanitizer.sanitize_language("ES") == "es"
      assert InputSanitizer.sanitize_language("EN") == "en"
      assert InputSanitizer.sanitize_language("FR") == "fr"
      assert InputSanitizer.sanitize_language("DE") == "de"
    end

    test "converts 2-character mixed case language to lowercase" do
      assert InputSanitizer.sanitize_language("Es") == "es"
      assert InputSanitizer.sanitize_language("En") == "en"
      assert InputSanitizer.sanitize_language("Fr") == "fr"
      assert InputSanitizer.sanitize_language("dE") == "de"
    end

    test "preserves already lowercase 2-character language codes" do
      assert InputSanitizer.sanitize_language("es") == "es"
      assert InputSanitizer.sanitize_language("en") == "en"
      assert InputSanitizer.sanitize_language("fr") == "fr"
      assert InputSanitizer.sanitize_language("de") == "de"
    end

    test "trims whitespace before checking length" do
      assert InputSanitizer.sanitize_language("  ES  ") == "es"
      assert InputSanitizer.sanitize_language("\tEN\t") == "en"
      assert InputSanitizer.sanitize_language("\nFR\n") == "fr"
    end

    test "preserves invalid length language codes unchanged" do
      # Too short
      assert InputSanitizer.sanitize_language("e") == "e"
      assert InputSanitizer.sanitize_language("E") == "E"
      
      # Too long
      assert InputSanitizer.sanitize_language("eng") == "eng"
      assert InputSanitizer.sanitize_language("english") == "english"
      assert InputSanitizer.sanitize_language("ENGLISH") == "ENGLISH"
      assert InputSanitizer.sanitize_language("Spanish") == "Spanish"
    end

    test "handles empty and nil values" do
      assert InputSanitizer.sanitize_language(nil) == nil
      assert InputSanitizer.sanitize_language("") == ""
      assert InputSanitizer.sanitize_language("   ") == "   "
    end

    test "preserves non-string values unchanged" do
      assert InputSanitizer.sanitize_language(123) == 123
      assert InputSanitizer.sanitize_language(:en) == :en
      assert InputSanitizer.sanitize_language(%{lang: "es"}) == %{lang: "es"}
    end

    test "handles edge cases with special characters" do
      # These should not be sanitized as they're not standard 2-letter codes
      assert InputSanitizer.sanitize_language("E1") == "E1"
      assert InputSanitizer.sanitize_language("E-") == "E-"
      assert InputSanitizer.sanitize_language("🇪🇸") == "🇪🇸"
    end
  end

  describe "sanitize_country_code/1" do
    test "converts 2-character lowercase country code to uppercase" do
      assert InputSanitizer.sanitize_country_code("us") == "US"
      assert InputSanitizer.sanitize_country_code("es") == "ES"
      assert InputSanitizer.sanitize_country_code("fr") == "FR"
      assert InputSanitizer.sanitize_country_code("de") == "DE"
    end

    test "converts 2-character mixed case country code to uppercase" do
      assert InputSanitizer.sanitize_country_code("Us") == "US"
      assert InputSanitizer.sanitize_country_code("eS") == "ES"
      assert InputSanitizer.sanitize_country_code("Fr") == "FR"
      assert InputSanitizer.sanitize_country_code("dE") == "DE"
    end

    test "preserves already uppercase 2-character country codes" do
      assert InputSanitizer.sanitize_country_code("US") == "US"
      assert InputSanitizer.sanitize_country_code("ES") == "ES"
      assert InputSanitizer.sanitize_country_code("FR") == "FR"
      assert InputSanitizer.sanitize_country_code("DE") == "DE"
    end

    test "trims whitespace before checking length" do
      assert InputSanitizer.sanitize_country_code("  us  ") == "US"
      assert InputSanitizer.sanitize_country_code("\tes\t") == "ES"
      assert InputSanitizer.sanitize_country_code("\nfr\n") == "FR"
    end

    test "preserves invalid length country codes unchanged" do
      # Too short
      assert InputSanitizer.sanitize_country_code("u") == "u"
      assert InputSanitizer.sanitize_country_code("U") == "U"
      
      # Too long
      assert InputSanitizer.sanitize_country_code("usa") == "usa"
      assert InputSanitizer.sanitize_country_code("united states") == "united states"
      assert InputSanitizer.sanitize_country_code("UNITED STATES") == "UNITED STATES"
      assert InputSanitizer.sanitize_country_code("España") == "España"
    end

    test "handles empty and nil values" do
      assert InputSanitizer.sanitize_country_code(nil) == nil
      assert InputSanitizer.sanitize_country_code("") == ""
      assert InputSanitizer.sanitize_country_code("   ") == "   "
    end

    test "preserves non-string values unchanged" do
      assert InputSanitizer.sanitize_country_code(123) == 123
      assert InputSanitizer.sanitize_country_code(:us) == :us
      assert InputSanitizer.sanitize_country_code(%{country: "us"}) == %{country: "us"}
    end

    test "handles edge cases with special characters" do
      # These should not be sanitized as they're not standard 2-letter codes
      assert InputSanitizer.sanitize_country_code("U1") == "U1"
      assert InputSanitizer.sanitize_country_code("U-") == "U-"
      assert InputSanitizer.sanitize_country_code("🇺🇸") == "🇺🇸"
    end
  end

  describe "integration scenarios" do
    test "common real-world language inputs" do
      # From LLM responses
      assert InputSanitizer.sanitize_language("EN") == "en"
      assert InputSanitizer.sanitize_language("Es") == "es"
      
      # From AssemblyAI
      assert InputSanitizer.sanitize_language("EN") == "en"
      assert InputSanitizer.sanitize_language("pt") == "pt"
      
      # Invalid inputs that should be preserved
      assert InputSanitizer.sanitize_language("auto") == "auto"
      assert InputSanitizer.sanitize_language("english") == "english"
    end

    test "common real-world country code inputs" do
      # From geocoding APIs
      assert InputSanitizer.sanitize_country_code("us") == "US"
      assert InputSanitizer.sanitize_country_code("es") == "ES"
      assert InputSanitizer.sanitize_country_code("xx") == "XX"
      
      # Invalid inputs that should be preserved
      assert InputSanitizer.sanitize_country_code("usa") == "usa"
      assert InputSanitizer.sanitize_country_code("spain") == "spain"
    end
  end
end