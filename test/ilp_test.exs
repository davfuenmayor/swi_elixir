Code.require_file("../examples/ilp.exs", __DIR__)

defmodule SWI.ILPTest do
  use ExUnit.Case, async: false

  @tasks [
    {:metagol, :grandparent, 3, 3, 6, 3},
    {:metagol, :ancestor, 2, 2, 3, 4},
    {:metagol, :droplasts, 3, 3, 3, 4},
    {:aleph, :trains, 4, 1, 10, 4},
    {:aleph, :membership, 4, 2, 25, 4}
  ]

  test "ILP and prover showcases coexist in the shared native runtime" do
    s = start_supervised!({SWI.Session, backend: :nif})

    for source <- ["prover_showcase", "metagol_ilp", "aleph_ilp"] do
      assert :ok = SWI.load(s, "examples/#{source}.pl")
    end

    assert :ok = SWI.load(s, "examples/metagol_tasks.pl")

    assert {:ok, true} =
             SWI.call(
               s,
               ~s|prover_showcase:run(leanhat,ht,"p=>p",proved,_,_,_)|
             )

    assert {:ok, true} = SWI.call(s, "metagol_ilp:learn_task(grandparent,3,learned,_,_,3,_)")
    assert {:ok, true} = SWI.call(s, "aleph_ilp:learn_task(trains,4,_,_,1,_,_,_)")
  end

  test "real learned programs fit training and withheld cases through both backends" do
    for {system, task, budget, clauses, training, holdout} <- @tasks do
      [port, nif] =
        for backend <- [:port, :nif] do
          row = ILPShowcase.learn(system, task, budget, backend) |> ILPShowcase.check!()
          assert row["Clauses"] == clauses

          assert [%{correct: ^training, total: ^training}, %{correct: ^holdout, total: ^holdout}] =
                   ILPShowcase.scores(row)

          assert row["Program"] != ""
          assert row["Trace"] != ""
          row
        end

      assert port["Rows"] == nif["Rows"]
    end
  end

  test "restricted bias gives Metagol exhaustion and Aleph memorization" do
    for backend <- [:port, :nif] do
      result = ILPShowcase.learn(:metagol, :grandparent, 2, backend)
      assert result["Status"] == {:atom, "no_hypothesis"}
      assert result["Rows"] == []
      assert result["Clauses"] == 0

      result = ILPShowcase.learn(:aleph, :trains, 3, backend)
      assert result["Clauses"] == 5

      assert [%{correct: 10, total: 10}, %{correct: 3, total: 4, false_negatives: 1}] =
               ILPShowcase.scores(result)

      assert [%{goal: "eastbound(probe_yes)", expected: true, actual: false}] =
               Enum.reject(result["Rows"], &(&1.expected == &1.actual))
    end
  end

  test "repeated native learning does not retain targets or accumulate initialization clauses" do
    s = start_supervised!({SWI.Session, backend: :nif})

    for _ <- 1..3 do
      ILPShowcase.learn(:metagol, :droplasts, 3, :nif) |> ILPShowcase.check!()
      ILPShowcase.learn(:aleph, :membership, 4, :nif) |> ILPShowcase.check!()
      assert SWI.call(s, "metagol_ilp:droplasts([[a,b]],[[a]])") == {:ok, false}
      assert SWI.call(s, "aleph_membership:mem(a,[a])") == {:ok, false}
      assert SWI.call(s, "clause(aleph_membership:induce,_,_)") == {:ok, false}

      assert [%{"N" => 2}] =
               SWI.query(s, "findall(1,metagol:ibk([map|_],_,_),L),length(L,N)")
               |> Enum.map(&Map.take(&1, ["N"]))
    end
  end

  test "learner errors reach Elixir and adapter cleanup allows a fresh experiment" do
    for backend <- [:port, :nif],
        {system, head, pi, goal, target} <- [
          {:metagol, "metagol:learn(_,_,_)", "metagol:learn/3",
           "metagol_ilp:learn_task(grandparent,3,_,_,_,_,_)",
           "metagol_ilp:grandparent(ann,amelia)"},
          {:aleph, "aleph:induce(_)", "aleph:induce/1",
           "aleph_ilp:learn_task(trains,4,_,_,_,_,_,_)", "aleph_trains:eastbound(east1)"}
        ] do
      s = start_supervised!({SWI.Session, backend: backend}, id: {backend, system})
      :ok = SWI.load(s, "examples/#{system}_ilp.pl")

      if system == :metagol do
        :ok = SWI.load(s, "examples/metagol_tasks.pl")
      end

      assert {:ok, true} =
               SWI.call(
                 s,
                 "wrap_predicate(#{head},ilp_fault,_,throw(learner_entered))"
               )

      try do
        assert {:error, {:prolog, "learner_entered"}} = SWI.call(s, goal)
      after
        assert {:ok, true} = SWI.call(s, "unwrap_predicate(#{pi},ilp_fault)")
      end

      assert {:ok, true} = SWI.call(s, goal)
      assert SWI.call(s, target) == {:ok, false}
    end
  end

  test "Metagol restores declared primitives and search settings after errors and timeouts" do
    for backend <- [:port, :nif] do
      s = start_supervised!({SWI.Session, backend: backend}, id: backend)
      :ok = SWI.load(s, "examples/metagol_ilp.pl")
      :ok = SWI.load(s, "examples/metagol_tasks.pl")
      assert {:ok, true} = SWI.call(s, "metagol:options")
      [before] = SWI.query(s, "metagol_ilp:save_settings(S)") |> Enum.to_list()

      assert {:ok, true} =
               SWI.call(
                 s,
                 "forall(true,wrap_predicate(metagol:learn(_,_,_),ilp_delay,W,(sleep(1),call(W))))"
               )

      try do
        assert SWI.call(s, "metagol_ilp:learn_task(droplasts,3,_,_,_,_,_)", timeout: 20) ==
                 {:error, :timeout}
      after
        assert {:ok, true} = SWI.call(s, "unwrap_predicate(metagol:learn/3,ilp_delay)")
      end

      [after_timeout] = SWI.query(s, "metagol_ilp:save_settings(S)") |> Enum.to_list()
      assert after_timeout == before
    end
  end

  test "Aleph timeout removes partially installed target clauses and permits reuse" do
    for backend <- [:port, :nif] do
      s = start_supervised!({SWI.Session, backend: backend}, id: backend)
      :ok = SWI.load(s, "examples/aleph_ilp.pl")

      assert {:ok, true} =
               SWI.call(
                 s,
                 "forall(true,wrap_predicate(aleph:induce(_),ilp_delay,W," <>
                   "(assertz(aleph_trains:eastbound(timeout_probe)),sleep(1),call(W))))"
               )

      try do
        assert SWI.call(s, "aleph_ilp:learn_task(trains,4,_,_,_,_,_,_)", timeout: 100) ==
                 {:error, :timeout}
      after
        assert {:ok, true} = SWI.call(s, "unwrap_predicate(aleph:induce/1,ilp_delay)")
      end

      assert SWI.call(s, "aleph_trains:eastbound(timeout_probe)") == {:ok, false}
      assert {:ok, true} = SWI.call(s, "aleph_ilp:learn_task(trains,4,_,_,1,_,_,_)")
      assert SWI.call(s, "aleph_trains:eastbound(east1)") == {:ok, false}
    end
  end
end
