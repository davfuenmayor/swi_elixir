for backend <- [:port, :nif] do
  {:ok, session} = SWI.start_link(backend: backend)

  try do
    [%{"X" => 1_267_650_600_228_229_401_496_703_205_376}] =
      Enum.to_list(SWI.query(session, "X is 2^100"))

    {:ok, true} = SWI.call(session, "use_module(library(clpfd))")
    {:error, _} = SWI.call(session, "throw(expected_failure)")
    IO.puts("PASS SWI #{backend}: real runtime, bignums, CLPFD and errors")
  after
    SWI.stop(session)
  end
end
