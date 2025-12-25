defmodule CooklangEx.Native do
  @moduledoc false

  use Rustler,
    otp_app: :cooklang_ex,
    crate: "cooklang_nif"

  # NIF stubs - these are replaced when the NIF is loaded

  @doc false
  @spec parse(String.t(), boolean()) :: {:ok, String.t()} | {:error, String.t()}
  def parse(_input, _all_extensions), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  @spec parse_and_scale(String.t(), pos_integer(), boolean()) ::
          {:ok, String.t()} | {:error, String.t()}
  def parse_and_scale(_input, _target_servings, _all_extensions),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  @spec parse_aisle_config(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def parse_aisle_config(_input), do: :erlang.nif_error(:nif_not_loaded)
end
