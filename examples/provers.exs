for backend <- [:port, :nif] do
  {:ok, session} = SWI.start_link(backend: backend)

  try do
    provers = ~w(leancop leanhat ileancop)
    for prover <- provers, do: :ok = SWI.load(session, "examples/#{prover}.pl")

    for formula <- ["p => p", "p ; ~p", "(~ ~p) => p", "(all X:p(X)) => ex Y:p(Y)", "~p ; ~ ~p"],
        prover <- provers do
      quoted = :json.encode(formula) |> IO.iodata_to_binary()
      IO.inspect({backend, prover, formula, SWI.call(session, "#{prover}:prove_text(#{quoted})")})
    end
  after
    SWI.stop(session)
  end
end
