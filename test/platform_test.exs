defmodule SWI.PlatformTest do
  use ExUnit.Case, async: true
  alias Mix.Tasks.Compile.SwiNative, as: Compiler

  test "selects an archive for every supported runtime architecture" do
    for {os, arch, target} <- [
          {{:unix, :linux}, "x86_64-pc-linux-gnu", "linux-x86_64"},
          {{:unix, :linux}, "aarch64-unknown-linux-gnu", "linux-aarch64"},
          {{:unix, :darwin}, "x86_64-apple-darwin", "macos-x86_64"},
          {{:unix, :darwin}, "aarch64-apple-darwin", "macos-aarch64"},
          {{:unix, :darwin}, "arm64-apple-darwin", "macos-aarch64"},
          {{:win32, :nt}, "AMD64", "windows-x86_64"}
        ] do
      assert Compiler.target(os, arch) == target
    end
  end

  test "rejects musl and unknown platforms instead of loading an incompatible binary" do
    for {os, arch} <- [
          {{:unix, :linux}, "x86_64-unknown-linux-musl"},
          {{:unix, :linux}, "aarch64-unknown-linux-musl"},
          {{:unix, :linux}, "riscv64-unknown-linux-gnu"},
          {{:win32, :nt}, "x86"},
          {{:win32, :nt}, "ARM64"},
          {{:unix, :freebsd}, "x86_64-unknown-freebsd"}
        ] do
      assert_raise Mix.Error, ~r/Unsupported SWI platform/, fn -> Compiler.target(os, arch) end
    end
  end
end
