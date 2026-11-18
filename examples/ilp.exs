defmodule ILPShowcase do
  @moduledoc "Project-authored orchestration for the ILP teaching examples."
  @project Path.expand("..", __DIR__)

  def learn(system, task, limit, backend \\ :port, sources \\ nil) do
    with_sources(add_aleph_imports(sources), fn directory ->
      adapter = Path.join(@project, "examples/#{system}_ilp.pl")

      {goal, kernel, paths} =
        case system do
          :metagol ->
            {"metagol_ilp:learn_task(#{task},#{limit},Status,Program,Rows,Clauses,Trace)",
             "metagol:learn(_,_,_)", [adapter, Path.join(directory, "metagol_tasks.pl")]}

          :aleph ->
            {aleph_goal(task, limit, directory, sources), "aleph:induce(_)", [adapter]}
        end

      engine = quote_path(Path.join(@project, "vendor/#{system}/#{system}.pl"))

      query =
        "statistics(inferences,Before),#{goal},statistics(inferences,After)," <>
          "Inferences is After-Before,predicate_property(#{kernel},file(Source))," <>
          "same_file(Source,#{engine})"

      execute(backend, paths, query)
    end)
  end

  def run_inline(backend, sources, entries, goal) do
    with_sources(sources, fn directory ->
      paths = Enum.map(entries, &Path.join(directory, &1))
      execute(backend, paths, goal.(directory))
    end)
  end

  defp execute(backend, paths, goal) do
    {:ok, session} = SWI.start_link(backend: backend)

    try do
      Enum.each(paths, fn path -> :ok = SWI.load(session, path) end)

      {us, [answer]} =
        :timer.tc(fn ->
          SWI.query(session, goal, timeout: 15_000) |> Enum.to_list()
        end)

      true = answer["Inferences"] > 0

      rows =
        Enum.map(answer["Rows"], fn
          {:compound, "result", [{:atom, split}, goal, expected, actual]} ->
            %{split: split, goal: goal, expected: boolean(expected), actual: boolean(actual)}
        end)

      Map.merge(answer, %{"Rows" => rows, "Backend" => backend, "ElapsedUs" => us})
    after
      SWI.stop(session)
    end
  end

  defp with_sources(nil, run), do: run.(Path.join(@project, "examples"))

  defp with_sources(sources, run) do
    # Keep the path stable when the native runtime reconsults an edited task.
    directory = Path.join(System.tmp_dir!(), "swi-ilp-#{System.pid()}")
    File.mkdir_p!(directory)

    try do
      for {name, source} <- sources, do: File.write!(Path.join(directory, name), source)
      run.(directory)
    after
      File.rm_rf!(directory)
    end
  end

  defp add_aleph_imports(nil), do: nil

  defp add_aleph_imports(sources) do
    for {name, source} <- sources, into: %{} do
      if name in ["aleph_trains.pl", "aleph_membership.pl"] do
        [module, body] = String.split(source, "\n", parts: 2)
        engine = quote_path(Path.join(@project, "vendor/aleph/aleph.pl"))
        {name, Enum.join([module, ":- use_module(#{engine}).", body], "\n")}
      else
        {name, source}
      end
    end
  end

  defp aleph_goal(task, limit, _source_dir, nil),
    do: "aleph_ilp:learn_task(#{task},#{limit},Program,Rows,Clauses,Bottom,Reduced,Trace)"

  defp aleph_goal(task, limit, source_dir, _sources) do
    file = if task == :trains, do: "aleph_trains.pl", else: "aleph_membership.pl"
    path = quote_path(Path.join(source_dir, file))
    "aleph_ilp:learn_task(#{task},#{limit},Program,Rows,Clauses,Bottom,Reduced,Trace,#{path})"
  end

  defp quote_path(path), do: path |> :json.encode() |> IO.iodata_to_binary()

  def check!(answer) do
    [_ | _] = answer["Rows"]
    true = Enum.all?(answer["Rows"], &(&1.expected == &1.actual))
    answer
  end

  def scores(answer) do
    for split <- ["train", "test"] do
      rows = Enum.filter(answer["Rows"], &(&1.split == split))

      %{
        split: split,
        correct: Enum.count(rows, &(&1.expected == &1.actual)),
        total: length(rows),
        false_positives: Enum.count(rows, &(not &1.expected and &1.actual)),
        false_negatives: Enum.count(rows, &(&1.expected and not &1.actual))
      }
    end
  end

  defp boolean({:atom, "true"}), do: true
  defp boolean({:atom, "false"}), do: false
end
