defmodule SWI.PriorityFixesTest do
  use ExUnit.Case, async: false
  import SWI.TestSupport
  import ExUnit.CaptureLog

  for backend <- [:port, :nif] do
    describe "#{backend} priority regressions" do
      setup do
        %{session: start_supervised!({SWI.Session, backend: unquote(backend)})}
      end

      test "special atoms and functors retain binary names at every depth", %{session: s} do
        assert [answer] =
                 Enum.to_list(
                   SWI.query(s, "X=true,Y=false,Z=null,F=true(false(null)),L=[true,false,null]")
                 )

        assert answer["X"] == {:atom, "true"}
        assert answer["Y"] == {:atom, "false"}
        assert answer["Z"] == {:atom, "null"}
        assert answer["F"] == {:compound, "true", [{:compound, "false", [{:atom, "null"}]}]}
        assert answer["L"] == Enum.map(~w(true false null), &{:atom, &1})
      end

      test "cleanup failures propagate on early halt and leave the session usable", %{session: s} do
        goal = "setup_call_cleanup(true,repeat,throw(cleanup_failed))"
        assert SWI.call(s, goal) == {:error, {:prolog, "cleanup_failed"}}
        assert_raise SWI.Error, fn -> Enum.take(SWI.query(s, goal), 1) end
        assert SWI.call(s, "true") == {:ok, true}
      end

      test "cleanup failures propagate when a suspended continuation is halted", %{session: s} do
        goal = "setup_call_cleanup(true,repeat,throw(cleanup_failed))"

        {:suspended, :answer, continuation} =
          Enumerable.reduce(SWI.query(s, goal), {:cont, nil}, fn _, _ -> {:suspend, :answer} end)

        assert_raise SWI.Error, fn -> continuation.({:halt, :answer}) end
        assert SWI.call(s, "true") == {:ok, true}

        assert Enumerable.reduce(SWI.query(s, "throw(never_started)"), {:halt, :empty}, fn _, _ ->
                 flunk()
               end) == {:halted, :empty}
      end

      test "consumer errors take precedence over cleanup errors", %{session: s} do
        log =
          capture_log(fn ->
            assert_raise RuntimeError, "consumer failed", fn ->
              SWI.query(s, "setup_call_cleanup(true,repeat,throw(cleanup_failed))")
              |> Enum.each(fn _ -> raise "consumer failed" end)
            end
          end)

        assert log =~ "cleanup_failed"
        assert SWI.call(s, "true") == {:ok, true}
      end

      test "an original query error is preserved and consumer throws release the cursor", %{
        session: s
      } do
        assert SWI.call(s, "setup_call_cleanup(true,throw(query_failed),true)") ==
                 {:error, {:prolog, "query_failed"}}

        assert catch_throw(Enum.each(SWI.query(s, "repeat"), fn _ -> throw(:consumer_throw) end)) ==
                 :consumer_throw

        assert SWI.call(s, "true") == {:ok, true}
      end

      test "consumer death logs cleanup failure and releases ownership", %{session: s} do
        parent = self()

        log =
          capture_log(fn ->
            owner =
              spawn(fn ->
                SWI.query(s, "setup_call_cleanup(true,repeat,throw(owner_cleanup_failed))")
                |> Enum.each(fn _ ->
                  send(parent, :yielded)
                  Process.sleep(:infinity)
                end)
              end)

            assert_receive :yielded, 1000
            Process.exit(owner, :kill)
            wait_until(fn -> :sys.get_state(s).active == nil end)
          end)

        assert log =~ "owner_cleanup_failed"
        assert SWI.call(s, "true") == {:ok, true}
      end

      test "prover loads and calls preserve ordinary unification flags", %{session: s} do
        for _ <- 1..2, source <- ["examples/nanocop.pl", "examples/leanhat.pl"] do
          assert :ok = SWI.load(s, source)
          assert {:ok, true} = SWI.call(s, "current_prolog_flag(occurs_check,false)")
          assert {:ok, true} = SWI.call(s, "X=f(X)")
        end

        assert SWI.call(
                 s,
                 ~s|set_prolog_flag(occurs_check,false), catch(nanocop:prove_text("(",ht),_,true), current_prolog_flag(occurs_check,false)|
               ) == {:ok, true}

        for flag <- ["false", "true", "error"] do
          goal =
            "set_prolog_flag(occurs_check,#{flag}), once(nanocop:prove_text(\"p=>p\",ht)), current_prolog_flag(occurs_check,#{flag})"

          assert SWI.call(s, goal) == {:ok, true}
        end

        assert SWI.call(
                 s,
                 "set_prolog_flag(occurs_check,false), (nanocop:prove_text(\"p; ~p\",intu) -> fail ; true), current_prolog_flag(occurs_check,false)"
               ) == {:ok, true}
      end

      test "leanHaT applies equality axioms, including after reconsult", %{session: s} do
        for _ <- 1..2 do
          assert :ok = SWI.load(s, "examples/leanhat.pl")

          for formula <- ["a=a", "(a=b)=>(b=a)", "(a=b)=>(f(a)=f(b))", "((a=b),p(a))=>p(b)"] do
            quoted = :json.encode(formula) |> IO.iodata_to_binary()
            assert SWI.call(s, "leanhat:prove_text(#{quoted})", timeout: 2000) == {:ok, true}
          end
        end
      end
    end
  end

  test "native explicit resource close reports cleanup exceptions" do
    {:ok, resource} = SWI.Native.open(Path.join(:code.priv_dir(:swi_elixir), "bridge.pl"))

    request = fn data ->
      SWI.Native.request(resource, :json.encode(data) |> IO.iodata_to_binary())
    end

    assert {:ok, _} =
             request.(%{
               op: "open",
               goal: "setup_call_cleanup(true,repeat,throw(native_cleanup_failed))"
             })

    assert {:ok, _} = request.(%{op: "next", timeout: 1})
    assert SWI.Native.close(resource) == {:error, {:prolog, "native_cleanup_failed"}}
    assert SWI.Native.close(resource) == :ok
  end

  test "Port owner kill during search reaps the old OS child under supervision" do
    session = start_supervised!({SWI.Session, backend: :port, name: :reap_on_restart})
    assert {:ok, true} = SWI.call(session, "true")
    {:os_pid, pid} = Port.info(:sys.get_state(session).transport, :os_pid)
    owner = search_until_killed(session)
    Process.exit(session, :kill)
    wait_until(fn -> not File.exists?("/proc/#{pid}") end)
    wait_until(fn -> (new = Process.whereis(:reap_on_restart)) != nil and new != session end)
    assert SWI.call(:reap_on_restart, "true") == {:ok, true}
    wait_until(fn -> not Process.alive?(owner) end)
  end

  test "supervisor shutdown during search reaps the OS child" do
    {:ok, supervisor} =
      Supervisor.start_link([{SWI, backend: :port, name: :reap_on_shutdown}],
        strategy: :one_for_one
      )

    session = Process.whereis(:reap_on_shutdown)
    assert {:ok, true} = SWI.call(session, "true")
    {:os_pid, pid} = Port.info(:sys.get_state(session).transport, :os_pid)
    owner = search_until_killed(session)
    Supervisor.stop(supervisor)
    wait_until(fn -> not File.exists?("/proc/#{pid}") end)
    wait_until(fn -> not Process.alive?(owner) end)
  end

  defp search_until_killed(session) do
    path = temporary("active")
    quoted = :json.encode(path) |> IO.iodata_to_binary()

    owner =
      spawn(fn ->
        try do
          SWI.call(session, "open(#{quoted},write,F),close(F),repeat,fail", timeout: 30000)
        catch
          :exit, _ -> :ok
        end
      end)

    wait_until(fn -> File.exists?(path) end)
    owner
  end
end
