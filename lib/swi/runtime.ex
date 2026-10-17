defmodule SWI.Runtime do
  @moduledoc false

  def home, do: Path.join(:code.priv_dir(:swi_elixir), "swipl")

  def executable do
    name = if :os.type() == {:win32, :nt}, do: "swipl.exe", else: "swipl"
    Path.join(home(), "bin/#{name}")
  end

  def nif, do: Path.join(home(), "bin/swi_nif")

  def kill(pid) do
    case :os.type() do
      {:win32, :nt} ->
        command = Path.join([System.fetch_env!("SystemRoot"), "System32", "taskkill.exe"])
        System.cmd(command, ["/F", "/PID", Integer.to_string(pid)], stderr_to_stdout: true)

      _ ->
        System.cmd("kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)
    end
  end
end
