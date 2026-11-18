# Install the unpacked Hex source package as a consumer would.
[archive] = System.argv()
{:ok, outer} = :erl_tar.extract(String.to_charlist(archive), [:memory])
{_, contents} = List.keyfind(outer, ~c"contents.tar.gz", 0)

scratch =
  Path.join(
    System.get_env("RUNNER_TEMP") || System.tmp_dir!(),
    "swi package #{System.pid()}-#{System.unique_integer([:positive])}"
  )

directory = Path.join(scratch, "source")
File.mkdir_p!(directory)
System.put_env("MIX_INSTALL_DIR", Path.join(scratch, "installs"))
IO.puts("Package check directory: #{scratch}")

:ok = :erl_tar.extract({:binary, contents}, [:compressed, {:cwd, String.to_charlist(directory)}])

# Windows holds the loaded NIF until this VM exits. The runner cleans its temp directory.
Mix.install([{:swi_elixir, path: directory}])
Code.require_file(Path.join(directory, "scripts/check_native.exs"))
