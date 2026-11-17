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
          "native/manifest.json",
          "native/README.md",
          "native/licenses",
          "priv/bridge.pl",
          "scripts/build-runtime.sh",
          "scripts/runtime-notices.exs",
          "scripts/runtime-metadata.exs",
          "scripts/check_native.exs",
          "MAINTAINING.md",
          ".gitattributes",
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

  def application, do: [extra_applications: [:logger, :crypto, :inets, :ssl]]
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
    {:ok, _} = Application.ensure_all_started(:crypto)

    {archive, expected} =
      case System.get_env("SWI_ELIXIR_BUNDLE") do
        nil -> release_bundle(target)
        path -> {path, File.read!(path <> ".sha256") |> String.trim()}
      end

    unless valid_archive?(archive, expected),
      do: Mix.raise("SWI runtime archive checksum mismatch")

    required = [
      "boot.prc",
      "bin/swi_nif.#{if target == "windows-x86_64", do: "dll", else: "so"}",
      "bin/swipl#{if target == "windows-x86_64", do: ".exe", else: ""}"
    ]

    installed? = fn ->
      File.read("priv/swipl/.bundle") == {:ok, expected} and
        Enum.all?(required, &File.regular?(Path.join("priv/swipl", &1)))
    end

    result =
      if installed?.() do
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

          unless Enum.all?(required, &File.regular?(Path.join(home, &1))),
            do: Mix.raise("SWI bundle is missing its executable, NIF or boot file")

          File.write!(Path.join(home, ".bundle"), expected)

          unless installed?.() do
            File.rm_rf!("priv/swipl")

            case File.rename(home, "priv/swipl") do
              :ok ->
                :ok

              {:error, reason} ->
                unless installed?.(),
                  do: Mix.raise("Cannot install SWI runtime: #{inspect(reason)}")
            end
          end

          {:ok, []}
        after
          File.rm_rf!(staging)
        end
      end

    # Windows may copy priv instead of symlinking it before custom compilers run.
    Mix.Project.build_structure()
    app_priv = Path.join(Mix.Project.app_path(), "priv")

    unless File.read(Path.join(app_priv, "swipl/.bundle")) == {:ok, expected} and
             Enum.all?(required, &File.regular?(Path.join([app_priv, "swipl", &1]))) do
      File.mkdir_p!(app_priv)
      File.cp_r!("priv", app_priv)
    end

    result
  end

  def source_fingerprint do
    paths =
      Enum.sort(
        Path.wildcard("c_src/**/*.{c,h}") ++
          Path.wildcard("native/licenses/*") ++
          ~w(Makefile scripts/build-runtime.sh scripts/runtime-notices.exs scripts/runtime-metadata.exs)
      )

    :crypto.hash(:sha256, [
      Mix.Project.config()[:version],
      <<0>>,
      Enum.map(paths, &[&1, <<0>>, File.read!(&1), <<0>>])
    ])
    |> Base.encode16(case: :lower)
  end

  defp valid_archive?(path, expected) do
    case File.read(path) do
      {:ok, data} -> Base.encode16(:crypto.hash(:sha256, data), case: :lower) == expected
      _ -> false
    end
  end

  @doc false
  def release_bundle(target, manifest \\ JSON.decode!(File.read!("native/manifest.json"))) do
    unless manifest["schema"] == 1 and manifest["source_sha256"] == source_fingerprint(),
      do:
        Mix.raise(
          "Native sources differ from the reviewed SWI manifest; build a new bundle explicitly"
        )

    artifact =
      manifest["artifacts"][target] ||
        Mix.raise(
          "No reviewed SWI artifact for #{target}. See MULTIPLATFORM.md; use SWI_ELIXIR_BUNDLE for a local build"
        )

    %{"file" => file, "sha256" => hash} = artifact
    release = manifest["release"]

    unless Path.basename(file) == file and Regex.match?(~r/^[a-f0-9]{64}$/, hash) and
             is_binary(release) and Regex.match?(~r/^v[0-9][a-zA-Z0-9._-]*$/, release),
           do: Mix.raise("Invalid SWI artifact manifest")

    cache =
      System.get_env("SWI_CACHE_DIR") || to_string(:filename.basedir(:user_cache, ~c"swi_elixir"))

    path = Path.join([cache, hash, file])

    unless valid_archive?(path, hash) do
      base =
        System.get_env(
          "SWI_RELEASE_BASE_URL",
          "https://github.com/davfuenmayor/swi_elixir/releases/download"
        )

      download_archive!(
        String.trim_trailing(base, "/") <> "/" <> release <> "/" <> file,
        path,
        hash
      )
    end

    {path, hash}
  end

  defp download_archive!(url, path, hash) do
    uri = URI.parse(url)

    unless uri.scheme == "https" or
             (uri.scheme == "http" and uri.host in ["127.0.0.1", "localhost"]),
           do: Mix.raise("SWI artifact downloads require HTTPS")

    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    data =
      case :httpc.request(
             :get,
             {String.to_charlist(url), []},
             [ssl: ssl, timeout: 120_000, connect_timeout: 15_000],
             body_format: :binary
           ) do
        {:ok, {{_, 200, _}, _, data}} ->
          data

        error ->
          Mix.raise(
            "Cannot download SWI artifact #{url}: #{inspect(error)}. Publish matching release assets or set SWI_ELIXIR_BUNDLE; see MAINTAINING.md"
          )
      end

    unless Base.encode16(:crypto.hash(:sha256, data), case: :lower) == hash,
      do: Mix.raise("Downloaded SWI archive checksum mismatch")

    File.mkdir_p!(Path.dirname(path))
    temporary = path <> ".#{System.pid()}.#{System.unique_integer([:positive])}.tmp"

    try do
      File.write!(temporary, data, [:exclusive])

      case File.rename(temporary, path) do
        :ok ->
          :ok

        {:error, reason} ->
          unless valid_archive?(path, hash) do
            File.rm(path)

            case File.rename(temporary, path) do
              :ok ->
                :ok

              {:error, _} ->
                unless valid_archive?(path, hash),
                  do: Mix.raise("Cannot cache SWI archive: #{inspect(reason)}")
            end
          end
      end
    after
      File.rm(temporary)
    end
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
