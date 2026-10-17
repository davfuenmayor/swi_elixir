defmodule SWI.TestSupport do
  import ExUnit.Assertions

  def wait_until(fun, attempts \\ 200)
  def wait_until(fun, 0), do: assert(fun.())

  def wait_until(fun, attempts) do
    unless fun.() do
      Process.sleep(10)
      wait_until(fun, attempts - 1)
    end
  end

  def temporary(name) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "swi-test-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)
    Path.join(dir, name)
  end

  def os_process_alive?(pid) do
    case :os.type() do
      {:win32, :nt} ->
        tasklist = Path.join([System.fetch_env!("SystemRoot"), "System32", "tasklist.exe"])
        {output, 0} = System.cmd(tasklist, ["/FI", "PID eq #{pid}", "/FO", "CSV", "/NH"])
        String.contains?(output, ~s(","#{pid}","))

      _ ->
        {_, status} = System.cmd("kill", ["-0", to_string(pid)], stderr_to_stdout: true)
        status == 0
    end
  end
end

ExUnit.start()
