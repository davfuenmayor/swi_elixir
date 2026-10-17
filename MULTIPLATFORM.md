# Multiplatform builds and tests

This document records bundle construction, validation, and remaining work.
Normal users need 64-bit Elixir 1.18+ and OTP 27+. Mix selects, verifies, and
extracts an available bundle; no SWI installation or compiler is needed.

## Status

Results from this workspace, 2026-10-17:

| Target | Build | Validation |
| --- | --- | --- |
| `linux-x86_64` | Built against glibc 2.31 | Native Debian 13, Elixir 1.20.4 / OTP 29: **126 tests passed**; all six lesson notebooks evaluated twice successfully. |
| `linux-aarch64` | Cross-built against glibc 2.31 | ARM64 OTP 27 / Elixir 1.18.3 in QEMU: full suite **not passed**; Port startup exceeded its deadline under emulation. |
| `windows-x86_64` | Cross-built with MinGW-w64 | Windows OTP 29 / Elixir 1.20.4 under Wine: both backend smoke checks passed; full suite **125 passed, 1 skipped**. The skip is the Linux-only resource diagnostic. |
| `macos-x86_64` | Build path prepared; no archive | Needs an Intel macOS build/test runner. |
| `macos-aarch64` | Build path prepared; no archive | Needs an Apple Silicon macOS build/test runner. |

Intended minimums are glibc 2.31, Windows 10, and macOS 12. The test hosts above
do not establish compatibility with every older OS. macOS is **not available
out of the box yet**. Musl/Alpine, 32-bit runtimes, and Windows ARM64 are
excluded. Match the running BEAM's architecture, including under emulation.

## Native builds

From this project checkout:

```sh
git clone --branch V10.0.1 https://github.com/SWI-Prolog/swipl-devel.git ../swipl-devel
scripts/build-runtime.sh ../swipl-devel
```

| Build host | Prerequisites |
| --- | --- |
| Linux glibc | C/C++ toolchain, make, CMake, Ninja, patchelf, git, curl, tar, Elixir/OTP. Build on glibc 2.31 or provide a compatible development sysroot. |
| macOS | Xcode Command Line Tools, `brew install cmake ninja`, git, curl, make, Elixir/OTP. Use a machine matching the target CPU. This path is unverified. |
| Windows | MSYS2 **MINGW64** Bash, MinGW-w64 GCC/G++, binutils, make, CMake, Ninja, git, curl, tar, and Windows Elixir/OTP on `PATH`. Native building remains unverified; the existing archive was cross-built. |

The builder pins SWI-Prolog 10.0.1 and downloads checksum-verified zlib 1.3.2
and OTP 27 NIF headers. Outputs are `native/swi-10.0.1-<target>.tar.gz` and
`.sha256`. Each archive contains a complete `swipl/` home, matching NIF,
target metadata, headers, and component notices.

The runtime uses LibBF and static zlib, excluding optional TLS/GUI/crypt
dependencies. Linux uses relative ELF search paths and rejects GLIBC symbol
requirements newer than 2.31. The macOS path rewrites Mach-O load paths and
applies ad-hoc signatures. Windows keeps DLLs beside the NIF and statically
links GCC/pthread dependencies. The Windows build also clears SWI's internal
unwind flag from process exit codes so `halt(7)` returns status 7. See
[the builder](scripts/build-runtime.sh) for exact inputs and local patches.

Optional build settings:

- `SWI_BUILD_SYSROOT=/absolute/path`: Linux development sysroot, including libc headers and startup objects.
- `SWI_BUILD_ROOT=/absolute/path`: retain build artifacts for incremental builds and diagnosis; otherwise temporary files are removed.
- `BUILD_JOBS=4`: compilation parallelism.
- `CFLAGS='-O3 -mcpu=native'` on Apple Silicon, or `CFLAGS='-O3 -march=native'` on Intel/AMD: local CPU tuning. Share tuned bundles only with matching CPUs and measure any improvements.

## Cross-builds used here

On Linux x86-64, using Debian 11 development sysroots:

```sh
SWI_BUILD_SYSROOT=/absolute/sysroots/debian11-amd64 \
  scripts/build-runtime.sh ../swipl-devel

SWI_TARGET=linux-aarch64 \
  SWI_BUILD_SYSROOT=/absolute/sysroots/debian11-arm64 \
  scripts/build-runtime.sh ../swipl-devel

SWI_TARGET=windows-x86_64 scripts/build-runtime.sh ../swipl-devel
```

ARM cross-building needs `aarch64-linux-gnu-gcc`, G++, binutils, and
`qemu-aarch64-static`; target SWI runs during boot-image generation. Windows
cross-building needs POSIX MinGW-w64 GCC/G++, windres, and Wine. macOS builds
require matching macOS machines; none was available in this workspace.

## Bring your own bundle

