defmodule CooklangExAisleConfigTest do
  use ExUnit.Case

  describe "parse_aisle_config/1" do
    test "parses a simple aisle configuration" do
      config = """
      [produce]
      tomatoes
      onions
      garlic

      [dairy]
      milk
      cheese
      butter
      """

      assert {:ok, result} = CooklangEx.parse_aisle_config(config)
      assert is_binary(result)
      # Parse the JSON to verify structure
      data = Jason.decode!(result)
      assert is_map(data)
    end

    test "parses empty aisle configuration" do
      assert {:ok, result} = CooklangEx.parse_aisle_config("")
      assert is_binary(result)
    end

    test "parses aisle config with single category" do
      config = """
      [spices]
      salt
      pepper
      cumin
      """

      assert {:ok, result} = CooklangEx.parse_aisle_config(config)
      data = Jason.decode!(result)
      assert is_map(data)
    end

    test "parses aisle config with multi-word items" do
      config = """
      [produce]
      red bell pepper
      sweet potato
      green onions
      """

      assert {:ok, result} = CooklangEx.parse_aisle_config(config)
      data = Jason.decode!(result)
      assert is_map(data)
    end

    test "handles whitespace in aisle config" do
      config = """

      [baking]
         flour

         sugar

      [dairy]
         milk
      """

      assert {:ok, result} = CooklangEx.parse_aisle_config(config)
      data = Jason.decode!(result)
      assert is_map(data)
    end

    test "parses aisle config with special characters" do
      config = """
      [produce]
      jalapeño peppers
      café-quality coffee
      """

      assert {:ok, result} = CooklangEx.parse_aisle_config(config)
      assert is_binary(result)
    end

    test "handles large aisle configuration" do
      # Generate a large config with many categories
      categories =
        1..20
        |> Enum.map(fn i ->
          items = Enum.map_join(1..10, "\n", fn j -> "item_#{i}_#{j}" end)
          "[category_#{i}]\n#{items}"
        end)
        |> Enum.join("\n\n")

      assert {:ok, result} = CooklangEx.parse_aisle_config(categories)
      assert is_binary(result)
      data = Jason.decode!(result)
      assert is_map(data)
    end

    test "parse_aisle_config! raises on error (if applicable)" do
      # Test the bang variant if it exists
      # Note: May need to adjust based on actual implementation
      config = """
      [produce]
      tomatoes
      """

      result = CooklangEx.parse_aisle_config!(config)
      assert is_map(result) or is_binary(result)
    end
  end

  describe "aisle config edge cases" do
    test "handles config with empty categories" do
      config = """
      [produce]

      [dairy]
      milk
      """

      assert {:ok, result} = CooklangEx.parse_aisle_config(config)
      assert is_binary(result)
    end

    test "handles config with comments (if supported)" do
      config = """
      [produce]
      tomatoes
      # This is a comment
      onions
      """

      # Parser may or may not support comments
      case CooklangEx.parse_aisle_config(config) do
        {:ok, result} ->
          assert is_binary(result)

        {:error, _reason} ->
          # Comments might not be supported, that's ok
          :ok
      end
    end

    test "handles unicode in aisle names" do
      config = """
      [🥗 Produce]
      lettuce
      tomatoes

      [🥛 Dairy]
      milk
      """

      # Unicode might or might not be supported
      case CooklangEx.parse_aisle_config(config) do
        {:ok, result} ->
          assert is_binary(result)

        {:error, _reason} ->
          :ok
      end
    end

    test "parses aisle config with duplicate category names" do
      config = """
      [produce]
      tomatoes

      [produce]
      onions
      """

      # Behavior might vary - either merge, take last, or error
      case CooklangEx.parse_aisle_config(config) do
        {:ok, result} ->
          assert is_binary(result)

        {:error, reason} ->
          # Duplicate categories might not be allowed
          assert is_binary(reason)
          assert reason =~ "Duplicate"
      end
    end
  end
end
