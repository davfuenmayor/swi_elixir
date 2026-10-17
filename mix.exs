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
        build_tools: ["mix"],
        links: %{
          "License" => "https://opensource.org/license/mit",
          "SWI-Prolog" => "https://www.swi-prolog.org/"
        },
        files: [
          "lib",
          "c_src",
          "native",
          "priv/bridge.pl",
          "scripts/build-runtime.sh",
          "scripts/runtime-notices.exs",
          "Makefile",
          "mix.exs",
          "README.md",
          "MULTIPLATFORM.md",
          "LICENSE",
          "THIRD_PARTY_NOTICES.md"
        ]
      ],
      compilers: [:swi_native] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]
end

defmodule Mix.Tasks.Compile.SwiNative do
  use Mix.Task.Compiler

  def run(_) do
    os = :os.type()

    arch =
      if os == {:win32, :nt},
        do: System.get_env("PROCESSOR_ARCHITECTURE", "unknown"),
        else: to_string(:erlang.system_info(:system_architecture))

    if :erlang.system_info(:wordsize) != 8, do: Mix.raise("SWI requires a 64-bit Erlang runtime.")
    target = target(os, arch)
    archive = System.get_env("SWI_ELIXIR_BUNDLE") || "native/swi-10.0.1-#{target}.tar.gz"

    unless File.regular?(archive) do
      Mix.raise("The #{target} SWI bundle is missing from this package. See native/README.md.")
    end

    expected = File.read!(archive <> ".sha256") |> String.trim()
    {:ok, _} = Application.ensure_all_started(:crypto)
    actual = :crypto.hash(:sha256, File.read!(archive)) |> Base.encode16(case: :lower)
    if actual != expected, do: Mix.raise("SWI runtime archive checksum mismatch")

    result =
      if File.read("priv/swipl/.bundle") == {:ok, expected} and
           Enum.all?(
             [
               "priv/swipl/bin/swi_nif.#{if target == "windows-x86_64", do: "dll", else: "so"}",
               "priv/swipl/boot.prc",
               "priv/swipl/bin/swipl#{if target == "windows-x86_64", do: ".exe", else: ""}"
             ],
             &File.regular?/1
           ) do
        {:noop, []}
      else
        staging = "priv/.unpack-#{System.pid()}-#{System.unique_integer([:positive])}"
        File.mkdir_p!(staging)

        try do
          case :erl_tar.extract(String.to_charlist(archive), [
                 :compressed,
                 {:cwd, String.to_charlist(staging)}
               ]) do
            :ok -> :ok
            {:error, reason} -> Mix.raise("Cannot unpack SWI runtime: #{inspect(reason)}")
          end

          home = Path.join(staging, "swipl")

          unless File.read(Path.join(home, "target")) == {:ok, target <> "\n"},
            do: Mix.raise("SWI bundle does not match #{target}")

          File.write!(Path.join(home, ".bundle"), expected)

          unless File.read("priv/swipl/.bundle") == {:ok, expected} do
            File.rm_rf!("priv/swipl")

            case File.rename(home, "priv/swipl") do
              :ok ->
                :ok

              {:error, reason} ->
                unless File.read("priv/swipl/.bundle") == {:ok, expected},
                  do: Mix.raise("Cannot install SWI runtime: #{inspect(reason)}")
            end
          end

          {:ok, []}
        after
          File.rm_rf!(staging)
        end
      end

    # Windows may copy priv instead of symlinking it before custom compilers run.
    app_priv = Path.join(Mix.Project.app_path(), "priv")

    unless File.read(Path.join(app_priv, "swipl/.bundle")) == {:ok, expected} do
      File.mkdir_p!(app_priv)
      File.cp_r!("priv", app_priv)
    end

    result
  end

  def clean do
    File.rm_rf!("priv/swipl")
    :ok
  end

  def target(os, arch) do
    cpu = arch |> String.split("-") |> hd()

    case {os, cpu, String.contains?(arch, "musl")} do
      {{:unix, :linux}, "x86_64", false} -> "linux-x86_64"
      {{:unix, :linux}, "aarch64", false} -> "linux-aarch64"
      {{:unix, :darwin}, "x86_64", false} -> "macos-x86_64"
      {{:unix, :darwin}, cpu, false} when cpu in ["aarch64", "arm64"] -> "macos-aarch64"
      {{:win32, :nt}, cpu, false} when cpu in ["AMD64", "amd64", "x86_64"] -> "windows-x86_64"
      _ -> Mix.raise("Unsupported SWI platform: #{inspect(os)} / #{arch}. See native/README.md.")
    end
  end
end
