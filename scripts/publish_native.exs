# Run after committing/tagging the release: elixir scripts/publish_native.exs
Mix.start()
Code.require_file("mix.exs")
version = Mix.Project.config()[:version]
tag = "v#{version}"

run! = fn command, args ->
  case System.cmd(command, args, stderr_to_stdout: true) do
    {output, 0} -> String.trim(output)
    {output, _} -> raise "#{command} failed: #{output}"
  end
end

gh =
  System.find_executable("gh") ||
    raise "Publishing needs GitHub CLI (gh) and authenticated release access."

run!.(gh, ["auth", "status"])

unless run!.("git", ["status", "--porcelain"]) == "",
  do: raise("Commit the reviewed release changes before publishing.")

unless run!.("git", ["rev-parse", "HEAD"]) ==
         run!.("git", ["rev-parse", "refs/tags/#{tag}^{commit}"]),
       do: raise("The release tag #{tag} must point to the current source commit.")

manifest = "native/manifest.json" |> File.read!() |> JSON.decode!()
required = ~w(linux-x86_64 linux-aarch64 windows-x86_64 macos-x86_64 macos-aarch64)

unless Enum.sort(Map.keys(manifest["artifacts"])) == Enum.sort(required),
  do: raise("Review artifacts for the complete five-target matrix before preparing a release")

unless manifest["source_sha256"] == Mix.Tasks.Compile.SwiNative.source_fingerprint() and
         manifest["release"] == tag,
       do: raise("Release manifest does not match tagged native source/version")

directory = System.fetch_env!("SWI_ARTIFACT_DIR")

archives =
  Enum.map(required, fn target ->
    artifact = manifest["artifacts"][target]

    unless artifact["build"]["source_sha256"] == manifest["source_sha256"] and
             artifact["build"]["target"] == target,
           do: raise("Artifact provenance does not match native source/target")

    path = Path.join(directory, artifact["file"])
    actual = :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
    unless actual == artifact["sha256"], do: raise("Artifact checksum mismatch: #{path}")
    metadata = (path <> ".json") |> File.read!() |> JSON.decode!()
    unless metadata == artifact["build"], do: raise("Artifact build provenance mismatch")

    unless String.trim(File.read!(path <> ".sha256")) == actual,
      do: raise("Sidecar checksum mismatch")

    path
  end)

repo = "davfuenmayor/swi_elixir"

case System.cmd(gh, ["release", "view", tag, "--repo", repo], stderr_to_stdout: true) do
  {_, 0} -> raise "Release #{tag} already exists; its artifacts will not be replaced."
  _ -> :ok
end

notes = Path.join("dist", "release_notes.md")
File.mkdir_p!("dist")

File.write!(
  notes,
  "SWI Elixir #{version}\n\nSWI-Prolog runtime and matching NIF. See MULTIPLATFORM.md and THIRD_PARTY_NOTICES.md at this tag.\n"
)

run!.(
  gh,
  [
    "release",
    "create",
    tag,
    "--repo",
    repo,
    "--draft",
    "--verify-tag",
    "--title",
    "SWI Elixir #{version}",
    "--notes-file",
    notes
  ] ++ Enum.flat_map(archives, &[&1, &1 <> ".sha256", &1 <> ".json"])
)

IO.puts(
  "Prepared draft #{repo} release #{tag}. Review assets and enable release immutability before publishing; publish Hex only after verified anonymous downloads work."
)
