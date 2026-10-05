defmodule CooklangEx.ParseError do
  @moduledoc """
  A failed parse, with each problem that cooklang-rs reported.

  Wraps the `cooklang::error::SourceReport` of a failed parse. The report keeps
  every problem with its position, so that all of them can be fixed in one go.

  - `message` - the messages of the errors, joined with newlines
  - `diagnostics` - all errors and warnings of the report, in report order, as
    `CooklangEx.Diagnostic` structs

  A failure that is not in the report, for example a scaling error, has a
  `message` and no `diagnostics`.

  `to_string/1` and string interpolation give `message`.
  """

  alias CooklangEx.Diagnostic

  @typedoc "A failed parse: the joined error messages and all diagnostics."
  @type t :: %__MODULE__{
          message: String.t(),
          diagnostics: [Diagnostic.t()]
        }

  defexception message: "", diagnostics: []

  @doc false
  def from_json(json_string) when is_binary(json_string) do
    data = Jason.decode!(json_string)

    %__MODULE__{
      message: data["message"] || "",
      diagnostics: Enum.map(data["diagnostics"] || [], &Diagnostic.from_map/1)
    }
  end
end

# The error value used to be the message string. Turning the error into a string
# gives that string, so logging and interpolation keep working.
defimpl String.Chars, for: CooklangEx.ParseError do
  def to_string(%CooklangEx.ParseError{message: message}), do: message
end
