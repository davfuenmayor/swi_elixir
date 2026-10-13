defmodule SWI.Bench do
  def measure(fun, n) do
    times = for _ <- 1..n, do: elem(:timer.tc(fun), 0)
    sorted = Enum.sort(times)
    %{median_us: Enum.at(sorted, div(n, 2)), p95_us: Enum.at(sorted, min(n - 1, trunc(n * 0.95)))}
  end

  def rss(pid) do
    case File.read("/proc/#{pid}/status") do
      {:ok, text} ->
        case Regex.run(~r/^VmRSS:\s+(\d+) kB/m, text) do
          [_, kb] -> String.to_integer(kb)
          _ -> nil
        end

      _ ->
        nil
    end
  end
end

IO.inspect(
  %{
    elixir: System.version(),
    otp: :erlang.system_info(:otp_release),
    swi: System.cmd("swipl", ["--version"]) |> elem(0) |> String.trim()
  },
  label: "versions"
)

for backend <- [:port, :nif] do
  start = fn ->
    {:ok, s} = SWI.start_link(backend: backend)
    {:ok, true} = SWI.call(s, "true")
    SWI.stop(s)
  end

  {first_us, :ok} = :timer.tc(start)
  startup = SWI.Bench.measure(start, 10)

  {:ok, s} = SWI.start_link(backend: backend)

  try do
    :ok = SWI.load(s, "examples/leanhat.pl")
    :ok = SWI.load(s, "examples/nanocop.pl")

    workloads = [
      {"tiny success", "true"},
      {"symbolic unification", "X=f(a,g(b),[1,2,3]), Y=X"},
      {"100 answers", "between(1,100,X)"},
      {"leanHaT quantified",
       ~s|once(leanhat:prove_text("((all X:(p(X)=>q(X))), (all Y:p(Y))) => all Z:q(Z)"))|},
      {"nanoCoP HT quantified",
       ~s|once(nanocop:prove_text("((all X:(p(X)=>q(X))), (all Y:p(Y))) => all Z:q(Z)",ht))|}
    ]

    for {label, goal} <- workloads do
      # Warm up autoloading before measuring persistent requests.
      [_ | _] = Enum.to_list(SWI.query(s, goal))
      result = SWI.Bench.measure(fn -> [_ | _] = Enum.to_list(SWI.query(s, goal)) end, 50)
      IO.inspect({backend, label, result})
    end

    timeout =
      SWI.Bench.measure(fn -> {:error, :timeout} = SWI.call(s, "repeat,fail", timeout: 20) end, 5)

    child_rss =
      if backend == :port do
        {:os_pid, pid} = Port.info(:sys.get_state(s).transport, :os_pid)
        SWI.Bench.rss(pid)
      end

    IO.inspect(%{
      backend: backend,
      first_start_query_stop_us: first_us,
      repeated_start_query_stop: startup,
      timeout: timeout,
      beam_rss_kb: SWI.Bench.rss(System.pid()),
      swipl_rss_kb: child_rss
    })

    if backend == :port, do: IO.inspect(SWI.call(s, "halt(7)"), label: "isolated exit")
  after
    SWI.stop(s)
  end
end
