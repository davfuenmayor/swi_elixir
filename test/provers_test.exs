defmodule SWI.ProversTest do
  use ExUnit.Case, async: false

  setup do
    sessions =
      for backend <- [:port, :nif] do
        session = start_supervised!({SWI.Session, backend: backend}, id: backend)
        :ok = SWI.load(session, "examples/leanhat.pl")
        :ok = SWI.load(session, "examples/nanocop.pl")
        {backend, session}
      end

    %{sessions: sessions}
  end

  test "both Otten provers agree across backends on HT formulas", %{sessions: sessions} do
    for {formula, expected} <- [
          {"p => p", true},
          {"p ; ~p", false},
          {"(~ ~p) => p", false},
          {"(all X:p(X)) => ex Y:p(Y)", true},
          {"((p => q), (q => r)) => (p => r)", true},
          {"~p ; ~ ~p", true}
        ],
        {_, s} <- sessions,
        prover <- ["leanhat", "nanocop"] do
      quoted = :json.encode(formula) |> IO.iodata_to_binary()
      args = if prover == "nanocop", do: ",ht", else: ""

      assert SWI.call(s, "#{prover}:prove_text(#{quoted}#{args})", timeout: 2_000) ==
               {:ok, expected}
    end
  end

  test "intuitionistic mode differs from HT on weak excluded middle", %{sessions: sessions} do
    for {_, s} <- sessions do
      assert SWI.call(s, ~s|nanocop:prove_text("~p ; ~ ~p",intu)|) == {:ok, false}
      assert SWI.call(s, ~s|nanocop:prove_text("~p ; ~ ~p",ht)|) == {:ok, true}
      assert SWI.call(s, ~s|nanocop:prove_text("p => p",intu)|) == {:ok, true}
    end
  end

  test "nanoCoP scratch clauses belong to independent query engines", %{sessions: sessions} do
    nif = Keyword.fetch!(sessions, :nif)
    other = start_supervised!({SWI.Session, backend: :nif}, id: :other)

    tasks =
      for s <- [nif, other],
          do:
            Task.async(fn ->
              for _ <- 1..10 do
                assert SWI.call(s, ~s|nanocop:prove_text("((p=>q),(q=>r))=>(p=>r)", ht)|) ==
                         {:ok, true}
              end
            end)

    Enum.each(tasks, &Task.await/1)
  end
end
