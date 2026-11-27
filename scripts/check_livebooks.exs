# With no arguments, give each notebook its own VM.
defmodule CheckLivebooks do
  def run(notebook) do
    cells =
      notebook
      |> File.read!()
      |> String.replace("\r\n", "\n")
      |> then(&Regex.scan(~r/^```elixir[ \t]*\n(.*?)^```[ \t]*$/ms, &1, capture: :all_but_first))
      |> List.flatten()

    if cells != [] do
      IO.puts("Checking #{notebook}")

      Enum.reduce(cells, {[], Code.env_for_eval(file: notebook)}, fn code, {bindings, env} ->
        {_, bindings, env} =
          Code.eval_quoted_with_env(Code.string_to_quoted!(code), bindings, env)

        {bindings, env}
      end)
    end
  end
end

case System.argv() do
  [] ->
    for path <- Path.wildcard(Path.expand("../livebooks/**/*.livemd", __DIR__)) do
      {_, status} = System.cmd("elixir", [__ENV__.file, path], into: IO.stream())
      if status != 0, do: System.halt(status)
    end

  paths ->
    Enum.each(paths, &CheckLivebooks.run/1)
end
