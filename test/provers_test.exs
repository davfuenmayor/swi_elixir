defmodule SWI.ProversTest do
  use ExUnit.Case, async: false

  setup do
    sessions =
      for backend <- [:port, :nif] do
        session = start_supervised!({SWI.Session, backend: backend}, id: backend)

        for prover <- ~w(leancop leanhat ileancop) do
          :ok = SWI.load(session, "examples/#{prover}.pl")
        end

        {backend, session}
      end

    %{sessions: sessions}
  end

  test "provers agree on shared theorems and differ on excluded middle", %{sessions: sessions} do
    for {formula, expectations} <- [
          {"p => p", [leancop: true, leanhat: true, ileancop: true]},
          {"(all X:p(X)) => ex Y:p(Y)", [leancop: true, leanhat: true, ileancop: true]},
          {"((p => q), (q => r)) => (p => r)", [leancop: true, leanhat: true, ileancop: true]},
          {"p ; ~p", [leancop: true, leanhat: false, ileancop: false]},
          {"(~ ~p) => p", [leancop: true, leanhat: false, ileancop: false]},
          {"~p ; ~ ~p", [leancop: true, leanhat: true, ileancop: false]}
        ],
        {_, s} <- sessions,
        {prover, expected} <- expectations do
      quoted = :json.encode(formula) |> IO.iodata_to_binary()

      assert SWI.call(s, "#{prover}:prove_text(#{quoted})", timeout: 2_000) ==
               {:ok, expected}
    end
  end

  test "ileanCoP search state belongs to independent query engines", %{sessions: sessions} do
    nif = Keyword.fetch!(sessions, :nif)
    other = start_supervised!({SWI.Session, backend: :nif}, id: :other)

    tasks =
      for s <- [nif, other],
          do:
            Task.async(fn ->
              for _ <- 1..10 do
                assert SWI.call(s, ~s|ileancop:prove_text("((p=>q),(q=>r))=>(p=>r)")|) ==
                         {:ok, true}
              end
            end)

    Enum.each(tasks, &Task.await/1)
  end
end
