defmodule SWI.NativeFailureTest do
  use ExUnit.Case, async: false
  import SWI.TestSupport, only: [temporary: 1]

  setup_all do
    app = temporary("swi_elixir-0.1.0")
    ebin = Path.join(app, "ebin")
    priv = Path.join(app, "priv")
    File.mkdir_p!(priv)
    File.cp_r!(Path.dirname(:code.which(SWI)), ebin)
    File.cp!("priv/bridge.pl", Path.join(priv, "bridge.pl"))
    include = Path.join(:code.root_dir(), "usr/include")
    {flags, 0} = System.cmd("pkg-config", ["--cflags", "--libs", "swipl"])
    {libdir, 0} = System.cmd("pkg-config", ["--variable=libdir", "swipl"])

    args =
      [
        "-DSWI_NIF_TESTING",
        "-std=c11",
        "-O2",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-fPIC",
        "-shared",
        "-pthread",
        "-I#{include}",
        "c_src/swi_nif.c",
        "-o",
        Path.join(priv, "swi_nif.so"),
        "-ldl",
        "-Wl,-rpath,#{String.trim(libdir)}"
      ] ++ String.split(flags)

    {output, status} = System.cmd("cc", args, stderr_to_stdout: true)
    assert status == 0, output
    %{ebin: ebin}
  end

  test "native open preserves the Prolog exception and releases a failed resource", ctx do
    run_vm(ctx, """
    {:error, {:prolog, error}} = SWI.Native.open("/missing/native-bridge.pl")
    true = error =~ "existence_error"
    wait.(fn -> SWI.Native.stats().engines == 0 end)
    """)
  end

  for {point, reason} <- [{"resource", :out_of_memory}, {"engine", :engine_failed}] do
    @point point
    @reason reason
    test "#{point} allocation failure does not consume native capacity", ctx do
      run_vm(ctx, """
      System.put_env("SWI_NIF_FAIL", #{inspect(@point)})
      {:error, #{inspect(@reason)}} = SWI.Native.open(bridge)
      %{engines: 0} = SWI.Native.stats()
      System.delete_env("SWI_NIF_FAIL")
      {:ok, resource} = SWI.Native.open(bridge)
      :ok = SWI.Native.close(resource)
      """)
    end
  end

  test "response allocation failure returns an error without crashing the VM", ctx do
    run_vm(ctx, """
    {:ok, resource} = SWI.Native.open(bridge)
    System.put_env("SWI_NIF_FAIL", "binary")
    {:error, :out_of_memory} = SWI.Native.request(resource, ~s|{"op":"hello","timeout":1}|)
    System.delete_env("SWI_NIF_FAIL")
    {:ok, _} = SWI.Native.request(resource, ~s|{"op":"hello","timeout":1}|)
    :ok = SWI.Native.close(resource)
    %{engines: 0} = SWI.Native.stats()
    """)
  end

  test "failed destruction retains the live handle for a successful retry", ctx do
    run_vm(ctx, """
    {:ok, resource} = SWI.Native.open(bridge)
    System.put_env("SWI_NIF_FAIL", "destroy")
    {:error, :engine_destroy_failed} = SWI.Native.close(resource)
    %{engines: 1} = SWI.Native.stats()
    System.delete_env("SWI_NIF_FAIL")
    {:ok, _} = SWI.Native.request(resource, ~s|{"op":"hello","timeout":1}|)
    :ok = SWI.Native.close(resource)
    :ok = SWI.Native.close(resource)
    %{engines: 0} = SWI.Native.stats()
    """)
  end

  test "query creation and term allocation failures unwind the request frame", ctx do
    run_vm(ctx, """
    {:ok, resource} = SWI.Native.open(bridge)
    for {point, expected} <- [{"query", :query_failed}, {"terms", :out_of_memory}] do
      System.put_env("SWI_NIF_FAIL", point)
      {:error, ^expected} = SWI.Native.request(resource, ~s|{"op":"hello","timeout":1}|)
      System.delete_env("SWI_NIF_FAIL")
      {:ok, _} = SWI.Native.request(resource, ~s|{"op":"hello","timeout":1}|)
    end
    :ok = SWI.Native.close(resource)
    %{engines: 0} = SWI.Native.stats()
    """)
  end

  test "failed engine restoration retains the handle for cleanup", ctx do
    run_vm(ctx, """
    {:ok, resource} = SWI.Native.open(bridge)
    System.put_env("SWI_NIF_FAIL", "restore")
    {:error, :engine_restore_failed} = SWI.Native.close(resource)
    %{engines: 1} = SWI.Native.stats()
    System.delete_env("SWI_NIF_FAIL")
    :ok = SWI.Native.close(resource)
    %{engines: 0} = SWI.Native.stats()
    """)
  end

  test "native admission is bounded and explicit close restores capacity", ctx do
    run_vm(ctx, """
    resources = for _ <- 1..SWI.Native.stats().capacity do
      {:ok, resource} = SWI.Native.open(bridge)
      resource
    end
    {:error, :native_capacity} = SWI.Native.open(bridge)
    Process.flag(:trap_exit, true)
    {:error, :native_capacity} = SWI.start_link(backend: :nif)
    Enum.each(resources, fn resource -> :ok = SWI.Native.close(resource) end)
    %{engines: 0, reapers: 0, quarantined: 0} = SWI.Native.stats()
    """)
  end

  test "reaper creation failure retains bounded, observable quarantined handles", ctx do
    run_vm(ctx, """
    System.put_env("SWI_NIF_FAIL", "reaper")
    {owner, ref} = spawn_monitor(fn ->
      resources = for _ <- 1..SWI.Native.stats().capacity do
        {:ok, resource} = SWI.Native.open(bridge)
        resource
      end
      send(parent, {:resources, length(resources)})
    end)
    receive do {:resources, 64} -> :ok after 2_000 -> raise "resources not opened" end
    receive do {:DOWN, ^ref, :process, ^owner, :normal} -> :ok after 2_000 -> raise "owner alive" end
    wait.(fn -> SWI.Native.stats().quarantined == 64 end)
    %{engines: 64, reapers: 0} = SWI.Native.stats()
    {:error, :native_capacity} = SWI.Native.open(bridge)
    """)
  end

  test "blocked GC handlers retain their slots and cannot cause unbounded admission", ctx do
    run_vm(ctx, """
    {owner, ref} = spawn_monitor(fn ->
      resources = for _ <- 1..2 do
        {:ok, resource} = SWI.Native.open(bridge)
        {:ok, _} = SWI.Native.request(resource, ~s|{"op":"open","goal":"setup_call_cleanup(true,repeat,(repeat,fail))"}|)
        {:ok, _} = SWI.Native.request(resource, ~s|{"op":"next","timeout":1}|)
        resource
      end
      send(parent, {:resources, length(resources)})
    end)
    receive do {:resources, 2} -> :ok after 2_000 -> raise "resources not opened" end
    receive do {:DOWN, ^ref, :process, ^owner, :normal} -> :ok after 2_000 -> raise "owner alive" end
    wait.(fn -> SWI.Native.stats().reapers == 2 end)
    resources = for _ <- 1..62 do
      {:ok, resource} = SWI.Native.open(bridge)
      resource
    end
    {:error, :native_capacity} = SWI.Native.open(bridge)
    Enum.each(resources, fn resource -> :ok = SWI.Native.close(resource) end)
    %{engines: 2, reapers: 2, quarantined: 0} = SWI.Native.stats()
    # The disposable VM terminates both deliberately blocked reapers on exit.
    """)
  end

  test "bursts of slow GC cleanup reclaim engines with bounded reaper work", ctx do
    output =
      run_vm(ctx, """
      {:ok, first} = SWI.Native.open(bridge)
      :ok = SWI.Native.close(first)
      measurements = fn ->
        {:ok, status} = File.read("/proc/self/status")
        [_, rss] = Regex.run(~r/^VmRSS:\\s+(\\d+) kB/m, status)
        [_, threads] = Regex.run(~r/^Threads:\\s+(\\d+)/m, status)
        %{rss_kb: String.to_integer(rss), threads: String.to_integer(threads)}
      end
      baseline = measurements.()
      samples = for _ <- 1..3 do
        {owner, ref} = spawn_monitor(fn ->
          resources = for _ <- 1..SWI.Native.stats().capacity do
            {:ok, resource} = SWI.Native.open(bridge)
            {:ok, _} = SWI.Native.request(resource, ~s|{"op":"open","goal":"setup_call_cleanup(true,repeat,sleep(0.1))"}|)
            {:ok, _} = SWI.Native.request(resource, ~s|{"op":"next","timeout":1}|)
            resource
          end
          send(parent, {:ready, length(resources)})
          receive do :drop -> length(resources) end
        end)
        receive do {:ready, 64} -> :ok after 5_000 -> raise "resources not ready" end
        send(owner, :drop)
        receive do {:DOWN, ^ref, :process, ^owner, :normal} -> :ok after 5_000 -> raise "owner alive" end
        peak = measurements.()
        true = SWI.Native.stats().reapers <= 64
        wait.(fn -> SWI.Native.stats().engines == 0 end)
        wait.(fn -> measurements.().threads <= baseline.threads + 2 end)
        %{peak: peak, reclaimed: measurements.()}
      end
      IO.inspect(%{baseline: baseline, samples: samples}, label: "gc_measurements", limit: :infinity, width: :infinity)
      %{engines: 0, quarantined: 0} = SWI.Native.stats()
      """)

    assert output =~ "gc_measurements"
    IO.puts(Enum.find(String.split(output, "\n"), &String.starts_with?(&1, "gc_measurements")))
  end

  defp run_vm(ctx, script) do
    prelude = """
    Application.load(:swi_elixir)
    bridge = Path.join(:code.priv_dir(:swi_elixir), "bridge.pl")
    parent = self()
    wait = fn fun ->
      deadline = System.monotonic_time(:millisecond) + 5_000
      poll = fn poll ->
        if fun.() do
          :ok
        else
          if System.monotonic_time(:millisecond) >= deadline, do: raise("condition timed out")
          Process.sleep(10)
          poll.(poll)
        end
      end
      poll.(poll)
    end
    """

    {output, status} =
      System.cmd(
        "elixir",
        ["-pa", ctx.ebin, "-e", prelude <> script <> "\nIO.puts(\"verified\")"],
        env: [{"ERL_FLAGS", "+S 1:1"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "verified"
    output
  end
end
