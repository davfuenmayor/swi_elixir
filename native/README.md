# Native runtime distribution

This directory contains the reviewed release manifest and redistribution notices.
Runtime archives, libraries and executables are excluded from Git and Hex.

`manifest.json` records a release tag, native source fingerprint, and one archive
filename, SHA-256 and build record per approved target. Native CI builds and tests
the artifacts; maintainers review them and publish versioned release assets.

Mix downloads the selected archive into an external SHA-256-keyed cache. It
verifies the committed digest, embedded target and required files before
installation. Each complete `swipl/` archive contains the executable, boot image,
matching NIF, libraries and [component notices](licenses/). Both backends share it.

For development, run `scripts/build-runtime.sh`, then set `SWI_ELIXIR_BUNDLE`
to the printed absolute archive path, keeping its `.sha256` sidecar. This is an
explicit trusted override, not an automatic fallback.

See [MULTIPLATFORM.md](../MULTIPLATFORM.md) for builds and validation and
[MAINTAINING.md](../MAINTAINING.md) for release preparation.
