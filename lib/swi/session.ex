defmodule SWI.Session do
  @moduledoc false
  use GenServer
  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  def request(session, request), do: GenServer.call(session, request, :infinity)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    backend = Keyword.get(opts, :backend, :port)
    state = %{backend: backend, opts: opts, transport: nil, active: nil, reset: false}

    case validate_and_connect(state) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:stop, _, state) do
    {reply, state} = close(state)
    {:stop, :normal, reply, state}
  end

  def handle_call(:close, _, state) do
    {reply, state} = close(state)
    {:reply, reply, state}
  end

  def handle_call(request, _, %{reset: true} = state)
      when elem(request, 0) in [:open, :load, :next] do
    {:reply, {:error, :session_reset}, %{state | reset: false}}
  end

  def handle_call({:open, goal}, {owner, _}, %{active: nil} = state) do
    {reply, state} = rpc(state, %{op: "open", goal: goal})

    case reply do
      :ok ->
        token = Process.monitor(owner)
        {:reply, {:ok, token}, %{state | active: {token, owner}}}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:open, _}, _, state), do: {:reply, {:error, :busy}, state}

  def handle_call({:next, token, seconds}, {owner, _}, %{active: {token, owner}} = state) do
    {reply, state} = rpc(state, %{op: "next", timeout: seconds})
    state = if match?({:ok, _}, reply), do: state, else: release(state)
    {:reply, reply, state}
  end

  def handle_call({:next, _, _}, _, state), do: {:reply, {:error, :stale_query}, state}

  def handle_call({:close, token}, _, %{active: {token, _}} = state) do
    {reply, state} = close(state)
    {:reply, reply, state}
  end

  def handle_call({:close, _}, _, state), do: {:reply, :ok, state}

  def handle_call({:load, path, seconds}, _, %{active: nil} = state) do
    {reply, state} = rpc(state, %{op: "load", path: path, timeout: seconds})
    {:reply, reply, state}
  end

  def handle_call({:load, _, _}, _, state), do: {:reply, {:error, :busy}, state}

  @impl true
  def handle_info({:DOWN, token, :process, _, _}, %{active: {token, _}} = state) do
    {reply, state} = close(state)
    log_cleanup(reply)
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, _}}, %{transport: port, backend: :port} = state),
    do: {:noreply, %{release(state) | transport: nil, reset: true}}

  def handle_info({:EXIT, port, _}, %{transport: port, backend: :port} = state),
    do: {:noreply, %{release(state) | transport: nil, reset: true}}

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_, state) do
    if state.backend == :port && state.active do
      {reply, _} = close(state)
      log_cleanup(reply)
    end

    retire(state)
    :ok
  end

  defp close(%{transport: nil} = state), do: {:ok, release(state)}

  defp close(state) do
    {reply, state} = rpc(state, %{op: "close"})
    {reply, release(state)}
  end

  defp log_cleanup(:ok), do: :ok
  defp log_cleanup(error), do: Logger.warning("Prolog cleanup failed: #{inspect(error)}")

  defp release(%{active: nil} = state), do: state

  defp release(%{active: {token, _}} = state) do
    Process.demonitor(token, [:flush])
    %{state | active: nil}
  end

  defp cleanup_seconds(state), do: Keyword.get(state.opts, :cleanup_timeout, 1_000) / 1000

  defp validate_and_connect(state) do
    case Keyword.get(state.opts, :cleanup_timeout, 1_000) do
      ms when is_integer(ms) and ms > 0 -> connect(state)
      _ -> {:error, :invalid_cleanup_timeout}
    end
  end

  defp ready(state) do
    case rpc(state, %{op: "hello", timeout: 1}) do
      {:ready, state} ->
        {:ok, state}

      {reply, state} ->
        retire(state)
        {:error, {:startup, reply}}
    end
  end

  defp connect(state) do
    with {:ok, transport} <- open_transport(state) do
      ready(%{state | transport: transport})
    end
  end

  defp open_transport(%{backend: :port} = state) do
    executable = Keyword.get(state.opts, :swipl, System.get_env("SWIPL") || "swipl")

    case System.find_executable(executable) do
      nil ->
        {:error, {:swipl_not_found, executable}}

      path ->
        port =
          Port.open({:spawn_executable, path}, [
            :binary,
            :exit_status,
            :use_stdio,
            {:line, 65_536},
            args: [
              "-q",
              "--no-signals",
              "-f",
              "none",
              "-s",
              bridge(state),
              "-g",
              "swi_bridge:main",
              "-t",
              "halt"
            ]
          ])

        {:ok, port}
    end
  rescue
    error in [ArgumentError, ErlangError] -> {:error, {:spawn_failed, Exception.message(error)}}
  end

  defp open_transport(%{backend: :nif} = state) do
    with {:module, SWI.Native} <- Code.ensure_loaded(SWI.Native) do
      SWI.Native.open(bridge(state))
    else
      {:error, reason} when reason in [:nofile, :on_load_failure] -> {:error, :nif_unavailable}
      error -> error
    end
  end

  defp open_transport(_), do: {:error, :invalid_backend}

  defp bridge(state),
    do: Keyword.get(state.opts, :bridge, Path.join(:code.priv_dir(:swi_elixir), "bridge.pl"))

  defp rpc(%{transport: nil} = state, request) do
    case connect(state) do
      {:ok, connected} -> rpc(connected, request)
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  defp rpc(state, request) do
    if Enum.any?(Map.values(request), &(is_binary(&1) and not String.valid?(&1))) do
      {{:error, :invalid_text}, state}
    else
      exchange(state, request)
    end
  end

  defp exchange(state, request) do
    encoded = request |> :json.encode() |> IO.iodata_to_binary()

    response =
      case state.backend do
        :nif ->
          SWI.Native.request(state.transport, encoded)

        :port ->
          seconds =
            if request.op == "close",
              do: cleanup_seconds(state),
              else: Map.get(request, :timeout, 5)

          deadline = trunc(seconds * 1000) + 1_000

          try do
            Port.command(state.transport, [encoded, "\n"])
            receive_line(state.transport, "", System.monotonic_time(:millisecond) + deadline)
          rescue
            ArgumentError -> {:error, :port_down}
          end
      end

    case response do
      {:ok, json} ->
        reply = decode_reply(json, request.op)
        state = if reply == {:error, :invalid_reply}, do: retire(state), else: state
        {reply, state}

      error ->
        {error, retire(state)}
    end
  end

  defp retire(state) do
    case {state.backend, state.transport} do
      {_, nil} -> :ok
      {:port, port} -> kill_port(port)
      {:nif, engine} -> log_cleanup(SWI.Native.close(engine))
    end

    %{release(state) | transport: nil}
  end

  defp decode_reply(json, op) do
    decode(:json.decode(json), op)
  rescue
    _ -> {:error, :invalid_reply}
  end

  defp receive_line(port, acc, timeout) do
    receive do
      {^port, {:data, {:eol, line}}} -> {:ok, acc <> line}
      {^port, {:data, {:noeol, line}}} -> receive_line(port, acc <> line, timeout)
      {^port, {:exit_status, status}} -> {:error, {:port_exit, status}}
      {:EXIT, ^port, reason} -> {:error, {:port_exit, reason}}
    after
      max(timeout - System.monotonic_time(:millisecond), 0) -> {:error, :timeout}
    end
  end

  defp decode(%{"status" => "ready", "protocol" => 1}, "hello"), do: :ready
  defp decode(%{"status" => "ok"}, op) when op in ["open", "close", "load"], do: :ok
  defp decode(%{"status" => "done"}, "next"), do: :done
  defp decode(%{"status" => "timeout"}, _), do: {:error, :timeout}

  defp decode(%{"status" => "error", "error" => error}, _) when is_binary(error),
    do: {:error, {:prolog, error}}

  defp decode(%{"status" => "solution", "bindings" => bindings}, "next") when is_map(bindings),
    do: {:ok, Map.new(bindings, fn {name, value} -> {name, SWI.Term.decode(value)} end)}

  defp kill_port(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        System.cmd("kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)

      nil ->
        :ok
    end

    try do
      Port.close(port)
    rescue
      ArgumentError -> :ok
    end
  end
end
