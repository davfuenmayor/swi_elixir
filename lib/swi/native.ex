defmodule SWI.Native do
  @moduledoc false
  @on_load :load_nif

  def load_nif do
    path = :filename.join(:code.priv_dir(:swi_elixir), ~c"swi_nif")
    :erlang.load_nif(path, 0)
  end

  def open(_bridge), do: :erlang.nif_error(:nif_not_loaded)
  def request(_engine, _request), do: :erlang.nif_error(:nif_not_loaded)
  def stats, do: :erlang.nif_error(:nif_not_loaded)
  def close(_engine), do: :erlang.nif_error(:nif_not_loaded)
end
