defmodule SWI.SessionTest do
  use ExUnit.Case, async: false
  import SWI.TestSupport

  for backend <- [:port, :nif] do
    describe "#{backend} session contracts" do
      setup do
        %{session: start_supervised!({SWI.Session, backend: unquote(backend)})}
      end

      test "invalid text fails in the caller and preserves session state", %{session: s} do
        assert SWI.call(s, "assertz(utf8_marker)") == {:ok, true}

        for text <- [<<255>>, <<0xE2, 0x82>>] do
          assert_raise ArgumentError, "text must be valid UTF-8", fn -> SWI.call(s, text) end
          assert_raise ArgumentError, "text must be valid UTF-8", fn -> SWI.query(s, text) end
          assert_raise ArgumentError, "text must be valid UTF-8", fn -> SWI.load(s, text) end
          assert SWI.Session.request(s, {:open, text}) == {:error, :invalid_text}
          assert SWI.Session.request(s, {:load, text, 1}) == {:error, :invalid_text}
        end

        assert Process.alive?(s)
        assert SWI.call(s, "utf8_marker, X='λ雪'") == {:ok, true}
      end

      test "one complete goal is required before side effects run", %{session: s} do
        for text <- [
              "true",
              "true.",
              "true. % comment",
              "true /* comment */",
              "true % comment",
              "'true'.\n/* comment */"
            ] do
          assert SWI.call(s, text) == {:ok, true}
        end

        assert [%{"X" => {:atom, "a.b"}}] = Enum.to_list(SWI.query(s, "X='a.b'"))

        for text <- [
              "true. fail.",
              "true. end_of_file.",
              "true. broken(",
              "true. /*",
              "true. false",
              ""
            ] do
          assert {:error, {:prolog, _}} = SWI.call(s, text)
        end

        assert {:error, {:prolog, _}} = SWI.call(s, "assertz(trailing_side_effect). true.")
        assert SWI.call(s, "current_predicate(trailing_side_effect/0)") == {:ok, false}
        assert SWI.call(s, "true") == {:ok, true}
      end

      test "formula adapters use the same complete-input parser", %{session: s} do
        assert :ok = SWI.load(s, "examples/leanhat.pl")
        assert :ok = SWI.load(s, "examples/nanocop.pl")

        for goal <- [
              ~s|leanhat:prove_text("p=>p. fail.")|,
              ~s|nanocop:prove_text("p=>p. fail.",ht)|
            ] do
          assert {:error, {:prolog, _}} = SWI.call(s, goal)
        end

        assert SWI.call(s, ~s|leanhat:prove_text("p=>p.")|) == {:ok, true}
        assert SWI.call(s, ~s|nanocop:prove_text("p=>p",ht)|) == {:ok, true}
      end

      test "failed initialization and directives return load errors", %{session: s} do
        path = temporary("initialization.pl")

        for source <- [
              ":- initialization(fail).",
              ":- initialization(throw(init_failed)).",
              ":- fail."
            ] do
          File.write!(path, source <> "\npartial_fact(ok).\n")
          assert {:error, {:prolog, _}} = SWI.load(s, path)
          # A failed consult is not a transaction: code already loaded can remain.
          assert SWI.call(s, "partial_fact(ok)") == {:ok, true}
        end

        File.write!(path, "partial_fact(changed).\nunused_variable(X).\n")
        assert :ok = SWI.load(s, path)
        assert SWI.call(s, "partial_fact(changed)") == {:ok, true}
        assert SWI.call(s, "partial_fact(ok)") == {:ok, false}
        File.write!(path, ":- initialization(sleep(0.1)).\n")
        assert SWI.load(s, path, timeout: 10) == {:error, :timeout}
        File.write!(path, "partial_fact(recovered).\n")
        assert :ok = SWI.load(s, path)
        assert SWI.call(s, "partial_fact(recovered)") == {:ok, true}
      end

      test "stop closes a suspended cursor and returns its cleanup failure", %{session: s} do
        {:ok, token} =
          SWI.Session.request(s, {:open, "setup_call_cleanup(true,repeat,throw(stop_failed))"})

        assert {:ok, %{}} = SWI.Session.request(s, {:next, token, 1})
        assert SWI.stop(s) == {:error, {:prolog, "stop_failed"}}
        refute Process.alive?(s)
      end

      test "requests queued after stop cannot open a query", %{session: s} do
        parent = self()
        :ok = :sys.suspend(s)
        stopper = spawn(fn -> send(parent, {:stopped, SWI.stop(s)}) end)

        wait_until(fn ->
          Enum.any?(elem(Process.info(s, :messages), 1), &match?({:"$gen_call", _, :stop}, &1))
        end)

        caller =
          spawn(fn ->
            result =
              try do
                SWI.call(s, "assertz(after_stop)")
              catch
                :exit, _ -> :stopped
              end

            send(parent, {:query_after_stop, result})
          end)

        wait_until(fn -> length(elem(Process.info(s, :messages), 1)) >= 2 end)
        :ok = :sys.resume(s)
        assert_receive {:stopped, :ok}, 1_000
        assert_receive {:query_after_stop, :stopped}, 1_000
        refute Process.alive?(s)
        refute Process.alive?(stopper)
        refute Process.alive?(caller)
      end

      test "concurrent stop calls dispose the session once", %{session: s} do
        parent = self()
        :ok = :sys.suspend(s)

        for _ <- 1..2 do
          spawn(fn ->
            result =
              try do
                SWI.stop(s)
              catch
                :exit, _ -> :stopped
              end

            send(parent, {:stop_result, result})
          end)
        end

        wait_until(fn -> length(elem(Process.info(s, :messages), 1)) >= 2 end)
        :ok = :sys.resume(s)

        results =
          for _ <- 1..2 do
            receive do
              {:stop_result, result} -> result
            after
              1_000 -> flunk("missing stop result")
            end
          end

        assert Enum.sort(results) == [:ok, :stopped]
        refute Process.alive?(s)
      end
    end
  end

  test "idle Port death reports one reset before reconnecting or loading" do
    s = start_supervised!({SWI.Session, backend: :port})
    assert SWI.call(s, "assertz(reset_marker)") == {:ok, true}

    for operation <- [:query, :load] do
      {:os_pid, os_pid} = Port.info(:sys.get_state(s).transport, :os_pid)
      SWI.Runtime.kill(os_pid)
      wait_until(fn -> :sys.get_state(s).transport == nil end)

      if operation == :query do
        assert SWI.call(s, "dynamic(reset_marker/0), \\+ reset_marker") ==
                 {:error, :session_reset}
      else
        assert SWI.load(s, "examples/family.pl") == {:error, :session_reset}
      end

      assert SWI.call(s, "true") == {:ok, true}
      assert :ok = SWI.load(s, "examples/family.pl")
      assert SWI.call(s, "family:ancestor(ada,emmy)") == {:ok, true}
    end
  end

  test "idle crash invalidates a suspended query and old tokens cannot affect a new cursor" do
    s = start_supervised!(SWI.Session)
    {:ok, old} = SWI.Session.request(s, {:open, "repeat"})
    assert {:ok, %{}} = SWI.Session.request(s, {:next, old, 1})
    {:os_pid, pid} = Port.info(:sys.get_state(s).transport, :os_pid)
    SWI.Runtime.kill(pid)
    wait_until(fn -> :sys.get_state(s).transport == nil end)
    assert SWI.Session.request(s, {:next, old, 1}) == {:error, :session_reset}
    {:ok, current} = SWI.Session.request(s, {:open, "repeat"})
    assert SWI.Session.request(s, {:next, old, 1}) == {:error, :stale_query}
    assert SWI.Session.request(s, {:close, old}) == :ok
    assert SWI.Session.request(s, {:load, "/missing", 1}) == {:error, :busy}
    assert {:ok, %{}} = SWI.Session.request(s, {:next, current, 1})
    assert SWI.Session.request(s, {:close, current}) == :ok
  end

  test "named restart is observable by monitoring its concrete session PID" do
    s = start_supervised!({SWI.Session, name: :contract_restart})
    ref = Process.monitor(s)
    Process.exit(s, :kill)
    assert_receive {:DOWN, ^ref, :process, ^s, :killed}, 1_000
    wait_until(fn -> (p = Process.whereis(:contract_restart)) != nil and p != s end)
    replacement = Process.whereis(:contract_restart)
    assert SWI.call(replacement, "true") == {:ok, true}
    assert SWI.stop(replacement) == :ok
  end
end
