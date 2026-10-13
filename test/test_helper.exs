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
end

ExUnit.start()
