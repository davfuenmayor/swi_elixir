# elixir scripts/prepare_native_manifest.exs ARTIFACT_DIR RELEASE_TAG > reviewed.json
Mix.start()
Code.require_file("mix.exs")
[directory, release] = System.argv()

unless release == "v#{Mix.Project.config()[:version]}",
  do: raise("Release must match the wrapper version")

source = Mix.Tasks.Compile.SwiNative.source_fingerprint()
targets = ~w(linux-x86_64 linux-aarch64 windows-x86_64 macos-x86_64 macos-aarch64)

artifacts =
  Map.new(targets, fn target ->
    file = "swi_elixir-#{Mix.Project.config()[:version]}-#{target}.tar.gz"
    path = Path.join(directory, file)
    metadata = (path <> ".json") |> File.read!() |> JSON.decode!()
    hash = :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

    for {valid, reason} <- [
          {metadata["source_sha256"] == source, "native source mismatch"},
          {metadata["sha256"] == hash, "archive checksum mismatch"},
          {metadata["target"] == target, "target mismatch"},
          {String.trim(File.read!(path <> ".sha256")) == hash, "sidecar checksum mismatch"}
        ] do
      unless valid, do: raise("#{target}: #{reason}")
    end

    {target, %{"file" => file, "sha256" => hash, "build" => metadata}}
  end)

IO.puts(JSON.encode!(%{schema: 1, release: release, source_sha256: source, artifacts: artifacts}))
