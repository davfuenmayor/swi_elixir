defmodule ILPShowcase do
  @moduledoc "Project-authored orchestration for the ILP teaching examples."
  @project Path.expand("..", __DIR__)

  def learn(system, task, limit, backend \\ :port, sources \\ nil) do
    source_dir = write_sources(sources)

    {goal, kernel} =
      case system do
        :metagol ->
          {"metagol_ilp:learn_task(#{task},#{limit},Status,Program,Rows,Clauses,Trace)",
           "metagol:learn(_,_,_)"}

        :aleph ->
          {aleph_goal(task, limit, source_dir, sources), "aleph:induce(_)"}
      end

    try do
      {:ok, session} = SWI.start_link(backend: backend)

      try do
        :ok = SWI.load(session, Path.join(@project, "examples/#{system}_ilp.pl"))

        if system == :metagol do
          :ok = SWI.load(session, Path.join(source_dir, "metagol_tasks.pl"))
        end

        query =
          "statistics(inferences,Before),#{goal},statistics(inferences,After)," <>
            "Inferences is After-Before,predicate_property(#{kernel},file(Source))"

        {us, [answer]} =
          :timer.tc(fn ->
            SWI.query(session, query, timeout: 15_000) |> Enum.to_list()
          end)

        {:atom, source} = answer["Source"]
        true = source == Path.join(@project, "vendor/#{system}/#{system}.pl")
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
    after
      if sources, do: File.rm_rf!(source_dir)
    end
  end

  defp write_sources(nil), do: Path.join(@project, "examples")

  defp write_sources(sources) do
    dir = Path.join(System.tmp_dir!(), "swi-ilp-#{:erlang.phash2(sources)}")
    File.mkdir_p!(dir)

    Enum.each(sources, fn {name, source} ->
      source =
        if String.starts_with?(name, "aleph_") do
          [module, rest] = String.split(source, "\n", parts: 2)

          module <>
            "\n:- use_module('#{Path.join(@project, "vendor/aleph/aleph.pl")}').\n" <> rest
        else
          source
        end

      File.write!(Path.join(dir, name), source)
    end)

    dir
  end

  defp aleph_goal(task, limit, _source_dir, nil),
    do: "aleph_ilp:learn_task(#{task},#{limit},Program,Rows,Clauses,Bottom,Reduced,Trace)"

  defp aleph_goal(task, limit, source_dir, _sources) do
    file = if task == :trains, do: "aleph_trains.pl", else: "aleph_membership.pl"
    path = Path.join(source_dir, file) |> String.replace("'", "''")
    "aleph_ilp:learn_task(#{task},#{limit},Program,Rows,Clauses,Bottom,Reduced,Trace,'#{path}')"
  end

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
