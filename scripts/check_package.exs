# Conservative Hex publication limits: 8,000,000 bytes compressed / 64,000,000 bytes uncompressed.
[path] = System.argv()
compressed = File.stat!(path).size
{:ok, outer} = :erl_tar.extract(String.to_charlist(path), [:memory])
{_, contents} = List.keyfind(outer, ~c"contents.tar.gz", 0)
uncompressed = contents |> :zlib.gunzip() |> byte_size()

if compressed >= 8_000_000 or uncompressed >= 64_000_000,
  do: raise("Package exceeds publication size budget")

{:ok, files} = :erl_tar.extract({:binary, contents}, [:compressed, :memory])

for {name, _} <- files do
  if Regex.match?(
       ~r/\.(so(?:\.\d+)*|dll|dylib|a|lib|exe|pdb|zip|tar(?:\.gz|\.xz|\.zst)?|tgz)$/i,
       to_string(name)
     ),
     do: raise("Native binary/archive leaked into source package: #{name}")
end

unless List.keymember?(files, ~c"native/manifest.json", 0), do: raise("Missing native manifest")

IO.puts(
  "PASS package: #{compressed} bytes compressed, #{uncompressed} bytes uncompressed; no native binaries"
)
