defmodule SWI.Native do
  @moduledoc false
  Code.ensure_compiled!(SWI.Runtime)
  @on_load :load_nif

  def load_nif do
    path = SWI.Runtime.nif() |> String.to_charlist() |> :filename.nativename()
    :erlang.load_nif(path, SWI.Runtime.home())
  end

  def open(_bridge), do: :erlang.nif_error(:nif_not_loaded)
  def request(_engine, _request), do: :erlang.nif_error(:nif_not_loaded)
  def stats, do: :erlang.nif_error(:nif_not_loaded)
  def close(_engine), do: :erlang.nif_error(:nif_not_loaded)
end
