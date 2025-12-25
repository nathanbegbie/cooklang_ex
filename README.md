# CooklangEx

[![Hex.pm](https://img.shields.io/hexpm/v/cooklang_ex.svg)](https://hex.pm/packages/cooklang_ex)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/cooklang_ex)

Elixir bindings for the canonical [Cooklang](https://cooklang.org/) parser, powered by
[cooklang-rs](https://github.com/cooklang/cooklang-rs) via Rustler NIFs.

## Features

- **Full Cooklang spec support** - Parse ingredients (`@`), cookware (`#`), timers (`~`), and metadata
- **Recipe scaling** - Automatically scale ingredient quantities to different serving sizes
- **Extensions** - Optional syntax extensions for advanced recipe formatting
- **Fast** - Native Rust performance via NIF bindings
- **Rich errors** - Detailed parse error messages with source locations

## Installation

Add `cooklang_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:cooklang_ex, "~> 0.1.0"}
  ]
end
```

### Requirements

- Elixir 1.14+
- Erlang/OTP 25+
- Rust 1.70+ (for compilation)

## Quick Start

```elixir
# Parse a simple recipe
recipe_text = """
>> servings: 2
>> time: 15 minutes

Crack @eggs{3} into a #bowl{large} and whisk until fluffy.

Heat @butter{2%tbsp} in a #pan{non-stick} over medium heat.

Pour egg mixture into pan and cook for ~{3%minutes}, stirring gently.

Season with @salt{} and @black pepper{} to taste.
"""

{:ok, recipe} = CooklangEx.parse(recipe_text)

# Access parsed data
recipe.metadata
# => %{"servings" => "2", "time" => "15 minutes"}

recipe.ingredients
# => [
#   %CooklangEx.Recipe.Ingredient{name: "eggs", quantity: %{value: 3.0, unit: nil}},
#   %CooklangEx.Recipe.Ingredient{name: "butter", quantity: %{value: 2.0, unit: "tbsp"}},
#   %CooklangEx.Recipe.Ingredient{name: "salt", quantity: nil},
#   %CooklangEx.Recipe.Ingredient{name: "black pepper", quantity: nil}
# ]

recipe.cookware
# => [
#   %CooklangEx.Recipe.Cookware{name: "bowl", quantity: %{value: "large"}},
#   %CooklangEx.Recipe.Cookware{name: "pan", quantity: %{value: "non-stick"}}
# ]

recipe.timers
# => [%CooklangEx.Recipe.Timer{quantity: %{value: 3.0, unit: "minutes"}}]
```

## Scaling Recipes

Scale recipes to different serving sizes:

```elixir
recipe_text = """
>> servings: 4

Mix @flour{400%g} with @water{250%ml}.
Add @yeast{1%packet} and @salt{1%tsp}.
"""

# Scale from 4 servings to 8
{:ok, scaled} = CooklangEx.parse_and_scale(recipe_text, 8)

# Quantities are automatically doubled
hd(scaled.ingredients).quantity.value
# => 800.0 (was 400)
```

## Cooklang Syntax Reference

### Ingredients
```
@ingredient           # Simple ingredient
@eggs{3}              # With quantity
@flour{200%g}         # With quantity and unit
@ground black pepper{} # Multi-word name
```

### Cookware
```
#pan                  # Simple cookware
#bowl{large}          # With size/description
#mixing bowl{}        # Multi-word name
```

### Timers
```
~{10%minutes}         # Duration timer
~{30%seconds}         # Another timer
~name{5%minutes}      # Named timer
```

### Metadata
```
>> servings: 4
>> source: https://example.com/recipe
>> time: 30 minutes
```

### Comments
```
-- This is a comment
Add @salt{} -- inline comment
```

### Steps
Steps are separated by blank lines:

```
First step here.

Second step here.

Third step here.
```

## API Reference

### `CooklangEx.parse/2`

Parse a Cooklang recipe string.

```elixir
{:ok, recipe} = CooklangEx.parse(text)
{:ok, recipe} = CooklangEx.parse(text, all_extensions: false)
```

### `CooklangEx.parse!/2`

Parse a recipe, raising on error.

```elixir
recipe = CooklangEx.parse!(text)
```

### `CooklangEx.parse_and_scale/3`

Parse and scale a recipe to target servings.

```elixir
{:ok, recipe} = CooklangEx.parse_and_scale(text, 8)
```

### `CooklangEx.ingredients/1`

Extract just the ingredients list.

```elixir
{:ok, ingredients} = CooklangEx.ingredients(text)
```

### `CooklangEx.cookware/1`

Extract just the cookware list.

```elixir
{:ok, cookware} = CooklangEx.cookware(text)
```

### `CooklangEx.metadata/1`

Extract just the metadata map.

```elixir
{:ok, metadata} = CooklangEx.metadata(text)
```

## Extensions

The parser supports several extensions to the base Cooklang specification.
By default, all extensions are enabled. Disable them with:

```elixir
CooklangEx.parse(text, all_extensions: false)
```

Extensions include:
- Multi-line steps
- Advanced units and quantities
- Sections and notes
- And more...

See the [cooklang-rs extensions documentation](https://github.com/cooklang/cooklang-rs/blob/main/extensions.md)
for details.

## Development

```bash
# Clone the repo
git clone https://github.com/yourusername/cooklang_ex
cd cooklang_ex

# Optional: if you're using asdf, set up your versioning
cp .tool-versions.example .tool-versions

# Install dependencies
mix deps.get

# Compile (this will also compile the Rust NIF)
mix compile

# Run tests
mix test
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Cooklang](https://cooklang.org/) - The recipe markup language
- [cooklang-rs](https://github.com/cooklang/cooklang-rs) - The canonical Rust parser
- [Rustler](https://github.com/rusterlium/rustler) - Safe Rust/Elixir bindings
