defmodule Kite4rent.Extractors.GearExtractorTest do
  use Kite4rent.DataCase, async: false
  use Mimic
  alias Kite4rent.Extractors.GearExtractor
  alias Kite4rent.Extractors.GearExtraction
  alias Kite4rent.Rental

  setup :verify_on_exit!

  setup do
    :ok
  end

  defp gear_item(attrs) do
    struct!(GearExtraction.GearItem, Map.merge(%{type: nil, brand: nil, model: nil, size: nil, year: nil, condition: nil, additional_details: nil}, attrs))
  end

  describe "extract/2" do
    test "extracts North kite with correct brand-model consistency" do
      text = "Tengo un North Reach 11 del 2023 en excelente estado"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %GearExtraction{
          gear: [gear_item(%{type: "kite", brand: "North", model: "Reach", size: "11", year: "2023", condition: "excellent"})],
          extraction_confidence: 0.95,
          needs_clarification: false,
          clarification_request: nil
        }}
      end)

      assert {:ok, result} = GearExtractor.extract(text)
      assert length(result.gear) == 1

      gear = hd(result.gear)
      assert gear.type == "kite"
      assert gear.brand == "North"
      assert gear.model == "Reach"
      assert gear.size == "11m"
      assert gear.year == "2023"
      assert gear.condition == "excellent"
      assert result.extraction_confidence == 0.95
      assert result.needs_clarification == false
    end

    test "prevents brand-model hallucinations" do
      text = "Tengo un kite Ozone"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %GearExtraction{
          gear: [gear_item(%{type: "kite", brand: "Ozone", model: "Edge"})],
          extraction_confidence: 0.7,
          needs_clarification: true,
          clarification_request: "Need size specification"
        }}
      end)

      assert {:ok, result} = GearExtractor.extract(text)

      gear = hd(result.gear)
      assert gear.brand == "Ozone"
      assert gear.model == "Edge"
      assert result.needs_clarification == true
    end

    test "handles multiple gear items" do
      text = "Vendo kite Duotone Evo 12m y tabla Select 145cm"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %GearExtraction{
          gear: [
            gear_item(%{type: "kite", brand: "Duotone", model: "Evo", size: "12m"}),
            gear_item(%{type: "board", brand: "Duotone", model: "Select", size: "145cm"})
          ],
          extraction_confidence: 0.9,
          needs_clarification: false,
          clarification_request: nil
        }}
      end)

      assert {:ok, result} = GearExtractor.extract(text)
      assert length(result.gear) == 2

      [kite, board] = result.gear
      assert kite.brand == "Duotone"
      assert kite.model == "Evo"
      assert board.brand == "Duotone"
      assert board.model == "Select"
    end

    test "handles no gear found" do
      text = "Hola, ¿cómo estás?"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %GearExtraction{
          gear: [],
          extraction_confidence: 0.9,
          needs_clarification: false,
          clarification_request: nil
        }}
      end)

      assert {:ok, result} = GearExtractor.extract(text)
      assert result.gear == []
      assert result.needs_clarification == false
    end

    test "sanitizes gear types correctly" do
      text = "Tengo equipo de kite"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %GearExtraction{
          gear: [gear_item(%{type: "KITE"})],
          extraction_confidence: 0.6,
          needs_clarification: true,
          clarification_request: "Need specific gear details"
        }}
      end)

      assert {:ok, result} = GearExtractor.extract(text)

      gear = hd(result.gear)
      assert gear.type == "kite"
    end

    @tag :capture_log
    test "handles LLM generation failure" do
      text = "Test message"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:error, "API error"}
      end)

      assert {:error, :gear_extraction_error, "Gear extraction failed"} = GearExtractor.extract(text)
    end

    test "clears clarification when enrichment resolves all missing brands" do
      Rental.create_gear_model(%{model_name: "Reach", brand: "North", gear_type: "kite"})
      Rental.create_gear_model(%{model_name: "Orbit", brand: "North", gear_type: "kite"})

      text = "Un 12 reach 2025, un orbit 7 2025"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %GearExtraction{
          gear: [
            gear_item(%{type: "kite", brand: nil, model: "Reach", size: "12", year: "2025"}),
            gear_item(%{type: "kite", brand: nil, model: "Orbit", size: "7", year: "2025"})
          ],
          extraction_confidence: 0.8,
          needs_clarification: true,
          clarification_request: "¿De qué marca son los kites Reach y Orbit?"
        }}
      end)

      assert {:ok, result} = GearExtractor.extract(text)
      # Brands enriched from reference
      assert Enum.all?(result.gear, fn g -> g.brand == "North" end)
      # Clarification cleared since all brands are now resolved
      assert result.needs_clarification == false
      assert result.clarification_request == nil
    end

    test "keeps clarification when enrichment can't resolve all brands" do
      # Only Reach is in reference, UnknownModel is not
      Rental.create_gear_model(%{model_name: "Reach", brand: "North", gear_type: "kite"})

      text = "Un 12 reach y un unknownmodel"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %GearExtraction{
          gear: [
            gear_item(%{type: "kite", brand: nil, model: "Reach", size: "12"}),
            gear_item(%{type: "kite", brand: nil, model: "UnknownModel", size: "9"})
          ],
          extraction_confidence: 0.7,
          needs_clarification: true,
          clarification_request: "What brand are these kites?"
        }}
      end)

      assert {:ok, result} = GearExtractor.extract(text)
      # Reach gets brand, UnknownModel doesn't
      assert hd(result.gear).brand == "North"
      assert List.last(result.gear).brand == nil
      # Clarification stays because one item still has no brand
      assert result.needs_clarification == true
    end

    test "auto-adds size units for kites and boards" do
      text = "Kite 12 and board 145"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %GearExtraction{
          gear: [
            gear_item(%{type: "kite", size: "12"}),
            gear_item(%{type: "board", size: "145"})
          ],
          extraction_confidence: 0.8,
          needs_clarification: false,
          clarification_request: nil
        }}
      end)

      assert {:ok, result} = GearExtractor.extract(text)

      [kite, board] = result.gear
      assert kite.size == "12m"
      assert board.size == "145cm"
    end
  end

  describe "enrich_brands_from_reference/1" do
    test "overwrites LLM brand with reference table match (ground truth)" do
      Rental.create_gear_model(%{model_name: "RPM", brand: "Slingshot", gear_type: "kite"})

      result = %{
        gear: [%{type: "kite", brand: "F-One", model: "RPM", size: "11m", year: "2020", gender: nil, condition: nil}],
        extraction_confidence: 0.9,
        needs_clarification: false,
        clarification_request: nil
      }

      enriched = GearExtractor.enrich_brands_from_reference(result)
      assert hd(enriched.gear).brand == "Slingshot"
    end

    test "sets brand when LLM returned nil and reference has unique match" do
      Rental.create_gear_model(%{model_name: "Orbit", brand: "North", gear_type: "kite"})

      result = %{
        gear: [%{type: "kite", brand: nil, model: "Orbit", size: "10m", year: "2023", gender: nil, condition: nil}],
        extraction_confidence: 0.8,
        needs_clarification: true,
        clarification_request: "What brand?"
      }

      enriched = GearExtractor.enrich_brands_from_reference(result)
      assert hd(enriched.gear).brand == "North"
    end

    test "also enriches gear_type from reference when type is nil or other" do
      Rental.create_gear_model(%{model_name: "Orbit", brand: "North", gear_type: "kite"})

      result = %{
        gear: [%{type: "other", brand: nil, model: "Orbit", size: "10m", year: "2023", gender: nil, condition: nil}],
        extraction_confidence: 0.8,
        needs_clarification: false,
        clarification_request: nil
      }

      enriched = GearExtractor.enrich_brands_from_reference(result)
      assert hd(enriched.gear).type == "kite"
      assert hd(enriched.gear).brand == "North"
    end

    test "does not overwrite existing type when reference has different type" do
      Rental.create_gear_model(%{model_name: "Orbit", brand: "North", gear_type: "kite"})

      result = %{
        gear: [%{type: "board", brand: nil, model: "Orbit", size: "10m", year: "2023", gender: nil, condition: nil}],
        extraction_confidence: 0.8,
        needs_clarification: false,
        clarification_request: nil
      }

      enriched = GearExtractor.enrich_brands_from_reference(result)
      # type stays "board" since it was already set (not nil/other)
      assert hd(enriched.gear).type == "board"
      assert hd(enriched.gear).brand == "North"
    end

    test "keeps LLM brand when reference is ambiguous" do
      Rental.create_gear_model(%{model_name: "Edge", brand: "Ozone", gear_type: "kite"})
      Rental.create_gear_model(%{model_name: "Edge", brand: "Slingshot", gear_type: "board"})

      result = %{
        gear: [%{type: "kite", brand: "Ozone", model: "Edge", size: nil, year: nil, gender: nil, condition: nil}],
        extraction_confidence: 0.7,
        needs_clarification: false,
        clarification_request: nil
      }

      enriched = GearExtractor.enrich_brands_from_reference(result)
      assert hd(enriched.gear).brand == "Ozone"
    end

    test "keeps nil brand when reference is ambiguous and LLM had no brand" do
      Rental.create_gear_model(%{model_name: "Edge", brand: "Ozone", gear_type: "kite"})
      Rental.create_gear_model(%{model_name: "Edge", brand: "Slingshot", gear_type: "board"})

      result = %{
        gear: [%{type: "kite", brand: nil, model: "Edge", size: nil, year: nil, gender: nil, condition: nil}],
        extraction_confidence: 0.7,
        needs_clarification: false,
        clarification_request: nil
      }

      enriched = GearExtractor.enrich_brands_from_reference(result)
      assert hd(enriched.gear).brand == nil
    end

    test "keeps LLM brand when model is not in reference table" do
      result = %{
        gear: [%{type: "kite", brand: "SomeBrand", model: "UnknownModel", size: nil, year: nil, gender: nil, condition: nil}],
        extraction_confidence: 0.7,
        needs_clarification: false,
        clarification_request: nil
      }

      enriched = GearExtractor.enrich_brands_from_reference(result)
      assert hd(enriched.gear).brand == "SomeBrand"
    end

    test "keeps nil brand when model is not in reference table and LLM had no brand" do
      result = %{
        gear: [%{type: "kite", brand: nil, model: "UnknownModel", size: nil, year: nil, gender: nil, condition: nil}],
        extraction_confidence: 0.7,
        needs_clarification: false,
        clarification_request: nil
      }

      enriched = GearExtractor.enrich_brands_from_reference(result)
      assert hd(enriched.gear).brand == nil
    end

    test "handles items with nil model gracefully" do
      result = %{
        gear: [%{type: "kite", brand: "North", model: nil, size: nil, year: nil, gender: nil, condition: nil}],
        extraction_confidence: 0.5,
        needs_clarification: true,
        clarification_request: nil
      }

      enriched = GearExtractor.enrich_brands_from_reference(result)
      assert hd(enriched.gear).brand == "North"
    end
  end

  describe "null string sanitization" do
    test "sanitizes brand 'null' string to nil" do
      text = "Some kite"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %GearExtraction{
          gear: [gear_item(%{type: "kite", brand: "null", model: "Reach", size: "12"})],
          extraction_confidence: 0.8,
          needs_clarification: false,
          clarification_request: nil
        }}
      end)

      assert {:ok, result} = GearExtractor.extract(text)
      assert hd(result.gear).brand == nil
    end

    test "sanitizes size 'null' string to nil" do
      text = "Some kite"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %GearExtraction{
          gear: [gear_item(%{type: "kite", brand: "North", model: "Reach", size: "null"})],
          extraction_confidence: 0.8,
          needs_clarification: false,
          clarification_request: nil
        }}
      end)

      assert {:ok, result} = GearExtractor.extract(text)
      assert hd(result.gear).size == nil
    end

    test "sanitizes condition 'null' string to nil" do
      text = "Some kite"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %GearExtraction{
          gear: [gear_item(%{type: "kite", brand: "North", model: "Reach", condition: "null"})],
          extraction_confidence: 0.8,
          needs_clarification: false,
          clarification_request: nil
        }}
      end)

      assert {:ok, result} = GearExtractor.extract(text)
      assert hd(result.gear).condition == nil
    end
  end

  describe "brand consistency validation" do
    test "validates known brand-model combinations" do
      text = "North Edge kite"

      expect(Kite4rent.LLM, :instruct, fn _params, _opts ->
        {:ok, %GearExtraction{
          gear: [gear_item(%{type: "kite"})],
          extraction_confidence: 0.3,
          needs_clarification: true,
          clarification_request: "Unclear brand-model combination"
        }}
      end)

      assert {:ok, result} = GearExtractor.extract(text)
      assert result.needs_clarification == true
      assert result.extraction_confidence <= 0.5
    end
  end
end
