# Install the unpacked Hex source package as a consumer would.
[archive] = System.argv()
{:ok, outer} = :erl_tar.extract(String.to_charlist(archive), [:memory])
{_, contents} = List.keyfind(outer, ~c"contents.tar.gz", 0)

directory =
  Path.join(
    System.tmp_dir!(),
    "swi package #{System.pid()}-#{System.unique_integer([:positive])}"
  )

File.mkdir_p!(directory)

try do
  :ok =
    :erl_tar.extract({:binary, contents}, [:compressed, {:cwd, String.to_charlist(directory)}])

  Mix.install([{:swi_elixir, path: directory}])
  Code.require_file(Path.join(directory, "scripts/check_native.exs"))
after
  File.rm_rf!(directory)
end
