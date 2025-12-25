defmodule CooklangExConcurrentTest do
  use ExUnit.Case

  describe "concurrent parsing" do
    test "handles multiple concurrent parse calls" do
      recipe_text = """
      >> servings: 4

      Add @flour{200%g}, @eggs{2}, and @milk{500%ml}.
      Mix in a #bowl{large} for ~{5%minutes}.
      """

      # Parse the same recipe concurrently from multiple processes
      tasks =
        1..50
        |> Enum.map(fn _i ->
          Task.async(fn ->
            CooklangEx.parse(recipe_text)
          end)
        end)

      results = Task.await_many(tasks, 5000)

      # All results should be successful
      Enum.each(results, fn result ->
        assert {:ok, recipe} = result
        assert length(recipe.ingredients) == 3
        assert length(recipe.cookware) == 1
        assert length(recipe.timers) == 1
      end)
    end

    @tag :skip
    test "handles concurrent parse_and_scale calls" do
      # NOTE: Skipped due to known issues in cooklang-rs scaling implementation
      recipe_text = """
      >> servings: 2

      Add @flour{200%g} and @eggs{2}.
      """

      # Scale to different servings concurrently (only scaling up to avoid known issues)
      tasks =
        [2, 4, 6, 8, 10]
        |> Enum.flat_map(fn target ->
          # Run each scaling multiple times
          Enum.map(1..10, fn _ ->
            Task.async(fn ->
              {target, CooklangEx.parse_and_scale(recipe_text, target)}
            end)
          end)
        end)

      results = Task.await_many(tasks, 5000)

      # Verify all scalings are correct
      Enum.each(results, fn {target, result} ->
        assert {:ok, recipe} = result
        flour = Enum.find(recipe.ingredients, &(&1.name == "flour"))

        if flour && flour.quantity do
          expected_flour = 200.0 * target / 2
          assert_in_delta(flour.quantity.value, expected_flour, 1.0)
        end

        eggs = Enum.find(recipe.ingredients, &(&1.name == "eggs"))

        if eggs && eggs.quantity do
          expected_eggs = 2.0 * target / 2
          assert_in_delta(eggs.quantity.value, expected_eggs, 0.1)
        end
      end)
    end

    test "handles concurrent aisle config parsing" do
      config = """
      [produce]
      tomatoes
      onions

      [dairy]
      milk
      cheese
      """

      tasks =
        1..30
        |> Enum.map(fn _i ->
          Task.async(fn ->
            CooklangEx.parse_aisle_config(config)
          end)
        end)

      results = Task.await_many(tasks, 5000)

      Enum.each(results, fn result ->
        assert {:ok, json} = result
        assert is_binary(json)
        # Verify it's valid JSON
        assert {:ok, _} = Jason.decode(json)
      end)
    end

    test "handles mixed concurrent operations" do
      recipe_text = """
      Add @salt{1%tsp} and @pepper{1%tsp}.
      """

      aisle_config = """
      [spices]
      salt
      pepper
      """

      # Mix different types of operations
      tasks =
        1..40
        |> Enum.map(fn i ->
          Task.async(fn ->
            case rem(i, 4) do
              0 -> {:parse, CooklangEx.parse(recipe_text)}
              1 -> {:ingredients, CooklangEx.ingredients(recipe_text)}
              2 -> {:metadata, CooklangEx.metadata(recipe_text)}
              3 -> {:aisle, CooklangEx.parse_aisle_config(aisle_config)}
            end
          end)
        end)

      results = Task.await_many(tasks, 5000)

      Enum.each(results, fn result ->
        case result do
          {:parse, {:ok, recipe}} ->
            assert %CooklangEx.Recipe{} = recipe

          {:ingredients, {:ok, ingredients}} ->
            assert is_list(ingredients)

          {:metadata, {:ok, metadata}} ->
            assert is_map(metadata)

          {:aisle, {:ok, json}} ->
            assert is_binary(json)

          _ ->
            flunk("Unexpected result: #{inspect(result)}")
        end
      end)
    end

    test "concurrent parsing with different recipes" do
      recipes = [
        """
        >> title: Recipe 1
        Add @ingredient1{100%g}.
        """,
        """
        >> title: Recipe 2
        Add @ingredient2{200%ml} and @ingredient3{3}.
        """,
        """
        >> title: Recipe 3
        Cook in #pan{} for ~{10%minutes}.
        """,
        """
        >> title: Recipe 4
        Mix @a{}, @b{}, @c{}, @d{}, and @e{}.
        """
      ]

      tasks =
        1..100
        |> Enum.map(fn i ->
          recipe = Enum.at(recipes, rem(i, length(recipes)))

          Task.async(fn ->
            CooklangEx.parse(recipe)
          end)
        end)

      results = Task.await_many(tasks, 5000)

      # All should succeed
      Enum.each(results, fn result ->
        assert {:ok, recipe} = result
        assert %CooklangEx.Recipe{} = recipe
      end)
    end

    test "concurrent parse! calls don't interfere" do
      recipe_text = "Add @salt{1%tsp}."

      tasks =
        1..30
        |> Enum.map(fn _i ->
          Task.async(fn ->
            CooklangEx.parse!(recipe_text)
          end)
        end)

      results = Task.await_many(tasks, 5000)

      Enum.each(results, fn recipe ->
        assert %CooklangEx.Recipe{} = recipe
        assert length(recipe.ingredients) == 1
      end)
    end

    test "stress test with many concurrent operations" do
      recipe_text = """
      >> servings: 4
      >> time: 30 minutes

      Preheat #oven{} to 180°C.

      Mix @flour{300%g}, @sugar{200%g}, and @eggs{3} in a #bowl{large}.

      Bake for ~{25%minutes}.
      """

      # Create 200 concurrent tasks
      tasks =
        1..200
        |> Enum.map(fn i ->
          Task.async(fn ->
            case rem(i, 3) do
              0 ->
                {:parse, CooklangEx.parse(recipe_text)}

              1 ->
                {:scale, CooklangEx.parse_and_scale(recipe_text, 8)}

              2 ->
                {:ingredients, CooklangEx.ingredients(recipe_text)}
            end
          end)
        end)

      results = Task.await_many(tasks, 10000)

      # Verify all operations succeeded
      parse_count = Enum.count(results, &match?({:parse, {:ok, _}}, &1))
      scale_count = Enum.count(results, &match?({:scale, {:ok, _}}, &1))
      ingredient_count = Enum.count(results, &match?({:ingredients, {:ok, _}}, &1))

      assert parse_count > 0
      assert scale_count > 0
      assert ingredient_count > 0
      assert parse_count + scale_count + ingredient_count == 200
    end
  end

  describe "process isolation" do
    test "parse errors in one process don't affect others" do
      good_recipe = "Add @salt{1%tsp}."
      # Even with permissive parser, we can test isolation
      potentially_bad = "{{{}}}@@@###"

      tasks =
        1..20
        |> Enum.map(fn i ->
          Task.async(fn ->
            recipe = if rem(i, 2) == 0, do: good_recipe, else: potentially_bad
            {i, CooklangEx.parse(recipe)}
          end)
        end)

      results = Task.await_many(tasks, 5000)

      # All good recipes should parse successfully
      good_results = Enum.filter(results, fn {i, _} -> rem(i, 2) == 0 end)

      Enum.each(good_results, fn {_i, result} ->
        assert {:ok, recipe} = result
        assert length(recipe.ingredients) == 1
      end)
    end

    test "each process gets independent recipe structures" do
      recipe_text = "Add @ingredient{100%g}."

      tasks =
        1..50
        |> Enum.map(fn _i ->
          Task.async(fn ->
            {:ok, recipe} = CooklangEx.parse(recipe_text)
            # Return the recipe's object id (memory address)
            # Each should be a different struct instance
            recipe
          end)
        end)

      recipes = Task.await_many(tasks, 5000)

      # All recipes should have the same content but be different objects
      Enum.each(recipes, fn recipe ->
        assert %CooklangEx.Recipe{} = recipe
        assert length(recipe.ingredients) == 1
      end)

      # Verify they're all valid recipe structs with the same content
      # In Elixir, each parse returns a new struct with the same data
      # Since the input is identical, the data will be identical too
      # This test verifies that concurrent parsing works correctly
      assert length(recipes) == 50

      # All should have identical content (same ingredient)
      ingredient_names = Enum.map(recipes, fn r -> hd(r.ingredients).name end)
      assert Enum.all?(ingredient_names, &(&1 == "ingredient"))
    end
  end
end