Set `SWI_ELIXIR_BUNDLE` to the archive's absolute native path before compiling
or starting Livebook. Keep its matching `.sha256` file alongside it. Mix still
checks both checksum and target. For example, in PowerShell:

```powershell
$env:SWI_ELIXIR_BUNDLE = 'C:\bundles\swi-10.0.1-windows-x86_64.tar.gz'
mix clean
mix test
```

On macOS/Linux:

```sh
export SWI_ELIXIR_BUNDLE=/absolute/bundles/swi-10.0.1-macos-aarch64.tar.gz
mix clean
mix test
```

Restart the BEAM/Livebook runtime after changing bundles: embedded SWI remains
loaded for the VM's lifetime. A local build permits CPU tuning and testing on
your machine; improved performance or reliability must be measured. Supply
the complete matching bundle rather than replacing only `libswipl`. The Port
backend additionally accepts a separate executable through `swipl:` or `SWIPL`.

## Test procedure

Run on each target OS/CPU, first with minimum supported OTP/Elixir and then
current versions. In a fresh BEAM VM:

```sh
mix clean
mix test
elixir scripts/check_livebooks.exs
```

The full suite compiles a fault-injection NIF, so maintainers need a compiler
and make for that step. End users do not. For cross-target tests without a
guest compiler, set `SWI_TEST_NIF` to a separately built fault shim compiled
from `c_src/swi_nif.c` with `-DSWI_NIF_TESTING`, the target ABI, and the bundle's
libraries. Production and fault shims run in separate BEAM processes.

Tests cover both backends, query equivalence, exceptions, timeouts, restarts,
cleanup, concurrent engines, scheduler responsiveness, real prover/ILP
examples, and native failure paths. The relocation test copies the application
to a path containing spaces, clears SWI configuration, restricts `PATH`, and
checks both backends in a fresh VM. The Linux `/proc` resource diagnostic is
intentionally skipped elsewhere.

The notebook checker evaluates all six lessons twice in one VM. Also open
`livebooks/intro.livemd` and evaluate each lesson in an actual Livebook runtime
without system SWI; the script alone does not validate the UI/runtime setup.

Before distribution, run `mix hex.build`, install the package in a fresh
project without SWI or a compiler, and exercise both backends. Check corrupted
checksums and wrong-target rejection, relocated native dependencies, included
notices, and the final package size against the package host's limit.

The current three-bundle Hex package was checked on Linux x86-64: a fresh
installation ran both backends with SWI and build tools absent from `PATH`,
and modifying the archive caused checksum rejection before extraction.
These results do not cover the other targets or the future macOS archives.

### Emulation used in this workspace

- **ARM64:** QEMU `virt`, two CPUs, 2 GiB RAM, Debian ARM64 kernel/root
  filesystem, actual ARM64 OTP 27.3.4.1 and Elixir 1.18.3. The bundle and
  cross-built fault shim were copied into the guest before running Mix tests.
  Slow TCG execution exceeded Port startup deadlines; this is not a pass.
- **Windows:** Wine 10, actual Windows OTP 29.1.1, Elixir 1.20.4 BEAM files,
  and Windows launcher. A separate project copy avoids loading another
  target's native libraries. Restricted `PATH` includes Windows Erlang/Elixir
  and system tools, without SWI or a compiler. Both backends passed large
  integer, recursive query, loading, timeout, and shutdown smoke checks.
  Wine coverage does not replace real Windows validation.

## Leftovers before declaring all targets ready

1. **macOS:** obtain Intel and Apple Silicon runners, build both missing
   archives, inspect dependencies/signatures, run the suite and Livebooks,
   and validate the intended macOS 12 baseline.
2. **ARM64:** rerun after the Elixir 1.18 NIF load-order fix, then finish on
   real hardware or faster virtualization. Diagnose startup latency before
   changing production deadlines. The emulated full suite has not passed.
3. **Windows:** validate native MSYS2 building and run the full suite and
   Livebooks on actual Windows 10+. The apparent GC cleanup failure was a
   test bug: an unescaped Windows temporary path produced a Prolog syntax
   error, and the test checked transport success without inspecting the
   response status. JSON-quoting the path and asserting `ok`/`solution`
   responses fixes the focused test on both Linux and Windows/Wine. The full
   Windows/Wine rerun passed 125 tests with one Linux-only diagnostic skipped
   in 80.4 seconds. No C cleanup change was needed. Earlier portability fixes covered batch
   quoting, path casing, bridge reload, and SWI process exit status.
4. **Compatibility:** complete the OTP 27/current OTP matrix and oldest-OS
   checks on every target. ELF symbol inspection alone does not prove that
   the runtime works on older Linux installations.
5. **Distribution:** repeat compiler-free Hex installs, checksum/target
   rejection, and actual Livebook runs for every final archive. Toolchain
   notices have been added to all three existing archives; verify package
   size again when both future macOS archives are included.
6. Update this matrix and the README from recorded passes. Five-platform
   out-of-the-box support is not yet established.
