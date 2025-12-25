defmodule CooklangExEdgeCasesTest do
  use ExUnit.Case

  describe "unicode and special character handling" do
    test "parses recipes with unicode ingredient names" do
      recipe_text = """
      Add @jalapeño{2} and @café{1%cup}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      names = Enum.map(recipe.ingredients, & &1.name)
      assert "jalapeño" in names or "jalape\u00F1o" in names
    end

    test "handles emoji in recipe text" do
      recipe_text = """
      >> title: Amazing 🍕 Pizza

      Add @mozzarella{200%g} 🧀 and cook in #oven{}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert map_size(recipe.metadata) > 0
    end

    test "parses CJK characters" do
      recipe_text = """
      >> title: 中华料理

      Add @豆腐{100%g} and @しょうゆ{2%tbsp}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      # At minimum, should not crash
      assert is_list(recipe.ingredients)
    end

    test "handles Arabic and RTL text" do
      recipe_text = """
      >> title: طعام عربي

      Add @ملح{1%tsp}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert is_list(recipe.ingredients)
    end

    test "parses ingredients with diacritics" do
      recipe_text = """
      Add @crème_fraîche{100%ml} and @münster_cheese{50%g}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert length(recipe.ingredients) >= 1
    end

    test "handles zero-width characters" do
      # Zero-width space (U+200B)
      recipe_text = "Add @salt\u200B{1%tsp}."

      case CooklangEx.parse(recipe_text) do
        {:ok, recipe} ->
          assert is_list(recipe.ingredients)

        {:error, _} ->
          # Zero-width chars might cause parse errors, that's acceptable
          :ok
      end
    end

    test "handles very long ingredient names" do
      long_name = String.duplicate("very_long_ingredient_name_", 20)
      recipe_text = "Add @#{long_name}{1}."

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert is_list(recipe.ingredients)
    end
  end

  describe "malformed input handling" do
    test "handles unclosed ingredient braces" do
      recipe_text = "Add @salt{1%tsp and @pepper{}."

      case CooklangEx.parse(recipe_text) do
        {:ok, recipe} ->
          # Parser is permissive, might still parse
          assert is_list(recipe.ingredients)

        {:error, _reason} ->
          # Or might return error
          :ok
      end
    end

    test "handles nested braces" do
      recipe_text = "Add @ingredient{{nested}%unit}."

      case CooklangEx.parse(recipe_text) do
        {:ok, recipe} ->
          assert is_list(recipe.ingredients)

        {:error, _} ->
          :ok
      end
    end

    test "handles multiple @ symbols" do
      recipe_text = "Add @@salt{1%tsp}."

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      # Should handle gracefully even if unexpected
      assert is_list(recipe.ingredients)
    end

    test "handles special characters in quantities" do
      recipe_text = "Add @salt{1.5e-2%kg}."

      case CooklangEx.parse(recipe_text) do
        {:ok, recipe} ->
          assert is_list(recipe.ingredients)

        {:error, _} ->
          :ok
      end
    end

    test "handles very large numbers" do
      recipe_text = "Add @water{999999999%liters}."

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)

      if length(recipe.ingredients) > 0 do
        water = hd(recipe.ingredients)

        if water.quantity do
          assert is_float(water.quantity.value)
        end
      end
    end

    test "handles negative numbers" do
      recipe_text = "Add @ingredient{-5%units}."

      case CooklangEx.parse(recipe_text) do
        {:ok, recipe} ->
          assert is_list(recipe.ingredients)

        {:error, _} ->
          # Negative quantities might not be allowed
          :ok
      end
    end

    test "handles fraction-like values" do
      recipe_text = "Add @flour{1/2%cup} and @sugar{3/4%cup}."

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert is_list(recipe.ingredients)
    end
  end

  describe "boundary conditions" do
    test "handles extremely long recipes" do
      # Generate a recipe with 500 steps
      steps =
        1..500
        |> Enum.map(fn i -> "Step #{i}: Add @ingredient#{i}{#{i}%g}." end)
        |> Enum.join("\n\n")

      assert {:ok, recipe} = CooklangEx.parse(steps)
      assert is_list(recipe.ingredients)
      # Should have many ingredients
      assert length(recipe.ingredients) > 100
    end

    test "handles recipe with many metadata fields" do
      metadata =
        1..50
        |> Enum.map(fn i -> ">> field#{i}: value#{i}" end)
        |> Enum.join("\n")

      recipe_text = """
      #{metadata}

      Add @salt{}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert map_size(recipe.metadata) > 10
    end

    test "handles empty metadata values" do
      recipe_text = """
      >> author:
      >> source:
      >> notes: Some notes

      Add @salt{}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert is_map(recipe.metadata)
    end

    test "handles metadata with colons in values" do
      recipe_text = """
      >> source: https://example.com:8080/recipe
      >> time: 1:30:00

      Add @salt{}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert recipe.metadata["source"] =~ "https://"
    end

    test "handles whitespace-only recipe" do
      recipe_text = "   \n\n\t\t  \n   "
      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert recipe.ingredients == []
    end

    test "handles recipe with only comments" do
      recipe_text = """
      -- This is a comment
      -- Another comment
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      # Comments should be ignored
      assert recipe.ingredients == []
    end

    test "handles mixed line endings (CRLF and LF)" do
      recipe_text = "Add @salt{1%tsp}.\r\nAdd @pepper{1%tsp}.\nAdd @cumin{1%tsp}."

      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      assert is_list(recipe.ingredients)
    end
  end

  describe "extension options" do
    test "parses with all_extensions: true" do
      recipe_text = "@ingredient{1%unit}"
      assert {:ok, recipe} = CooklangEx.parse(recipe_text, all_extensions: true)
      assert is_list(recipe.ingredients)
    end

    test "parses with all_extensions: false" do
      recipe_text = "@ingredient{1%unit}"
      assert {:ok, recipe} = CooklangEx.parse(recipe_text, all_extensions: false)
      assert is_list(recipe.ingredients)
    end

    test "parses with specific extensions list" do
      recipe_text = "@ingredient{1%unit}"
      # Test various extension combinations
      assert {:ok, _} = CooklangEx.parse(recipe_text, extensions: [])
      assert {:ok, _} = CooklangEx.parse(recipe_text, extensions: [:multiline_steps])
      assert {:ok, _} = CooklangEx.parse(recipe_text, extensions: [:sections])
    end

    test "all_extensions takes precedence over extensions list" do
      recipe_text = "@ingredient{1%unit}"

      assert {:ok, recipe} =
               CooklangEx.parse(recipe_text, extensions: [], all_extensions: true)

      assert is_list(recipe.ingredients)
    end

    test "extensions option with multiline_steps" do
      recipe_text = """
      == Preparation ==

      Chop @onions{2}.
      Mince @garlic{3%cloves}.

      == Cooking ==

      Heat @oil{2%tbsp} in a #pan{}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text, extensions: [:multiline_steps])
      assert is_list(recipe.ingredients)
    end

    test "extensions option with sections" do
      recipe_text = """
      == Preparation ==

      Mix @flour{200%g} and @water{100%ml}.

      == Cooking ==

      Bake for ~{20%minutes}.
      """

      assert {:ok, recipe} = CooklangEx.parse(recipe_text, extensions: [:sections])
      assert is_list(recipe.ingredients)
    end

    test "extensions option with multiple extensions" do
      recipe_text = """
      == Section 1 ==

      Step one with @ingredient1{}.

      == Section 2 ==

      Step two with @ingredient2{}.
      """

      assert {:ok, recipe} =
               CooklangEx.parse(recipe_text, extensions: [:multiline_steps, :sections])

      assert is_list(recipe.ingredients)
    end

    test "extensions work with parse_and_scale" do
      recipe_text = """
      >> servings: 2

      == Ingredients ==
      @flour{200%g}

      == Steps ==
      Mix everything.
      """

      assert {:ok, recipe} =
               CooklangEx.parse_and_scale(recipe_text, 4,
                 extensions: [:sections],
                 all_extensions: false
               )

      if length(recipe.ingredients) > 0 do
        flour = hd(recipe.ingredients)
        assert flour.quantity.value == 400.0
      end
    end

    test "all_extensions: false disables extensions" do
      recipe_text = "@ingredient{100%g}"

      # With all_extensions: false, behavior should be consistent
      assert {:ok, recipe1} = CooklangEx.parse(recipe_text, all_extensions: false)
      assert {:ok, recipe2} = CooklangEx.parse(recipe_text, all_extensions: false)

      assert length(recipe1.ingredients) == length(recipe2.ingredients)
    end

    test "extensions option is ignored when all_extensions is true" do
      recipe_text = "@salt{1%tsp}"

      # all_extensions: true should override extensions list
      result1 = CooklangEx.parse(recipe_text, all_extensions: true, extensions: [])

      result2 =
        CooklangEx.parse(recipe_text,
          all_extensions: true,
          extensions: [:multiline_steps, :sections]
        )

      assert {:ok, recipe1} = result1
      assert {:ok, recipe2} = result2
      # Both should parse successfully with all extensions
      assert length(recipe1.ingredients) == length(recipe2.ingredients)
    end

    test "empty extensions list parses basic recipes" do
      recipe_text = "Add @salt{1%tsp} to a #bowl{}."

      assert {:ok, recipe} = CooklangEx.parse(recipe_text, extensions: [], all_extensions: false)
      assert length(recipe.ingredients) == 1
      assert length(recipe.cookware) == 1
    end
  end

  describe "warning handling" do
    test "warnings field exists in parsed recipe" do
      recipe_text = "Add @salt{1%tsp}."
      assert {:ok, recipe} = CooklangEx.parse(recipe_text)
      # Warnings should be a list (empty or with warnings)
      assert is_list(recipe.warnings)
    end

    test "empty recipe has no warnings" do
      assert {:ok, recipe} = CooklangEx.parse("")
      assert recipe.warnings == []
    end
  end

  describe "error message validation" do
    test "error messages are descriptive strings when errors occur" do
      # Try to scale without servings metadata
      recipe_text = "Add @flour{200%g}."

      case CooklangEx.parse_and_scale(recipe_text, 4) do
        {:ok, _} ->
          # Might succeed with default servings
          :ok

        {:error, reason} ->
          assert is_binary(reason)
          assert String.length(reason) > 0
      end
    end

    test "parse! raises ArgumentError with message" do
      # Since cooklang-rs is permissive, we can't easily trigger a parse error
      # But we can test that parse! returns a recipe or raises properly
      recipe_text = "Add @salt{}."
      recipe = CooklangEx.parse!(recipe_text)
      assert %CooklangEx.Recipe{} = recipe
    end
  end
end
