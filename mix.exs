defmodule SWIElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :swi_elixir,
      version: "0.1.0",
      description: "An Elixir wrapper for SWI-Prolog with Port and NIF backends",
      elixir: "~> 1.18",
      deps: [],
      package: [
        licenses: ["MIT"],
        links: %{
          "License" => "https://opensource.org/license/mit",
          "SWI-Prolog" => "https://www.swi-prolog.org/"
        },
        files: [
          "lib",
          "c_src",
          "priv/bridge.pl",
          "Makefile",
          "mix.exs",
          "README.md",
          "LICENSE",
          "THIRD_PARTY_NOTICES.md"
        ]
      ],
      compilers: [:swi_native] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod
    ]
  end

  def application, do: [extra_applications: [:logger]]
end

defmodule Mix.Tasks.Compile.SwiNative do
  use Mix.Task.Compiler

  def run(_) do
    if System.get_env("SWI_ELIXIR_SKIP_NIF") == "1" do
      {:noop, []}
    else
      {output, status} = System.cmd("make", ["-s"], stderr_to_stdout: true)
      IO.write(output)
      if status == 0, do: {:ok, []}, else: {:error, []}
    end
  end

  def clean, do: File.rm("priv/swi_nif.so")
end
