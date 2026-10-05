defmodule CooklangEx.Diagnostic do
  @moduledoc """
  An error or a warning about a recipe, with its location in the source.

  Wraps `cooklang::error::SourceDiag`, so that an editor or a form can show
  each problem next to the text that caused it. Each label points at a part of
  the source. The first label is the main location.
  """

  alias CooklangEx.Diagnostic.Label

  @typedoc """
  Whether the problem makes the parse fail.

  Wraps `cooklang::error::Severity`. An `:error` makes the parse fail, and a
  `:warning` does not. The parser keeps going after an error, so one report can
  hold several errors and warnings.
  """
  @type severity :: :error | :warning

  @typedoc """
  The parser stage that found the problem.

  Wraps `cooklang::error::Stage`: `:parse` reads the syntax, and `:analysis`
  checks the parsed recipe.
  """
  @type stage :: :parse | :analysis

  @typedoc """
  An error or a warning, with the fields of `cooklang::error::SourceDiag`.

  `cause` is the lower-level error behind the diagnostic, for example the
  integer parse error behind "Error parsing integer number". It is `nil` if
  cooklang-rs has none.
  """
  @type t :: %__MODULE__{
          severity: severity(),
          stage: stage(),
          message: String.t(),
          cause: String.t() | nil,
          hints: [String.t()],
          labels: [Label.t()]
        }

  defstruct severity: :error, stage: :parse, message: "", cause: nil, hints: [], labels: []

  @doc false
  def from_map(data) when is_map(data) do
    %__MODULE__{
      severity: severity(data["severity"]),
      stage: stage(data["stage"]),
      message: data["message"] || "",
      cause: data["cause"],
      hints: data["hints"] || [],
      labels: Enum.map(data["labels"] || [], &Label.from_map/1)
    }
  end

  defp severity("warning"), do: :warning
  defp severity(_), do: :error

  defp stage("analysis"), do: :analysis
  defp stage(_), do: :parse
end

defmodule CooklangEx.Diagnostic.Label do
  @moduledoc """
  A part of the recipe source that a diagnostic points at.

  Wraps `cooklang::error::Label`, a span with an optional message. The byte
  offsets let code slice the source, for example to underline the span. The
  line and column let a person find the place without the source at hand.
  cooklang-rs has no line and column, so the binding computes them.

  - `start` and `end` - byte offsets into the source, `end` exclusive. If
    cooklang-rs points inside a multi-byte character, the binding moves the
    offset to a character boundary, so that a slice is always valid text.
  - `line` and `column` - 1-based position of `start`; `column` counts characters
  - `message` - an optional note about this span
  """

  @typedoc "A labelled span of the recipe source, with its line and column."
  @type t :: %__MODULE__{
          start: non_neg_integer(),
          end: non_neg_integer(),
          line: pos_integer(),
          column: pos_integer(),
          message: String.t() | nil
        }

  defstruct [:start, :end, :line, :column, :message]

  @doc false
  def from_map(data) when is_map(data) do
    %__MODULE__{
      start: data["start"],
      end: data["end"],
      line: data["line"],
      column: data["column"],
      message: data["message"]
    }
  end
end
