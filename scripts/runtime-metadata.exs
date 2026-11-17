Mix.start()
Code.require_file("mix.exs")
[archive, home] = System.argv()
{compiler, 0} = System.cmd(System.fetch_env!("SWI_BUILD_CC"), ["--version"])
{commit, 0} = System.cmd("git", ["rev-parse", "HEAD"])
hash = :crypto.hash(:sha256, File.read!(archive)) |> Base.encode16(case: :lower)

{inspector, flags} =
  case :os.type() do
    {:unix, :linux} -> {"readelf", ["-d"]}
    {:unix, :darwin} -> {"otool", ["-L"]}
    {:win32, :nt} -> {"objdump", ["-p"]}
  end

dependencies =
  Path.wildcard(Path.join(home, "**/*"))
  |> Enum.filter(
    &(File.regular?(&1) and
        Regex.match?(~r/(?:\/swipl|\.exe|\.dll|\.so(?:\.[0-9]+)*|\.dylib)$/, &1))
  )
  |> Enum.map(fn file ->
    {report, 0} = System.cmd(inspector, flags ++ [file], stderr_to_stdout: true)

    report =
      if :os.type() == {:win32, :nt},
        do:
          report
          |> String.split("\n")
          |> Enum.filter(&String.contains?(&1, "DLL Name:"))
          |> Enum.join("\n"),
        else: report

    if :os.type() == {:win32, :nt} and Regex.match?(~r/libgcc|libstdc\+\+|libwinpthread/i, report),
      do: raise("Non-system runtime DLL dependency in #{file}: #{report}")

    %{file: Path.relative_to(file, home), imports: report}
  end)

metadata = %{
  target: System.fetch_env!("SWI_TARGET"),
  sha256: hash,
  source_sha256: Mix.Tasks.Compile.SwiNative.source_fingerprint(),
  source_commit: String.trim(commit),
  swi_version: "10.0.1",
  compiler: String.trim(compiler),
  swi_commit: "e58621a91ab7dd530e1e8185ed518f63d851c414",
  libc:
    if(:os.type() == {:unix, :linux},
      do: System.cmd("ldd", ["--version"]) |> elem(0) |> String.split("\n") |> hd(),
      else: nil
    ),
  otp: to_string(:erlang.system_info(:otp_release)),
  runtime_nif_version: to_string(:erlang.system_info(:nif_version)),
  header_otp_version: "27.0",
  dependencies: dependencies,
  os: inspect(:os.type()),
  os_version: inspect(:os.version()),
  cflags: System.get_env("CFLAGS"),
  deployment_target: System.get_env("MACOSX_DEPLOYMENT_TARGET"),
  build_image: System.get_env("ImageOS"),
  build_image_version: System.get_env("ImageVersion"),
  ci_run: System.get_env("GITHUB_RUN_ID"),
  ci_attempt: System.get_env("GITHUB_RUN_ATTEMPT")
}

File.write!(archive <> ".json", JSON.encode!(metadata) <> "\n")
