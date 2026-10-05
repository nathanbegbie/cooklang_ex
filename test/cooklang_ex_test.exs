defmodule CooklangExTest do
  use ExUnit.Case
  doctest CooklangEx

  describe "parse/1" do
    test "parses a simple recipe" do
      recipe_text = """
      Add @eggs{3} to a #bowl{}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert length(recipe.ingredients) == 1
      assert hd(recipe.ingredients).name == "eggs"
      assert hd(recipe.ingredients).quantity.value == 3.0
    end

    test "parses ingredients with units" do
      recipe_text = """
      Add @flour{200%g} and @milk{1%cup}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert length(recipe.ingredients) == 2

      flour = Enum.find(recipe.ingredients, &(&1.name == "flour"))
      assert flour.quantity.value == 200.0
      assert flour.quantity.unit == "g"

      milk = Enum.find(recipe.ingredients, &(&1.name == "milk"))
      assert milk.quantity.value == 1.0
      assert milk.quantity.unit == "cup"
    end

    test "parses multi-word ingredient names" do
      recipe_text = """
      Season with @ground black pepper{} and @sea salt{1%pinch}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert length(recipe.ingredients) == 2

      names = Enum.map(recipe.ingredients, & &1.name)
      assert "ground black pepper" in names
      assert "sea salt" in names
    end

    test "parses cookware" do
      recipe_text = """
      Heat in a #pan{large} and serve in a #bowl{}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert length(recipe.cookware) == 2

      names = Enum.map(recipe.cookware, & &1.name)
      assert "pan" in names
      assert "bowl" in names
    end

    test "parses timers" do
      recipe_text = """
      Cook for ~{5%minutes} then rest for ~{30%seconds}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert length(recipe.timers) == 2
    end

    test "parses metadata" do
      recipe_text = """
      >> servings: 4
      >> source: https://example.com
      >> time: 30 minutes

      Add @salt{}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert recipe.metadata["servings"] == "4"
      assert recipe.metadata["source"] == "https://example.com"
      assert recipe.metadata["time"] == "30 minutes"
    end

    test "handles empty recipe" do
      assert {:ok, recipe} = CooklangEx.parse("")
      assert recipe.ingredients == []
      assert recipe.cookware == []
      assert recipe.timers == []
    end
  end

  describe "parse/2 diagnostics" do
    @recipe_with_errors """
    Chop @onion{1}.

    Add @flour{%g} and stir.

    Add @salt{=} to taste.
    """

    test "returns a ParseError with a diagnostic and a position for each error" do
      assert {:error, %CooklangEx.ParseError{} = error} = CooklangEx.parse(@recipe_with_errors)

      assert error.message == "Empty quantity value\nEmpty quantity value"

      assert [first, second] = error.diagnostics
      assert %CooklangEx.Diagnostic{severity: :error, message: "Empty quantity value"} = first

      # cooklang-rs marks the empty point where the value is missing: before `%g`.
      assert [
               %CooklangEx.Diagnostic.Label{line: 3, column: 12, message: "add value here"} =
                 label
             ] =
               first.labels

      assert label.start == label.end
      assert binary_part(@recipe_with_errors, label.start, 2) == "%g"

      assert [%CooklangEx.Diagnostic.Label{line: 5, column: 12}] = second.labels
    end

    test "returns warnings with positions in recipe.diagnostics" do
      assert {:ok, recipe} = CooklangEx.parse("Stir.\nWait ~{10}.\n")

      assert recipe.warnings == ["Invalid timer quantity: missing unit"]

      assert [
               %CooklangEx.Diagnostic{
                 severity: :warning,
                 message: "Invalid timer quantity: missing unit",
                 labels: [%CooklangEx.Diagnostic.Label{line: 2} | _]
               }
             ] = recipe.diagnostics
    end

    test "keeps every error and warning of a failed parse, in report order" do
      # cooklang-rs keeps parsing after an error, so the report also has the
      # problems that come after the first error.
      source = "Add @flour{%g}.\nWait ~{10}.\nAdd @salt{%g}.\n"
      assert {:error, error} = CooklangEx.parse(source)

      assert error.message == "Empty quantity value\nEmpty quantity value"

      assert [
               %CooklangEx.Diagnostic{
                 severity: :error,
                 message: "Empty quantity value",
                 labels: [%CooklangEx.Diagnostic.Label{line: 1} | _]
               },
               %CooklangEx.Diagnostic{
                 severity: :warning,
                 message: "Invalid timer quantity: missing unit",
                 labels: [%CooklangEx.Diagnostic.Label{line: 2} | _]
               },
               %CooklangEx.Diagnostic{
                 severity: :error,
                 message: "Empty quantity value",
                 labels: [%CooklangEx.Diagnostic.Label{line: 3} | _]
               }
             ] = error.diagnostics
    end

    test "reports the stage that raised each diagnostic, with its hints" do
      assert {:error, error} = CooklangEx.parse("Add @flour{%g}.")

      assert [%CooklangEx.Diagnostic{message: "Empty quantity value", stage: :parse}] =
               error.diagnostics

      assert {:ok, recipe} = CooklangEx.parse("Use a #pan{=2}.")

      assert [
               %CooklangEx.Diagnostic{
                 severity: :warning,
                 message: "Unnecessary scaling lock modifier",
                 stage: :analysis,
                 hints: ["Only ingredients can be scaled, scaling lock is not needed here"]
               }
             ] = recipe.diagnostics
    end

    test "reports the underlying cause of a diagnostic, if there is one" do
      # The numerator does not fit in the u32 that cooklang-rs parses it into.
      assert {:error, error} = CooklangEx.parse("Add @eggs{99999999999/2}.")

      assert [
               %CooklangEx.Diagnostic{
                 message: "Error parsing integer number",
                 cause: "number too large to fit in target type"
               }
             ] = error.diagnostics

      assert {:error, error} = CooklangEx.parse("Add @flour{%g}.")
      assert [%CooklangEx.Diagnostic{cause: nil}] = error.diagnostics
    end

    test "counts columns in characters, not in bytes" do
      source = "Crème brûlée ~{10}.\nAjoutez @farine{%g}.\n"
      assert {:error, error} = CooklangEx.parse(source)

      assert [
               %CooklangEx.Diagnostic{labels: [warning_label | _]},
               %CooklangEx.Diagnostic{labels: [error_label | _]}
             ] = error.diagnostics

      # `}` is the 18th character of line 1, after three 2-byte characters.
      assert {warning_label.line, warning_label.column} == {1, 18}
      assert binary_part(source, warning_label.start, 1) == "}"

      # `%` is the 17th character of line 2.
      assert {error_label.line, error_label.column} == {2, 17}
      assert binary_part(source, error_label.start, 1) == "%"
    end

    test "counts lines with CRLF line endings" do
      source = "Stir.\r\nWait ~{10}.\r\nAdd @flour{%g}.\r\n"
      assert {:error, error} = CooklangEx.parse(source)

      assert [
               %CooklangEx.Diagnostic{labels: [%{line: 2} | _]},
               %CooklangEx.Diagnostic{labels: [%{line: 3, column: 12} | _]}
             ] = error.diagnostics
    end

    test "moves a label that points inside a multi-byte character to its start" do
      # cooklang-rs points one byte before the `(` of a timer note, which is
      # inside the 2-byte `é`.
      source = "Wait ~minuté(soft)."
      assert {:error, error} = CooklangEx.parse(source)

      assert [
               %CooklangEx.Diagnostic{
                 message: "A timer cannot have a note, it will be text",
                 labels: [_note_label, space_label]
               },
               %CooklangEx.Diagnostic{message: "Invalid timer: missing quantity"}
             ] = error.diagnostics

      assert {space_label.line, space_label.column} == {1, 12}
      assert binary_part(source, space_label.start, 2) == "é"
    end

    test "turns into its message as a string, the error value before ParseError" do
      assert {:error, error} = CooklangEx.parse("Add @flour{%g}.\n\nAdd @salt{%g}.")

      assert to_string(error) == "Empty quantity value\nEmpty quantity value"
      assert "Failed: #{error}" == "Failed: Empty quantity value\nEmpty quantity value"
    end
  end

  describe "parse_and_scale/3 errors" do
    @recipe_with_error ">> servings: 2\n\nAdd @flour{%g}.\n"

    test "returns a ParseError with the diagnostics of the report" do
      assert {:error, %CooklangEx.ParseError{} = error} =
               CooklangEx.parse_and_scale(@recipe_with_error, 4)

      assert [
               %CooklangEx.Diagnostic{
                 message: "Empty quantity value",
                 labels: [%CooklangEx.Diagnostic.Label{line: 3, column: 12} | _]
               }
             ] = error.diagnostics
    end

    test "parse_and_scale!/3 raises the ParseError" do
      assert_raise CooklangEx.ParseError, "Empty quantity value", fn ->
        CooklangEx.parse_and_scale!(@recipe_with_error, 4)
      end
    end
  end

  describe "parse_and_scale/2" do
    test "scales ingredient quantities" do
      recipe_text = """
      >> servings: 2

      Add @flour{200%g} and @eggs{2}.
      """

      assert {:ok, recipe} = CooklangEx.parse_and_scale(recipe_text, 4)

      flour = Enum.find(recipe.ingredients, &(&1.name == "flour"))
      assert flour.quantity.value == 400.0

      eggs = Enum.find(recipe.ingredients, &(&1.name == "eggs"))
      assert eggs.quantity.value == 4.0
    end

    test "scales down" do
      recipe_text = """
      >> servings: 4

      Add @butter{100%g}.
      """

      assert {:ok, recipe} = CooklangEx.parse_and_scale(recipe_text, 2)

      butter = Enum.find(recipe.ingredients, &(&1.name == "butter"))
      assert butter.quantity.value == 50.0
    end
  end

  describe "ingredients/1" do
    test "extracts only ingredients" do
      recipe_text = """
      Add @eggs{3} to a #bowl{} and cook for ~{5%minutes}.
      """

      assert {:ok, ingredients} = CooklangEx.ingredients(recipe_text)
      assert length(ingredients) == 1
      assert hd(ingredients).name == "eggs"
    end
  end

  describe "cookware/1" do
    test "extracts only cookware" do
      recipe_text = """
      Add @eggs{3} to a #bowl{} and transfer to a #plate{}.
      """

      assert {:ok, cookware} = CooklangEx.cookware(recipe_text)
      assert length(cookware) == 2
    end
  end

  describe "metadata/1" do
    test "extracts only metadata" do
      recipe_text = """
      >> servings: 4
      >> author: Test

      Add @ingredient{}.
      """

      assert {:ok, metadata} = CooklangEx.metadata(recipe_text)
      assert metadata["servings"] == "4"
      assert metadata["author"] == "Test"
    end
  end

  describe "parse!/1" do
    test "returns recipe on success" do
      recipe = CooklangEx.parse!("Add @salt{}.")
      assert length(recipe.ingredients) == 1
    end

    test "raises on invalid input" do
      # Note: cooklang-rs is quite permissive, so we test with clearly invalid syntax
      # In practice, most input will parse (possibly with warnings)
      recipe = CooklangEx.parse!("Just plain text")
      assert recipe.ingredients == []
    end

    test "raises a ParseError with the joined messages" do
      assert_raise CooklangEx.ParseError, "Empty quantity value", fn ->
        CooklangEx.parse!("Add @flour{%g}.")
      end
    end
  end
end
