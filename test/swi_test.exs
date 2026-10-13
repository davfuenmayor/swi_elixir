defmodule SWITest do
  use ExUnit.Case, async: false
  import SWI.TestSupport

  for backend <- [:port, :nif] do
    describe "#{backend}" do
      setup do
        session = start_supervised!({SWI.Session, backend: unquote(backend)})
        %{session: session}
      end

      test "success, failure, repeated calls and syntax errors", %{session: s} do
        for _ <- 1..30 do
          assert SWI.call(s, "true") == {:ok, true}
          assert SWI.call(s, "fail") == {:ok, false}
        end

        assert {:error, {:prolog, error}} = SWI.call(s, "bad(")
        assert error =~ "syntax_error"
        assert {:ok, true} = SWI.call(s, "true.")
      end

      test "bindings, compounds, strings, integers, floats and lists", %{session: s} do
        assert [answer] = Enum.to_list(SWI.query(s, ~s|X=f(a, [1, 2.5], "hi"), N is 2^100|))
        assert answer["X"] == {:compound, "f", [{:atom, "a"}, [1, 2.5], "hi"]}
        assert answer["N"] == Integer.pow(2, 100)

        assert [%{"X" => [], "Y" => {:cons, 1, {:atom, "tail"}}}] =
                 Enum.to_list(SWI.query(s, "X=[], Y=[1|tail]"))
      end

      test "cyclic and extended terms have an explicit text fallback", %{session: s} do
        assert [%{"X" => {:prolog, cyclic}}] =
                 Enum.to_list(SWI.query(s, "set_prolog_flag(occurs_check,false), X=f(X)"))

        assert cyclic =~ "f("
        assert [%{"X" => {:prolog, "1r3"}}] = Enum.to_list(SWI.query(s, "X is 1 rdiv 3"))
        assert [%{"X" => {:prolog, "1.0Inf"}}] = Enum.to_list(SWI.query(s, "X is 1.0Inf"))
        assert [%{"X" => {:prolog, text}}] = Enum.to_list(SWI.query(s, "X=tag{a:1}"))
        assert text =~ "tag{"
      end

      test "variable identity is shared across the entire answer", %{session: s} do
        assert [%{"X" => x, "Y" => y, "Z" => {:compound, "f", [a, b]}}] =
                 Enum.to_list(SWI.query(s, "X=Y, Z=f(X,W)"))

        assert x == y and x == a and x != b
        assert {:var, _} = x
      end

      test "multiple answers are lazy and early halt releases the query", %{session: s} do
        assert Enum.to_list(SWI.query(s, "member(X,[a,b,c])")) ==
                 Enum.map(~w(a b c), &%{"X" => {:atom, &1}})

        assert length(Enum.take(SWI.query(s, "repeat"), 100)) == 100
        assert SWI.call(s, "true") == {:ok, true}
        assert [] == Enum.to_list(SWI.query(s, "fail"))
      end

      test "consult files, recursion, and missing file errors", %{session: s} do
        assert :ok == SWI.load(s, "test/fixtures/program.pl")

        assert Enum.to_list(SWI.query(s, "fixture:path(a,X)")) ==
                 Enum.map(~w(b c d), &%{"X" => {:atom, &1}})

        assert {:error, {:prolog, _}} = SWI.load(s, "does-not-exist.pl")
        assert {:error, {:prolog, error}} = SWI.load(s, "test/fixtures/invalid.pl")
        assert error =~ "syntax_error"
        assert {:ok, true} = SWI.call(s, "true")
      end

      test "exceptions release the cursor", %{session: s} do
        assert {:error, {:prolog, "oops"}} = SWI.call(s, "throw(oops)")

        assert_raise SWI.Error, fn ->
          SWI.query(s, "(X=1;throw(later))") |> Enum.to_list()
        end

        assert {:ok, true} = SWI.call(s, "true")
      end

      test "timeout interrupts real computation and the session remains usable", %{session: s} do
        assert :ok == SWI.load(s, "test/fixtures/program.pl")
        assert {:error, :timeout} == SWI.call(s, "fixture:spin", timeout: 30)
        assert {:ok, true} == SWI.call(s, "fixture:path(a,d)")
        assert {:error, :timeout} == SWI.call(s, "sleep(1)", timeout: 30)
      end

      test "timeout resets for each pull and excludes consumer time", %{session: s} do
        answers = SWI.query(s, "member(X,[1,2,3]), sleep(0.01)", timeout: 40)

        assert [1, 2, 3] ==
                 Enum.map(answers, fn %{"X" => x} ->
                   Process.sleep(60)
                   x
                 end)
      end

      test "cleanup runs on early halt and consumer death", %{session: s} do
        # Non-backtrackable state is owned by the query engine, so use a file.
        file = temporary("cleanup")
        quoted = :json.encode(file) |> IO.iodata_to_binary()

        goal =
          "setup_call_cleanup(true, repeat, (open(#{quoted},write,F),write(F,done),close(F)))"

        assert [_] = Enum.take(SWI.query(s, goal), 1)
        assert File.read!(file) == "done"
        File.rm!(file)
        parent = self()

        owner =
          spawn(fn ->
            SWI.query(s, goal)
            |> Enum.each(fn _ ->
              send(parent, :yielded)
              Process.sleep(:infinity)
            end)
          end)

        assert_receive :yielded
        assert {:error, :busy} = SWI.call(s, "true")
        Process.exit(owner, :kill)
        wait_until(fn -> File.exists?(file) end)
        assert {:ok, true} = SWI.call(s, "true")
      end

      test "query output cannot corrupt the protocol", %{session: s} do
        assert {:ok, true} = SWI.call(s, "writeln(hello), format('~s', [\"output\"])")
        assert [%{"X" => {:atom, "λ雪"}}] = Enum.to_list(SWI.query(s, "X='λ雪'"))
        assert [answer] = Enum.to_list(SWI.query(s, "length(X,20000), maplist(=(a),X)"))
        assert length(answer["X"]) == 20_000
      end
    end
  end

  test "ordinary queries agree across backends" do
    port = start_supervised!({SWI.Session, backend: :port}, id: :port)
    nif = start_supervised!({SWI.Session, backend: :nif}, id: :nif)

    for goal <- [
          "true",
          "fail",
          "member(X,[f(a),1,2.5,[]])",
          "X=Y, Z=f(Y)",
          "findall(X, between(1,10,X), L)"
        ] do
      assert Enum.to_list(SWI.query(port, goal)) == Enum.to_list(SWI.query(nif, goal))
    end
  end

  test "independent NIF engines can search concurrently" do
    sessions = for i <- 1..4, do: start_supervised!({SWI.Session, backend: :nif}, id: i)

    tasks =
      for {s, i} <- Enum.with_index(sessions),
          do:
            Task.async(fn ->
              for _ <- 1..20,
                  do: assert(Enum.to_list(SWI.query(s, "X=#{i}, sleep(0.005)")) == [%{"X" => i}])
            end)

    Enum.each(tasks, &Task.await/1)
  end

  test "NIF computation leaves ordinary schedulers responsive" do
    s = start_supervised!({SWI.Session, backend: :nif})
    task = Task.async(fn -> SWI.call(s, "repeat, fail", timeout: 300) end)
    # Running with +S 1 makes a misplaced CPU-bound NIF block the only scheduler.
    started = System.monotonic_time(:millisecond)
    Process.sleep(30)
    assert System.monotonic_time(:millisecond) - started < 200
    assert Process.alive?(task.pid)
    assert Task.await(task) == {:error, :timeout}
  end

  test "Port crash is isolated and the next request starts a fresh runtime" do
    s = start_supervised!({SWI.Session, backend: :port})
    assert :ok == SWI.load(s, "examples/family.pl")
    assert {:error, {:port_exit, 7}} = SWI.call(s, "halt(7)")
    assert Process.alive?(s)
    assert {:ok, true} = SWI.call(s, "true")
    assert {:error, {:prolog, _}} = SWI.call(s, "family:ancestor(ada,emmy)")
    assert :ok == SWI.load(s, "examples/family.pl")
    assert {:ok, true} = SWI.call(s, "family:ancestor(ada,emmy)")
  end

  test "Port enforces a hard deadline when a goal catches the SWI alarm" do
    s = start_supervised!({SWI.Session, backend: :port})
    assert {:ok, true} = SWI.call(s, "assertz(marker)")
    original = :sys.get_state(s).transport

    assert {:error, :timeout} =
             SWI.call(s, "catch((repeat,fail),time_limit_exceeded,(repeat,fail))", timeout: 30)

    assert Port.info(original) == nil
    assert {:ok, true} = SWI.call(s, "true")
    assert :sys.get_state(s).transport != original
  end

  test "Port reuses its OS process for ordinary calls" do
    s = start_supervised!({SWI.Session, backend: :port})
    original = :sys.get_state(s).transport
    for _ <- 1..10, do: assert(SWI.call(s, "true") == {:ok, true})
    assert :sys.get_state(s).transport == original
    ref = Process.monitor(s)
    SWI.stop(s)
    assert_receive {:DOWN, ^ref, :process, ^s, :normal}
    assert Port.info(original) == nil
  end

  test "GC of an unclosed native resource destroys its suspended query" do
    path = temporary("gc-finished")

    {owner, ref} =
      spawn_monitor(fn ->
        bridge = Path.join(:code.priv_dir(:swi_elixir), "bridge.pl")
        {:ok, resource} = SWI.Native.open(bridge)
        quoted = :json.encode(path) |> IO.iodata_to_binary()
        goal = "setup_call_cleanup(true,repeat,(open(#{quoted},write,F),write(F,done),close(F)))"
        request = :json.encode(%{op: "open", goal: goal}) |> IO.iodata_to_binary()
        {:ok, _} = SWI.Native.request(resource, request)
        {:ok, _} = SWI.Native.request(resource, ~s|{"op":"next","timeout":1}|)
      end)

    assert_receive {:DOWN, ^ref, :process, ^owner, :normal}
    wait_until(fn -> File.exists?(path) end)
    assert File.read!(path) == "done"
  end

  test "session works as an OTP child and is restarted by its supervisor" do
    s = start_supervised!({SWI.Session, backend: :port, name: :restartable})
    Process.exit(s, :kill)
    wait_until(fn -> (p = Process.whereis(:restartable)) != nil and p != s end)
    assert {:ok, true} = SWI.call(:restartable, "true")
  end

  test "native close is idempotent and closed resources reject requests" do
    bridge = Path.join(:code.priv_dir(:swi_elixir), "bridge.pl")
    {:ok, resource} = SWI.Native.open(bridge)
    assert :ok = SWI.Native.close(resource)
    assert :ok = SWI.Native.close(resource)
    assert {:error, :closed} = SWI.Native.request(resource, "{}")

    for _ <- 1..30 do
      {:ok, s} = SWI.start_link(backend: :nif)
      assert {:ok, true} = SWI.call(s, "true")
      SWI.stop(s)
    end
  end

  test "invalid options are rejected" do
    s = start_supervised!({SWI.Session, backend: :port})
    assert_raise ArgumentError, fn -> SWI.query(s, "true", timeout: 0) end
  end
end
