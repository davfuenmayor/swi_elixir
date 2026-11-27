defmodule SWI.DistributionTest do
  use ExUnit.Case, async: false
  alias Mix.Tasks.Compile.SwiNative, as: Compiler

  @moduletag :tmp_dir
  setup %{tmp_dir: directory} do
    keys = ~w(SWI_CACHE_DIR SWI_RELEASE_BASE_URL SWI_ELIXIR_BUNDLE)
    previous = Map.new(keys, &{&1, System.get_env(&1)})
    System.put_env("SWI_CACHE_DIR", directory)

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    :ok
  end

  test "downloads verified bytes, repairs a corrupt cache, then works offline" do
    data = "fixture runtime bytes"
    manifest = manifest(data)
    {path, hash} = fetch(data, manifest)
    assert File.read!(path) == data
    File.write!(path, "corruption")
    assert {^path, ^hash} = fetch(data, manifest)
    System.put_env("SWI_RELEASE_BASE_URL", "http://127.0.0.1:1")
    assert {^path, ^hash} = Compiler.release_bundle("linux-x86_64", manifest)
    assert File.read!(path) == data
  end

  test "rejects a bad download before caching it", %{tmp_dir: directory} do
    assert_raise Mix.Error, ~r/checksum mismatch/, fn ->
      fetch("tampered", manifest("expected"))
    end

    assert Path.wildcard(Path.join([directory, "**", "*.tar.gz"])) == []
  end

  test "rejects stale source, unsafe filenames and insecure mirrors" do
    valid = manifest("data")

    assert_raise Mix.Error, ~r/Native sources differ/, fn ->
      Compiler.release_bundle("linux-x86_64", %{valid | "source_sha256" => "wrong"})
    end

    artifact = put_in(valid, ["artifacts", "linux-x86_64", "file"], "../escape")

    assert_raise Mix.Error, ~r/Invalid SWI artifact manifest/, fn ->
      Compiler.release_bundle("linux-x86_64", artifact)
    end

    System.put_env("SWI_RELEASE_BASE_URL", "http://example.com")

    assert_raise Mix.Error, ~r/require HTTPS/, fn ->
      Compiler.release_bundle("linux-x86_64", valid)
    end
  end

  test "a failed download names both release files and where to set the override" do
    error =
      assert_raise Mix.Error, fn ->
        fetch("bad response body", manifest("expected"), "404 Not Found")
      end

    url = "https://github.com/davfuenmayor/swi_elixir/releases/download/v0.1.0/swi-fixture.tar.gz"
    assert Exception.message(error) =~ "HTTP 404"
    assert Exception.message(error) =~ "\n  #{url}\n  #{url}.sha256"
    assert Exception.message(error) =~ "before Mix.install in Setup"
    refute Exception.message(error) =~ "bad response body"
  end

  test "a local archive needs its adjacent checksum file", %{tmp_dir: directory} do
    path = Path.join(directory, "bundle.tar.gz")
    System.put_env("SWI_ELIXIR_BUNDLE", path)
    assert_raise Mix.Error, ~r/archive not found/, fn -> Compiler.run([]) end

    File.write!(path, "fixture")
    assert_raise Mix.Error, ~r/bundle.tar.gz.sha256/, fn -> Compiler.run([]) end
  end

  defp manifest(data) do
    hash = :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

    %{
      "schema" => 1,
      "release" => "v0.1.0",
      "source_sha256" => Compiler.source_fingerprint(),
      "artifacts" => %{"linux-x86_64" => %{"file" => "swi-fixture.tar.gz", "sha256" => hash}}
    }
  end

  defp fetch(data, manifest, status \\ "200 OK") do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5_000)
        {:ok, _} = :gen_tcp.recv(socket, 0, 5_000)

        :ok =
          :gen_tcp.send(socket, [
            "HTTP/1.1 #{status}\r\nContent-Length: #{byte_size(data)}\r\nConnection: close\r\n\r\n",
            data
          ])

        :gen_tcp.close(socket)
      end)

    System.put_env("SWI_RELEASE_BASE_URL", "http://127.0.0.1:#{port}")

    try do
      Compiler.release_bundle("linux-x86_64", manifest)
    after
      :gen_tcp.close(listener)
      Task.await(server, 5_000)
    end
  end
end
