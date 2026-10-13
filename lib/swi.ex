defmodule SWI do
  @moduledoc "A persistent SWI-Prolog session with incremental, backend-neutral queries."

  @doc """
  Start a persistent session. Options: `:backend` (`:port` by default), `:name`,
  `:swipl`, `:bridge`, and positive `:cleanup_timeout` milliseconds (Port only).
  Native admission can return `{:error, :native_capacity}` when its 64 engine
  slots are occupied, including engines still undergoing GC cleanup.
  """
  defdelegate start_link(opts \\ []), to: SWI.Session
  defdelegate child_spec(opts), to: SWI.Session

  @doc "Close the cursor and stop atomically, returning any cleanup error."
  def stop(session), do: SWI.Session.request(session, :stop)

  @doc """
  Consult a UTF-8 source path, expanding relative paths in Elixir.
  Failed initialization or directives return an error; other warnings are
  nonfatal. Failed loads may leave partial code and side effects behind.
  `:timeout` is positive milliseconds, defaulting to 5,000.
  """
  def load(session, path, opts \\ []) do
    path = path |> IO.chardata_to_string() |> text!() |> Path.expand()
    SWI.Session.request(session, {:load, path, timeout(opts)})
  end

  @doc """
  Lazily enumerate bindings for one complete UTF-8 Prolog goal. A final period
  and trailing comments are optional; extra terms are rejected before execution.
  Invalid UTF-8 raises `ArgumentError` in the caller. One enumeration owns each
  session. `:timeout` bounds each search pull, excluding consumer and close time.
  Prolog/transport errors raise `SWI.Error`. After an unnoticed transport loss,
  the next operation reports `:session_reset` before a later request reconnects;
  reload lost state explicitly. Monitor the concrete PID for supervised restarts.
  """
  def query(session, goal, opts \\ []) when is_binary(goal) do
    goal = text!(goal)
    %SWI.Query{session: session, goal: goal, seconds: timeout(opts)}
  end

  @doc "Return {:ok, true | false} or {:error, reason}; discard remaining choice points."
  def call(session, goal, opts \\ []) do
    {:ok, Enum.any?(query(session, goal, opts))}
  rescue
    e in SWI.Error -> {:error, e.reason}
  end

  defp text!(text) do
    if String.valid?(text), do: text, else: raise(ArgumentError, "text must be valid UTF-8")
  end

  defp timeout(opts) do
    case Keyword.get(opts, :timeout, 5_000) do
      ms when is_integer(ms) and ms > 0 -> ms / 1000
      _ -> raise ArgumentError, "timeout must be a positive integer in milliseconds"
    end
  end
end
