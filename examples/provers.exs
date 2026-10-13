for backend <- [:port, :nif] do
  {:ok, session} = SWI.start_link(backend: backend)

  try do
    :ok = SWI.load(session, "examples/leanhat.pl")
    :ok = SWI.load(session, "examples/nanocop.pl")

    for formula <- ["p => p", "p ; ~p", "(~ ~p) => p", "(all X:p(X)) => ex Y:p(Y)", "~p ; ~ ~p"],
        prover <- ["leanhat:prove_text", "nanocop:prove_text"] do
      args = if prover == "nanocop:prove_text", do: ", ht", else: ""
      quoted = :json.encode(formula) |> IO.iodata_to_binary()

      IO.inspect(
        {backend, prover, formula,
         SWI.call(session, "#{prover}(#{quoted}#{args})", timeout: 2_000)}
      )
    end
  after
    SWI.stop(session)
  end
end
