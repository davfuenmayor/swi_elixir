# Evaluate every standalone Livebook twice in one VM. This does not test its UI.
project = Path.expand("..", __DIR__)
System.put_env("SWI_ELIXIR_PATH", project)

for notebook <- Path.wildcard(Path.join(project, "livebooks/*.livemd")) |> Enum.sort() do
  cells =
    notebook
    |> File.read!()
    |> then(&Regex.scan(~r/^```elixir\n(.*?)^```/ms, &1, capture: :all_but_first))
    |> List.flatten()

  if cells == [], do: raise("No code cells in #{notebook}")
  IO.puts("Checking #{Path.basename(notebook)} (two evaluations in one VM)")

  for _ <- 1..2 do
    Enum.reduce(cells, [], fn code, bindings ->
      {_, bindings} = Code.eval_string(code, bindings, file: notebook)
      bindings
    end)
  end
end
