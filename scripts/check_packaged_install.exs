# Verify the unpacked Hex source package without SWI or compilers on PATH.
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

  tools = Path.join(directory, "system tools")
  File.mkdir_p!(tools)

  if :os.type() != {:win32, :nt} do
    File.cp!(System.find_executable("kill"), Path.join(tools, "kill"))
  end

  code = """
  System.put_env("PATH", #{inspect(tools)})
  Mix.install([{:swi_elixir, path: #{inspect(directory)}}])
  Code.require_file(#{inspect(Path.join(directory, "scripts/check_native.exs"))})
  """

  executable = System.find_executable("elixir") || raise "Elixir executable not found"

  {output, status} =
    System.cmd(executable, ["--erl", "+S 2:2", "-e", code], stderr_to_stdout: true)

  IO.write(output)
  if status != 0, do: raise("Unpacked package installation failed")
after
  File.rm_rf!(directory)
end
