[source, output] = System.argv()

notices =
  ["src", "packages/clib", "packages/http", "packages/json", "packages/sgml"]
  |> Enum.flat_map(&Path.wildcard(Path.join([source, &1, "**/*.{c,h}"])))
  |> Enum.flat_map(fn file ->
    Regex.scan(~r{/\*.*?\*/}s, File.read!(file))
    |> Enum.map(&hd/1)
    |> Enum.filter(&Regex.match?(~r/copyright|permission is hereby|public domain|modified BSD/i, &1))
  end)
  |> Enum.uniq()
  |> Enum.join("\n\n")

File.write!(output, "SWI-Prolog source copyright and component notices\n\n" <> notices <> "\n")
