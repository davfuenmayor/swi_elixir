# Multiplatform builds and validation

Requires 64-bit Elixir 1.18+ and OTP 27+. Git and Hex contain sources, the artifact
manifest and notices. Release archives contain SWI and its matching C NIF. Ports
and NIF share the same installation.

## CI matrix

| Target | Native CI environment | Build requirements |
| --- | --- | --- |
| Linux x86-64 | Ubuntu 20.04 container on an x86-64 runner | C/C++, CMake, Ninja, make, patchelf, git, curl |
| Linux ARM64 | Ubuntu 20.04 container on an ARM64 runner | Same; native ARM64 toolchain |
| Windows x86-64 | Windows 2022, MSYS2 MINGW64 | MinGW-w64 GCC/G++, CMake, Ninja, make, binutils, git, curl |
| macOS Intel | Intel macOS 15 | Xcode Command Line Tools, CMake, Ninja, make, git, curl |
| macOS Apple Silicon | ARM64 macOS 15 | Same; native ARM64 toolchain |

Jobs run independently without fail-fast cancellation. CI uploads candidate
artifacts but has no publication permission. Automatic installation requires an
approved manifest entry and a matching public release asset; otherwise use an
explicit local bundle when developing an unpublished version.

Linux enforces a maximum glibc symbol requirement of 2.31. macOS requests
deployment target 12; Windows targets Windows 10+. These settings do not replace
execution on the minimum supported OS. Musl, 32-bit runtimes and Windows ARM64
are outside the matrix.

## Build locally

Install the tools above plus Elixir/OTP. On macOS, use `brew install cmake ninja`;
on Windows, use an MSYS2 MINGW64 shell with Windows Elixir/OTP on PATH. Linux
builds need glibc 2.31 or a suitable development sysroot.

```sh
git clone --branch V10.0.1 https://github.com/SWI-Prolog/swipl-devel.git ../swipl-devel
scripts/build-runtime.sh ../swipl-devel
export SWI_ELIXIR_BUNDLE=/absolute/path/printed/as/SWI_NATIVE_ARCHIVE
mix compile
mix run scripts/check_native.exs
```

The builder pins SWI, zlib and OTP NIF headers. The compact runtime uses LibBF
and static zlib, without optional TLS/GUI/readline extensions. Relative library
paths and component notices travel with the runtime. Windows clears SWI's unwind
bit from exit codes; macOS modifies load paths and strips before ad-hoc signing.

Outputs are `swi_elixir-<wrapper-version>-<target>.tar.gz`, `.sha256` and `.json`.
Builds and generated notices stay outside the checkout. Override locations with
`SWI_BUILD_CACHE`, `SWI_BUILD_ROOT` and `SWI_ARTIFACT_DIR`. `BUILD_JOBS` limits
parallelism. `SWI_BUILD_SYSROOT` selects a Linux sysroot; `SWI_TARGET` enables
supported cross-builds. Emulated execution does not replace native CI.

Private CPU-tuned builds may use `CFLAGS='-O3 -mcpu=native'` on Apple Silicon
or `CFLAGS='-O3 -march=native'` on Intel/AMD. Keep those on matching CPUs and
measure performance and compatibility before using them elsewhere.

## Validate

Fast installer and target checks:

```sh
mix test test/distribution_test.exs test/platform_test.exs
mix run scripts/check_native.exs
```

CI installs the source package and runs the same Port and NIF smoke check on
each target. The check exercises bignums, CLPFD and exceptions. The Linux x86-64
job also runs the full `mix test` suite, including query timeouts, fault injection,
and relocated execution without system SWI.

```sh
mix hex.build -o /tmp/swi.tar
elixir scripts/check_package.exs /tmp/swi.tar
elixir scripts/check_packaged_install.exs /tmp/swi.tar
```

The package guard rejects binary/archive payloads. The consumer check extracts
the package into a path containing spaces and installs it with `Mix.install/1`,
the same entry point used by Livebook.
CI uses its explicitly built bundle. Public delivery must also be tested without
that override, with an empty cache, on every target. Evaluate Livebooks on native
runtimes before advertising notebook support; lesson content is unchanged.

See [MAINTAINING.md](MAINTAINING.md) for artifact review, immutable draft releases,
anonymous download checks and Hex publication order.
