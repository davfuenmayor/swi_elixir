defmodule SWI.RuntimeTest do
  use ExUnit.Case, async: false
  import SWI.TestSupport, only: [temporary: 1]

  test "both backends run from a relocated application without system SWI or build tools" do
    app = temporary("with spaces/swi_elixir-0.1.0")
    File.mkdir_p!(app)
    File.cp_r!(Path.dirname(:code.which(SWI)), Path.join(app, "ebin"))
    File.cp_r!(Path.expand("priv"), Path.join(app, "priv"))
    bin = Path.join(app, "bin")
    File.mkdir!(bin)

    if :os.type() != {:win32, :nt} do
      File.cp!(System.find_executable("kill"), Path.join(bin, "kill"))
      File.chmod!(Path.join(bin, "kill"), 0o755)
    end

    script = """
    Application.load(:swi_elixir)
    System.put_env("PATH", #{inspect(bin)})
    System.put_env("SWI_HOME_DIR", "/nonexistent")
    System.delete_env("SWIPL")
    true = String.contains?(SWI.Runtime.home(), "with spaces")
    for backend <- [:port, :nif] do
      {:ok, prolog} = SWI.start_link(backend: backend)
      [%{"H" => home}] = Enum.to_list(SWI.query(prolog, "current_prolog_flag(home,H)"))
      {:atom, reported} = home
      reported = :json.encode(reported) |> IO.iodata_to_binary()
      expected = :json.encode(SWI.Runtime.home()) |> IO.iodata_to_binary()
      {:ok, true} = SWI.call(prolog, "same_file(" <> reported <> "," <> expected <> ")")
      [%{"X" => 1267650600228229401496703205376}] =
        Enum.to_list(SWI.query(prolog, "X is 2^100"))
      {:ok, true} = SWI.call(prolog, "use_module(library(clpfd))")
      :ok = SWI.stop(prolog)
    end
    IO.puts("relocated runtime verified")
    """

    script_path = Path.join(app, "runtime.exs")
    File.write!(script_path, script)

    {output, status} =
      System.cmd("elixir", ["-pa", Path.join(app, "ebin"), script_path],
        env: [{"ERL_FLAGS", "+S 2:2"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "relocated runtime verified"
  end
end
