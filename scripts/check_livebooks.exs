# Evaluate every standalone Livebook twice in one VM. This does not test its UI.
project = Path.expand("..", __DIR__)

for notebook <- Path.wildcard(Path.join(project, "livebooks/*.livemd")) |> Enum.sort(),
    Path.basename(notebook) != "intro.livemd" do
  cells =
    notebook
    |> File.read!()
    |> then(&Regex.scan(~r/^```elixir\n(.*?)^```/ms, &1, capture: :all_but_first))
    |> List.flatten()

  if cells == [], do: raise("No code cells in #{notebook}")
  IO.puts("Checking #{Path.basename(notebook)} (two evaluations in one VM)")

  for _ <- 1..2 do
    Enum.reduce(cells, {[], Code.env_for_eval(file: notebook)}, fn code, {bindings, env} ->
      {_, bindings, env} =
        Code.eval_quoted_with_env(Code.string_to_quoted!(code), bindings, env)

      {bindings, env}
    end)
  end
end
