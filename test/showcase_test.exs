Code.require_file("../examples/showcase.exs", __DIR__)

defmodule SWI.ShowcaseTest do
  use ExUnit.Case, async: false

  setup do
    sessions =
      for backend <- [:port, :nif] do
        session = start_supervised!({SWI.Session, backend: backend}, id: backend)
        :ok = SWI.load(session, "examples/prover_showcase.pl")
        {backend, session}
      end

    %{sessions: sessions}
  end

  test "tutorial and paper cases enter the real kernels and meet expectations", %{
    sessions: sessions
  } do
    for {_, session} <- sessions,
        example <- ProverShowcase.cases(),
        {prover, logic} <- example.modes do
      answer = ProverShowcase.run(session, prover, logic, example.formula)
      expected = Map.fetch!(example.expected, logic)
      assert answer["Result"] == {:atom, expected}, "#{example.name}: #{prover}/#{logic}"

      case {prover, expected} do
        {:nanocop, "proved"} -> assert [_ | _] = answer["Proof"]
        {:leanhat, "proved"} -> assert answer["Proof"] == {:atom, "unavailable"}
        {_, "exhausted"} -> assert answer["Proof"] == {:atom, "none"}
      end

      assert_unwrapped(session)
    end
  end

  test "reported clauses belong to the unchanged upstream kernels", %{sessions: sessions} do
    for {_, session} <- sessions,
        {prover, path} <- [
          {:leanhat, "vendor/leanHaT/leanhat_swi.pl"},
          {:nanocop, "vendor/nanoCoP-i-HT/nanocopi20_swi.pl"}
        ] do
      [row] = SWI.query(session, "prover_showcase:source(#{prover},File,Line)") |> Enum.to_list()
      assert row["File"] == {:atom, Path.expand(path)}
      assert row["Line"] > 0
    end
  end

  test "kernel exceptions propagate and diagnostic wrappers are removed", %{sessions: sessions} do
    for {_, session} <- sessions do
      # If the showcase bypassed the actual search, this injected failure could
      # not reach Elixir. Keep our independent test wrapper until final cleanup.
      {:ok, true} =
        SWI.call(
          session,
          "wrap_predicate(leanhat:prove(_,_,_,_),test_fault,_,throw(kernel_entered))"
        )

      try do
        goal = ProverShowcase.goal(:leanhat, :ht, ProverShowcase.chain(4))
        assert {:error, {:prolog, "kernel_entered"}} = SWI.call(session, goal)
        assert_unwrapped(session)
      after
        SWI.call(session, "unwrap_predicate(leanhat:prove/4,test_fault)")
      end

      assert %{"Result" => {:atom, "proved"}} =
               ProverShowcase.run(session, :leanhat, :ht, ProverShowcase.chain(4))
    end
  end

  test "timeout and early halt restore diagnostic wrappers and allow reuse", %{sessions: sessions} do
    for {_, session} <- sessions do
      # Controlled delay avoids relying on machine-specific search timings.
      {:ok, true} =
        SWI.call(
          session,
          "forall(true,wrap_predicate(nanocop:prove(_,_,_,_,_,_,_,_,_,_),test_delay,W,(sleep(1),call(W))))"
        )

      try do
        goal = ProverShowcase.goal(:nanocop, :intu, ProverShowcase.chain(4))
        assert SWI.call(session, goal, timeout: 20) == {:error, :timeout}
        assert_unwrapped(session)
      after
        SWI.call(session, "unwrap_predicate(nanocop:prove/10,test_delay)")
      end

      assert {:ok, true} =
               SWI.call(session, ProverShowcase.goal(:nanocop, :intu, ProverShowcase.chain(4)))

      assert_unwrapped(session)
      assert {:ok, true} = SWI.call(session, "nanocop:prove_text(\"p=>p\",intu)")
    end
  end

  defp assert_unwrapped(session) do
    assert SWI.call(
             session,
             "(prover_showcase:core(_,Head,_),current_predicate_wrapper(Head,showcase,_,_))"
           ) == {:ok, false}
  end
end
