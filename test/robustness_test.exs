defmodule SWI.RobustnessTest do
  use ExUnit.Case, async: false
  import SWI.TestSupport
  import ExUnit.CaptureLog

  for backend <- [:port, :nif] do
    describe "#{backend} cleanup budgets" do
      setup do
        %{
          session:
            start_supervised!({SWI.Session, backend: unquote(backend), cleanup_timeout: 50})
        }
      end

      test "early halt waits for finite cleanup and permits another query", %{session: s} do
        {elapsed, result} = :timer.tc(fn -> SWI.call(s, slow_cleanup(), timeout: 10) end)
        assert result == {:ok, true}
        assert elapsed < 1_500_000
        assert SWI.call(s, "true") == {:ok, true}
      end

      test "owner death finishes finite cleanup and releases ownership", %{session: s} do
        parent = self()

        log =
          capture_log(fn ->
            owner =
              spawn(fn ->
                SWI.query(s, slow_cleanup())
                |> Enum.each(fn _ ->
                  send(parent, :yielded)
                  Process.sleep(:infinity)
                end)
              end)

            assert_receive :yielded, 1_000
            Process.exit(owner, :kill)
            wait_until(fn -> :sys.get_state(s).active == nil end)
          end)

        assert log == ""
        assert SWI.call(s, "true") == {:ok, true}
      end

      test "explicit shutdown waits for finite cleanup", %{session: s} do
        suspend(s)
        assert SWI.stop(s) == :ok
        refute Process.alive?(s)
      end

      test "supervisor shutdown waits for finite cleanup", %{session: s} do
        suspend(s)
        {elapsed, log} = :timer.tc(fn -> capture_log(fn -> stop_supervised!(SWI.Session) end) end)
        assert elapsed < 1_500_000
        assert log == ""
        refute Process.alive?(s)
      end
    end
  end

  for payload <- [
        "not json\n",
        "{\n",
        ~s({"status":"unknown"}\n),
        ~s({"status":"solution"}\n),
        ~s({"status":"solution","bindings":[]}\n),
        ~s({"status":"solution","bindings":{"X":{"t":"number","v":"bad"}}}\n),
        ~s({"status":"solution","bindings":{"X":{"t":"var","v":-1}}}\n),
        ~s({"status":"solution","bindings":{"X":{"t":"compound","f":42,"v":[]}}}\n),
        ~s({"status":"solution","bindings":{"X":{"t":"list","v":[{}]}}}\n),
        ~s({"status":"error"}\n),
        ~s({"status":"error","error":42}\n),
        ~s({"status":"ok"}\n)
      ] do
    @payload payload
    test "malformed reply #{inspect(payload)} retires the child and recovers" do
      s = start_supervised!({SWI.Session, fake_child(@payload)})
      port = :sys.get_state(s).transport
      assert SWI.call(s, "true") == {:error, :invalid_reply}
      assert Process.alive?(s)
      assert Port.info(port) == nil
      assert :sys.get_state(s).active == nil
      assert SWI.call(s, "true") == {:ok, true}
      refute :sys.get_state(s).transport == port
    end
  end

  test "Port hard deadline kills a looping cleanup handler" do
    s = start_supervised!({SWI.Session, cleanup_timeout: 50})
    port = :sys.get_state(s).transport

    {elapsed, result} =
      :timer.tc(fn ->
        SWI.call(s, "setup_call_cleanup(true,repeat,(repeat,fail))")
      end)

    assert result == {:error, :timeout}
    assert elapsed < 2_000_000
    assert Port.info(port) == nil
    assert SWI.call(s, "true") == {:ok, true}
  end

  test "EOF partway through a multi-chunk reply retires the child" do
    s = start_supervised!({SWI.Session, fake_child(String.duplicate("x", 150_000), true)})
    assert {:error, {:port_exit, _}} = SWI.call(s, "true")
    assert SWI.call(s, "true") == {:ok, true}
  end

  test "startup validates executables and the bridge before returning a session" do
    Process.flag(:trap_exit, true)
    assert {:error, {:swipl_not_found, _}} = SWI.start_link(swipl: "/missing/swipl")
    exited = temporary("exit.pl")
    File.write!(exited, ":- initialization(halt(0)).\n")
    assert {:error, {:startup, {:error, reason}}} = SWI.start_link(bridge: exited)
    assert reason in [:port_down, {:port_exit, 0}]
    assert {:error, :invalid_cleanup_timeout} = SWI.start_link(cleanup_timeout: 0)
    assert {:error, :invalid_cleanup_timeout} = SWI.start_link(cleanup_timeout: 1.5)

    bridge = temporary("broken.pl")
    File.write!(bridge, ":- initialization(halt(19)).\n")
    assert {:error, {:startup, {:error, reason}}} = SWI.start_link(bridge: bridge)
    assert reason in [:port_down, {:port_exit, 19}]

    # A library import error must fail readiness, even if other predicates loaded.
    File.write!(
      bridge,
      ":- module(swi_bridge,[main/0]).\n:- use_module(library(missing_library)).\nmain :- halt(20).\n"
    )

    assert {:error, {:startup, {:error, reason}}} = SWI.start_link(bridge: bridge)
    assert reason in [:port_down, {:port_exit, 20}]
  end

  test "readiness is bounded and failed children are killed" do
    Process.flag(:trap_exit, true)
    bridge = temporary("silent-child.pl")
    pid_file = bridge <> ".pid"
    quoted_path = :json.encode(pid_file) |> IO.iodata_to_binary()

    File.write!(bridge, """
    :- module(swi_bridge, [main/0]).
    main :- current_prolog_flag(pid, Pid),
            setup_call_cleanup(open(#{quoted_path},write,F), write(F,Pid), close(F)),
            sleep(60).
    """)

    {elapsed, result} = :timer.tc(fn -> SWI.start_link(bridge: bridge) end)
    assert result == {:error, {:startup, {:error, :timeout}}}
    assert elapsed < 3_000_000
    pid = File.read!(pid_file)
    wait_until(fn -> not os_process_alive?(pid) end)

    for reply <- [~s({"status":"ready","protocol":2}), ~s({"status":"ok"})] do
      File.write!(bridge, """
      :- module(swi_bridge, [main/0]).
      :- use_module(library(readutil)).
      main :- current_prolog_flag(pid, Pid),
              setup_call_cleanup(open(#{quoted_path},write,F), write(F,Pid), close(F)),
              read_line_to_string(user_input, _),
              format('~s~n', [#{:json.encode(reply) |> IO.iodata_to_binary()}]),
              flush_output, sleep(60).
      """)

      assert SWI.start_link(bridge: bridge) == {:error, {:startup, {:error, :invalid_reply}}}
      pid = File.read!(pid_file)
      wait_until(fn -> not os_process_alive?(pid) end)
    end

    executable = temporary("invalid-executable")
    File.write!(executable, "invalid executable\n")
    File.chmod!(executable, 0o755)

    case SWI.start_link(swipl: executable) do
      {:error, {:spawn_failed, message}} -> assert is_binary(message)
      {:error, {:startup, {:error, :port_down}}} -> :ok
      {:error, {:startup, {:error, {:port_exit, status}}}} -> assert status != 0
      {:error, {:swipl_not_found, ^executable}} -> :ok
    end
  end

  test "native startup rejects a bridge with a missing required library" do
    bridge = temporary("bridge.pl")

    File.write!(
      bridge,
      File.read!("priv/bridge.pl")
      |> String.replace(
        ":- use_module(library(time)).",
        ":- set_prolog_flag(autoload, false).\n:- use_module(library(missing_time_library))."
      )
    )

    script =
      """
      Process.flag(:trap_exit, true)
      Application.load(:swi_elixir)
      case SWI.start_link(backend: :nif, bridge: #{inspect(bridge)}) do
        {:error, {:startup, {:error, {:prolog, message}}}} -> IO.puts("startup_rejected: " <> message)
        result -> raise inspect(result)
      end
      """

    script_path = temporary("startup.exs")
    File.write!(script_path, script)

    {output, 0} =
      System.cmd("elixir", ["-pa", Path.dirname(:code.which(SWI)), script_path],
        env: [{"ERL_FLAGS", "+S 1:1"}],
        stderr_to_stdout: true
      )

    assert output =~ "startup_rejected:"
    assert output =~ "call_with_time_limit"
  end

  test "a failed native request retires its resource and reconnects" do
    s = start_supervised!({SWI.Session, backend: :nif})
    resource = :sys.get_state(s).transport
    assert :ok = SWI.Native.close(resource)
    assert SWI.call(s, "true") == {:error, :closed}
    assert :sys.get_state(s).transport == nil
    assert :sys.get_state(s).active == nil
    assert SWI.call(s, "true") == {:ok, true}
  end

  test "bridge serialization failures become Prolog errors and release the cursor" do
    s = start_supervised!({SWI.Session, backend: :port})

    goal =
      "abolish(swi_bridge:encode_bindings/2), assertz((swi_bridge:encode_bindings(_,_{bad:foo(bar)})))"

    assert {:error, {:prolog, error}} = SWI.call(s, goal)
    assert error =~ "json_term"
    assert :sys.get_state(s).active == nil
    assert :ok = SWI.load(s, Path.join(:code.priv_dir(:swi_elixir), "bridge.pl"))
    assert SWI.call(s, "true") == {:ok, true}
  end

  test "encoding errors take precedence over cleanup errors and release the cursor" do
    s = start_supervised!({SWI.Session, backend: :port})

    goal =
      "abolish(swi_bridge:encode_bindings/2), " <>
        "assertz((swi_bridge:encode_bindings(_,_) :- throw(encode_failed))), " <>
        "setup_call_cleanup(true,repeat,throw(cleanup_failed))"

    assert SWI.call(s, goal) == {:error, {:prolog, "encode_failed"}}
    assert :sys.get_state(s).active == nil
    assert :ok = SWI.load(s, Path.join(:code.priv_dir(:swi_elixir), "bridge.pl"))
    assert SWI.call(s, "true") == {:ok, true}
  end

  test "missing NIF in a clean application returns a predictable startup error" do
    root = temporary("swi_elixir-0.1.0")
    ebin = Path.join(root, "ebin")
    File.mkdir_p!(Path.join(root, "priv"))
    File.cp_r!(Path.dirname(:code.which(SWI)), ebin)

    script =
      "Process.flag(:trap_exit, true); Application.load(:swi_elixir); IO.inspect(SWI.start_link(backend: :nif))"

    script_path = temporary("missing-nif.exs")
    File.write!(script_path, script)

    {output, 0} =
      System.cmd("elixir", ["-pa", ebin, script_path],
        env: [{"ERL_FLAGS", "+S 1:1"}],
        stderr_to_stdout: true
      )

    assert output =~ "{:error, :nif_unavailable}"
  end

  test "native GC cleanup finishes a slow handler and runs outer cleanup" do
    path = temporary("gc-finished")
    quoted_path = path |> :json.encode() |> IO.iodata_to_binary()
    bridge = Path.join(:code.priv_dir(:swi_elixir), "bridge.pl")
    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        {:ok, resource} = SWI.Native.open(bridge)

        goal =
          "setup_call_cleanup(true,setup_call_cleanup(true,repeat,sleep(0.1)),setup_call_cleanup(open(#{quoted_path},write,S),write(S,done),close(S)))"

        for {request, status} <- [
              {%{op: "open", goal: goal}, "ok"},
              {%{op: "next", timeout: 1}, "solution"}
            ] do
          assert {:ok, response} =
                   SWI.Native.request(
                     resource,
                     request |> :json.encode() |> IO.iodata_to_binary()
                   )

          assert %{"status" => ^status} = :json.decode(response)
        end

        send(parent, :opened)
      end)

    assert_receive :opened, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 1_000
    wait_until(fn -> File.read(path) == {:ok, "done"} end)
  end

  defp slow_cleanup, do: "setup_call_cleanup(true,repeat,sleep(0.1))"

  defp suspend(s) do
    assert {:ok, token} = SWI.Session.request(s, {:open, slow_cleanup()})
    assert {:ok, %{}} = SWI.Session.request(s, {:next, token, 1})
  end

  defp fake_child(payload, eof \\ false) do
    bridge = temporary("child.pl")
    marker = :json.encode(bridge <> ".used") |> IO.iodata_to_binary()
    payload = :json.encode(payload) |> IO.iodata_to_binary()

    File.write!(bridge, """
    :- module(swi_bridge, [main/0]).
    :- use_module(library(http/json)).
    :- use_module(library(readutil)).
    main :- read_line_to_string(user_input, Line),
            (Line == end_of_file -> halt
            ; atom_json_dict(Line, Request, []), reply(Request.op), flush_output, main).
    reply("hello") :- !, writeln('{"status":"ready","protocol":1}').
    reply("next") :- !,
        (exists_file(#{marker}) -> writeln('{"status":"solution","bindings":{}}')
        ; setup_call_cleanup(open(#{marker},write,F),write(F,used),close(F)),
          format('~s', [#{payload}]), flush_output,
          (#{eof} -> halt ; true)).
    reply(_) :- writeln('{"status":"ok"}').
    """)

    [bridge: bridge]
  end
end
