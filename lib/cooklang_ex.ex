defmodule CooklangEx do
  @moduledoc """
  Elixir bindings for the canonical Cooklang parser.

  This library wraps the `cooklang-rs` Rust crate via Rustler NIFs,
  providing a complete Cooklang parser with support for:

  - Parsing `.cook` recipe files
  - Recipe scaling (adjust servings)
  - Unit conversion
  - Rich error messages
  - Optional Cooklang extensions

  ## Quick Start

      iex> recipe_text = \"""
      ...> >> servings: 2
      ...>
      ...> Crack @eggs{3} into a #bowl{} and whisk.
      ...> Heat @butter{2%tbsp} in a #pan{large} over medium heat.
      ...> Cook for ~{5%minutes}.
      ...> \"""
      iex> {:ok, recipe} = CooklangEx.parse(recipe_text)
      iex> recipe.metadata["servings"]
      "2"
      iex> length(recipe.ingredients)
      2

  ## Scaling Recipes

      iex> recipe_text = \"""
      ...> >> servings: 2
      ...>
      ...> Crack @eggs{3} into a #bowl{} and whisk.
      ...> Heat @butter{2%tbsp} in a #pan{large} over medium heat.
      ...> Cook for ~{5%minutes}.
      ...> \"""
      iex> {:ok, scaled} = CooklangEx.parse_and_scale(recipe_text, 4)
      iex> Enum.find(scaled.ingredients, &(&1.name == "eggs")).quantity.value
      6.0

  ## Extensions

  The parser supports several extensions to the base Cooklang spec.
  These can be enabled/disabled via options:

      CooklangEx.parse(text, extensions: [:multiline_steps, :advanced_units])

  See `CooklangEx.Extensions` for available extensions.
  """

  alias CooklangEx.Native
  alias CooklangEx.Recipe

  @type parse_option ::
          {:extensions, [atom()]}
          | {:all_extensions, boolean()}

  @type scale_option ::
          {:target_servings, pos_integer()}

  @doc """
  Parse a Cooklang recipe string.

  Returns `{:ok, recipe}` on success or `{:error, reason}` on failure.

  ## Options

  - `:extensions` - List of extensions to enable (default: all)
  - `:all_extensions` - Enable all extensions (default: true)

  ## Examples

      iex> {:ok, recipe} = CooklangEx.parse("Add @salt{1%tsp} and @pepper{} to taste.")
      iex> is_struct(recipe, CooklangEx.Recipe)
      true
  """
  @spec parse(String.t(), [parse_option()]) :: {:ok, Recipe.t()} | {:error, String.t()}
  def parse(input, opts \\ []) when is_binary(input) do
    all_extensions = Keyword.get(opts, :all_extensions, true)

    case Native.parse(input, all_extensions) do
      {:ok, json} ->
        {:ok, Recipe.from_json(json)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Parse a Cooklang recipe string, raising on error.

  See `parse/2` for options.
  """
  @spec parse!(String.t(), [parse_option()]) :: Recipe.t()
  def parse!(input, opts \\ []) do
    case parse(input, opts) do
      {:ok, recipe} -> recipe
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Parse and scale a recipe to a target number of servings.

  The recipe must have a `servings` metadata field to enable scaling.

  ## Examples

      iex> text = \"""
      ...> >> servings: 2
      ...> Add @flour{200%g} to a #bowl{}.
      ...> \"""
      iex> {:ok, recipe} = CooklangEx.parse_and_scale(text, 4)
      iex> hd(recipe.ingredients).quantity.value
      400.0
  """
  @spec parse_and_scale(String.t(), pos_integer(), [parse_option()]) ::
          {:ok, Recipe.t()} | {:error, String.t()}
  def parse_and_scale(input, target_servings, opts \\ [])
      when is_binary(input) and is_integer(target_servings) and target_servings > 0 do
    all_extensions = Keyword.get(opts, :all_extensions, true)

    case Native.parse_and_scale(input, target_servings, all_extensions) do
      {:ok, json} ->
        {:ok, Recipe.from_json(json)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Parse and scale a recipe, raising on error.

  See `parse_and_scale/3` for details.
  """
  @spec parse_and_scale!(String.t(), pos_integer(), [parse_option()]) :: Recipe.t()
  def parse_and_scale!(input, target_servings, opts \\ []) do
    case parse_and_scale(input, target_servings, opts) do
      {:ok, recipe} -> recipe
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Extract just the ingredients from a recipe string.

  Useful when you only need an ingredient list without full parsing.

  ## Examples

      iex> {:ok, ingredients} = CooklangEx.ingredients("Add @eggs{3} and @milk{1%cup}.")
      iex> Enum.map(ingredients, & &1.name)
      ["eggs", "milk"]
  """
  @spec ingredients(String.t()) :: {:ok, [Recipe.Ingredient.t()]} | {:error, String.t()}
  def ingredients(input) when is_binary(input) do
    case Native.parse(input, true) do
      {:ok, json} ->
        recipe = Recipe.from_json(json)
        {:ok, recipe.ingredients}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Extract just the cookware from a recipe string.

  ## Examples

      iex> {:ok, cookware} = CooklangEx.cookware("Heat in a #pan{large} and transfer to a #bowl{}.")
      iex> Enum.map(cookware, & &1.name)
      ["pan", "bowl"]
  """
  @spec cookware(String.t()) :: {:ok, [Recipe.Cookware.t()]} | {:error, String.t()}
  def cookware(input) when is_binary(input) do
    case Native.parse(input, true) do
      {:ok, json} ->
        recipe = Recipe.from_json(json)
        {:ok, recipe.cookware}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Extract the metadata from a recipe string.

  ## Examples

      iex> text = \"""
      ...> >> source: https://example.com
      ...> >> servings: 4
      ...> >> time: 30 minutes
      ...> \"""
      iex> {:ok, metadata} = CooklangEx.metadata(text)
      iex> metadata["servings"]
      "4"
  """
  @spec metadata(String.t()) :: {:ok, map()} | {:error, String.t()}
  def metadata(input) when is_binary(input) do
    case Native.parse(input, true) do
      {:ok, json} ->
        recipe = Recipe.from_json(json)
        {:ok, recipe.metadata}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Parse an aisle configuration file.

  Aisle configuration files organize ingredients into shopping categories
  (aisles) for easier grocery shopping.

  Returns `{:ok, config}` on success or `{:error, reason}` on failure.

  ## Format

  Aisle configuration files use a simple INI-like format:

      [produce]
      tomatoes
      onions
      garlic

      [dairy]
      milk
      cheese
      butter

  ## Examples

      iex> config = \"""
      ...> [produce]
      ...> tomatoes
      ...> onions
      ...> \"""
      iex> {:ok, result} = CooklangEx.parse_aisle_config(config)
      iex> is_map(Jason.decode!(result))
      true
  """
  @spec parse_aisle_config(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def parse_aisle_config(input) when is_binary(input) do
    Native.parse_aisle_config(input)
  end

  @doc """
  Parse an aisle configuration file, raising on error.

  See `parse_aisle_config/1` for details.
  """
  @spec parse_aisle_config!(String.t()) :: map()
  def parse_aisle_config!(input) do
    case parse_aisle_config(input) do
      {:ok, json} -> Jason.decode!(json)
      {:error, reason} -> raise ArgumentError, reason
    end
  end
end
