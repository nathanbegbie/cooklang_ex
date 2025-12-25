defmodule CooklangEx.Recipe do
  @moduledoc """
  Represents a parsed Cooklang recipe.

  A recipe contains:
  - `metadata` - Key-value pairs from `>> key: value` lines
  - `ingredients` - List of ingredients marked with `@`
  - `cookware` - List of cookware marked with `#`
  - `timers` - List of timers marked with `~`
  - `steps` - List of cooking steps (paragraphs)
  """

  alias CooklangEx.Recipe.{Ingredient, Cookware, Timer, Step, Quantity}

  @type t :: %__MODULE__{
          metadata: map(),
          ingredients: [Ingredient.t()],
          cookware: [Cookware.t()],
          timers: [Timer.t()],
          steps: [Step.t()],
          warnings: [String.t()]
        }

  defstruct metadata: %{},
            ingredients: [],
            cookware: [],
            timers: [],
            steps: [],
            warnings: []

  @doc false
  def from_json(json_string) when is_binary(json_string) do
    data = Jason.decode!(json_string)
    from_map(data)
  end

  @doc false
  def from_map(data) when is_map(data) do
    %__MODULE__{
      metadata: data["metadata"] || %{},
      ingredients: parse_ingredients(data["ingredients"] || []),
      cookware: parse_cookware(data["cookware"] || []),
      timers: parse_timers(data["timers"] || []),
      steps: parse_steps(data["sections"] || data["steps"] || []),
      warnings: data["warnings"] || []
    }
  end

  defp parse_ingredients(ingredients) do
    Enum.map(ingredients, &Ingredient.from_map/1)
  end

  defp parse_cookware(cookware) do
    Enum.map(cookware, &Cookware.from_map/1)
  end

  defp parse_timers(timers) do
    Enum.map(timers, &Timer.from_map/1)
  end

  defp parse_steps(sections) when is_list(sections) do
    sections
    |> Enum.flat_map(fn section ->
      case section do
        %{"content" => content} when is_list(content) ->
          Enum.map(content, &Step.from_map/1)

        %{"items" => items} when is_list(items) ->
          Enum.flat_map(items, fn item ->
            case item do
              %{"type" => "step"} -> [Step.from_map(item)]
              _ -> []
            end
          end)

        step when is_map(step) ->
          [Step.from_map(step)]

        _ ->
          []
      end
    end)
  end
end

defmodule CooklangEx.Recipe.Quantity do
  @moduledoc """
  Represents a quantity with an optional value and unit.

  Examples:
  - `@eggs{3}` -> value: 3, unit: nil
  - `@flour{200%g}` -> value: 200, unit: "g"
  - `@salt{}` -> value: nil, unit: nil (some amount)
  """

  @type t :: %__MODULE__{
          value: number() | String.t() | nil,
          unit: String.t() | nil
        }

  defstruct value: nil, unit: nil

  @doc false
  def from_map(nil), do: nil

  def from_map(data) when is_map(data) do
    value =
      case data["value"] do
        %{"Number" => n} -> n
        %{"Range" => %{"start" => s, "end" => e}} -> {s, e}
        %{"Text" => t} -> t
        n when is_number(n) -> n
        other -> other
      end

    %__MODULE__{
      value: value,
      unit: data["unit"]
    }
  end
end

defmodule CooklangEx.Recipe.Ingredient do
  @moduledoc """
  Represents an ingredient in a recipe.

  Ingredients are marked with `@` in Cooklang:
  - `@salt` - just the name
  - `@eggs{3}` - with quantity
  - `@flour{200%g}` - with quantity and unit
  - `@ground black pepper{}` - multi-word name
  """

  alias CooklangEx.Recipe.Quantity

  @type t :: %__MODULE__{
          name: String.t(),
          quantity: Quantity.t() | nil,
          note: String.t() | nil
        }

  defstruct name: "", quantity: nil, note: nil

  @doc false
  def from_map(data) when is_map(data) do
    %__MODULE__{
      name: data["name"] || "",
      quantity: Quantity.from_map(data["quantity"]),
      note: data["note"]
    }
  end
end

defmodule CooklangEx.Recipe.Cookware do
  @moduledoc """
  Represents cookware in a recipe.

  Cookware is marked with `#` in Cooklang:
  - `#pan` - just the name
  - `#pan{large}` - with a size/description
  - `#mixing bowl{}` - multi-word name
  """

  alias CooklangEx.Recipe.Quantity

  @type t :: %__MODULE__{
          name: String.t(),
          quantity: Quantity.t() | nil,
          note: String.t() | nil
        }

  defstruct name: "", quantity: nil, note: nil

  @doc false
  def from_map(data) when is_map(data) do
    %__MODULE__{
      name: data["name"] || "",
      quantity: Quantity.from_map(data["quantity"]),
      note: data["note"]
    }
  end
end

defmodule CooklangEx.Recipe.Timer do
  @moduledoc """
  Represents a timer in a recipe.

  Timers are marked with `~` in Cooklang:
  - `~{10%minutes}` - duration with unit
  - `~{30%seconds}` - shorter duration
  """

  alias CooklangEx.Recipe.Quantity

  @type t :: %__MODULE__{
          name: String.t() | nil,
          quantity: Quantity.t() | nil
        }

  defstruct name: nil, quantity: nil

  @doc false
  def from_map(data) when is_map(data) do
    %__MODULE__{
      name: data["name"],
      quantity: Quantity.from_map(data["quantity"])
    }
  end
end

defmodule CooklangEx.Recipe.Step do
  @moduledoc """
  Represents a cooking step in a recipe.

  Steps are separated by blank lines in Cooklang. Each step
  contains a list of items which can be text, ingredients,
  cookware, or timers.
  """

  @type item ::
          {:text, String.t()}
          | {:ingredient, non_neg_integer()}
          | {:cookware, non_neg_integer()}
          | {:timer, non_neg_integer()}

  @type t :: %__MODULE__{
          items: [item()],
          raw_text: String.t() | nil
        }

  defstruct items: [], raw_text: nil

  @doc false
  def from_map(data) when is_map(data) do
    items =
      (data["items"] || data["content"] || [])
      |> Enum.map(&parse_item/1)
      |> Enum.reject(&is_nil/1)

    %__MODULE__{
      items: items,
      raw_text: data["raw_text"]
    }
  end

  defp parse_item(%{"type" => "text", "value" => value}), do: {:text, value}
  defp parse_item(%{"type" => "ingredient", "index" => idx}), do: {:ingredient, idx}
  defp parse_item(%{"type" => "cookware", "index" => idx}), do: {:cookware, idx}
  defp parse_item(%{"type" => "timer", "index" => idx}), do: {:timer, idx}
  defp parse_item(%{"Text" => value}), do: {:text, value}
  defp parse_item(%{"Ingredient" => %{"index" => idx}}), do: {:ingredient, idx}
  defp parse_item(%{"Cookware" => %{"index" => idx}}), do: {:cookware, idx}
  defp parse_item(%{"Timer" => %{"index" => idx}}), do: {:timer, idx}
  defp parse_item(text) when is_binary(text), do: {:text, text}
  defp parse_item(_), do: nil
end
