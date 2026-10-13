defmodule SWI.Query do
  @moduledoc false
  require Logger
  defstruct [:session, :goal, :seconds]

  def reduce(_query, {:halt, acc}, _fun), do: {:halted, acc}

  def reduce(query, {:suspend, acc}, fun),
    do: {:suspended, acc, &reduce(query, &1, fun)}

  def reduce(query, {:cont, acc}, fun) do
    {:ok, token} = request(query, {:open, query.goal})
    resume(query, token, {:cont, acc}, fun)
  end

  defp resume(query, token, {:halt, acc}, _fun) do
    close(query, token)
    {:halted, acc}
  end

  defp resume(query, token, {:suspend, acc}, fun),
    do: {:suspended, acc, &resume(query, token, &1, fun)}

  defp resume(query, token, {:cont, acc}, fun) do
    case request(query, {:next, token, query.seconds}) do
      :done ->
        {:done, acc}

      {:ok, bindings} ->
        next =
          try do
            fun.(bindings, acc)
          catch
            kind, reason ->
              stack = __STACKTRACE__
              # A consumer exception takes precedence over a cleanup exception.
              try do
                close(query, token)
              catch
                cleanup_kind, cleanup_reason ->
                  Logger.warning(
                    "Prolog cleanup failed: #{Exception.format_banner(cleanup_kind, cleanup_reason)}"
                  )
              end

              :erlang.raise(kind, reason, stack)
          end

        resume(query, token, next, fun)
    end
  end

  defp close(query, token), do: request(query, {:close, token})

  defp request(query, message) do
    case SWI.Session.request(query.session, message) do
      {:error, reason} -> raise SWI.Error, message: inspect(reason), reason: reason
      reply -> reply
    end
  end
end

defimpl Enumerable, for: SWI.Query do
  defdelegate reduce(query, acc, fun), to: SWI.Query
  def count(_), do: {:error, __MODULE__}
  def member?(_, _), do: {:error, __MODULE__}
  def slice(_), do: {:error, __MODULE__}
end
