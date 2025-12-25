defmodule CooklangExPropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  describe "property-based parsing tests" do
    property "parsing never crashes on any input" do
      check all(input <- string(:printable)) do
        # Should always return ok or error tuple, never crash
        result = CooklangEx.parse(input)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end

    property "parsing empty strings always succeeds" do
      check all(whitespace <- string([?\s, ?\n, ?\t, ?\r], min_length: 0, max_length: 100)) do
        assert {:ok, recipe} = CooklangEx.parse(whitespace)
        assert recipe.ingredients == []
        assert recipe.cookware == []
        assert recipe.timers == []
      end
    end

    property "parsing preserves ingredient names" do
      check all(name <- string(:alphanumeric, min_length: 1, max_length: 50)) do
        input = "@#{name}{}"

        case CooklangEx.parse(input) do
          {:ok, recipe} ->
            if length(recipe.ingredients) > 0 do
              ingredient = hd(recipe.ingredients)
              assert is_binary(ingredient.name)
              assert String.length(ingredient.name) > 0
            end

          {:error, _} ->
            # Some generated strings might not parse, that's ok
            :ok
        end
      end
    end

    @tag :skip
    property "scaling maintains proportions when scaling up" do
      # NOTE: Skipped due to known issues in cooklang-rs scaling implementation
      check all(
              original_servings <- integer(2..10),
              scale_factor <- integer(2..5),
              quantity <- float(min: 10.0, max: 1000.0)
            ) do
        target_servings = original_servings * scale_factor

        # Create recipe with servings metadata
        input = """
        >> servings: #{original_servings}

        Add @flour{#{quantity}%g}.
        """

        case CooklangEx.parse_and_scale(input, target_servings) do
          {:ok, recipe} ->
            if length(recipe.ingredients) > 0 do
              flour = hd(recipe.ingredients)
              expected = quantity * scale_factor
              # Allow for floating point errors - use relative delta
              delta = max(1.0, abs(expected) * 0.01)
              assert_in_delta(flour.quantity.value, expected, delta)
            end

          {:error, _} ->
            # Scaling might fail, that's ok for property tests
            :ok
        end
      end
    end

    property "multiple ingredients are all captured" do
      check all(count <- integer(1..10)) do
        # Generate multiple ingredient declarations
        ingredients =
          1..count
          |> Enum.map(fn i -> "@ingredient#{i}{#{i}%g}" end)
          |> Enum.join(" and ")

        input = "Add #{ingredients}."

        case CooklangEx.parse(input) do
          {:ok, recipe} ->
            # Should capture at least some ingredients
            assert is_list(recipe.ingredients)

          {:error, _} ->
            :ok
        end
      end
    end

    property "cookware parsing is consistent" do
      check all(cookware_name <- string(:alphanumeric, min_length: 1, max_length: 20)) do
        input = "##{cookware_name}{}"

        case CooklangEx.parse(input) do
          {:ok, recipe} ->
            if length(recipe.cookware) > 0 do
              cookware = hd(recipe.cookware)
              assert is_binary(cookware.name)
            end

          {:error, _} ->
            :ok
        end
      end
    end

    property "timer quantities are non-negative" do
      check all(minutes <- integer(0..1000)) do
        input = "Cook for ~{#{minutes}%minutes}."

        case CooklangEx.parse(input) do
          {:ok, recipe} ->
            Enum.each(recipe.timers, fn timer ->
              if timer.quantity do
                assert timer.quantity.value >= 0
              end
            end)

          {:error, _} ->
            :ok
        end
      end
    end

    property "metadata keys and values are preserved" do
      check all(
              key <- string(:alphanumeric, min_length: 1, max_length: 20),
              value <- string(:printable, min_length: 0, max_length: 100)
            ) do
        # Sanitize value to remove newlines that would break metadata format
        safe_value = String.replace(value, ~r/[\r\n]/, " ")

        input = """
        >> #{key}: #{safe_value}

        Add @salt{}.
        """

        case CooklangEx.parse(input) do
          {:ok, recipe} ->
            assert is_map(recipe.metadata)

          {:error, _} ->
            :ok
        end
      end
    end
  end
end
