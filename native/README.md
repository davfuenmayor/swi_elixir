# Bundled runtimes

This directory contains relocatable SWI-Prolog 10.0.1 runtimes and their matching
NIFs, named `swi-10.0.1-<target>.tar.gz`. Each archive has a `.sha256` file;
Mix verifies both the checksum and embedded target before extraction. Available
bundles need no separate SWI installation or native compilation.

See [MULTIPLATFORM.md](../MULTIPLATFORM.md) for platform status, build
prerequisites, native and cross-build commands, local bundle overrides, test
procedures, and remaining validation work. macOS archives are not yet built.

The runtime uses LibBF and statically linked zlib 1.3.2. Optional dependencies
such as readline, TLS, and GUI extensions are excluded. It is a compact runtime
for the wrapper and notebooks rather than a full desktop SWI distribution.
Component terms and notices are in [licenses/](licenses/) and accompany the
extracted runtime. Windows also includes applicable MinGW/GCC runtime notices.

For local C shim development, run `mix compile`, then `make -B` on Unix or
`make -B NIF_EXT=dll` in Windows MINGW64. This builds against the extracted
runtime using your installed OTP headers. Rebuild the archive before
distributing a shim change.
