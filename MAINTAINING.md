# Native distribution

## Release artifacts

Git and Hex contain sources, notices and `native/manifest.json`, not runtime
archives. Build, test and review all five targets before publication. The manifest
must describe the reviewed artifacts and their build provenance. Publish Hex only
after anonymous release downloads and source-package installs pass.

## Local development

For a source build, clone SWI-Prolog and run:

```sh
git clone --branch V10.0.1 https://github.com/SWI-Prolog/swipl-devel.git ../swipl-devel
scripts/build-runtime.sh ../swipl-devel
# Set SWI_ELIXIR_BUNDLE to the absolute SWI_NATIVE_ARCHIVE path printed above.
export SWI_ELIXIR_BUNDLE=/absolute/path/to/archive.tar.gz
mix compile
mix run scripts/check_native.exs
```

Keep the SHA-256 sidecar with an offline bundle. This explicit override is trusted
maintainer input and bypasses release/source matching, but still verifies the
sidecar hash, target and required payload. It is never selected implicitly from
the source directory. Native source changes require a rebuilt bundle.

Build work and archives default outside the checkout, under the user's cache.
`SWI_BUILD_CACHE`, `SWI_BUILD_ROOT` and `SWI_ARTIFACT_DIR` override build locations.
The builder generates notices in staging, leaving committed license files alone.
`SWI_CACHE_DIR` controls verified download storage, keyed by SHA-256.
`SWI_RELEASE_BASE_URL` selects an HTTPS release mirror; plain HTTP is allowed only
on localhost for tests. It never bypasses manifest hashes. TLS certificates are
verified. Cache corruption triggers a verified replacement; cached installs can
work offline. Restart BEAM after replacing a NIF.

## Prepare a release

1. Choose an unused wrapper version and update `mix.exs` before building. SWI's
   version is separate. Native source fingerprints cover the C shim, Makefile,
   build/metadata/notices scripts and committed licenses, with LF source endings.
2. Run **Native SWI builds** on the reviewed source. It builds/tests native
   Linux x86-64/ARM64, Windows x86-64 and both Macs. Linux builds in Ubuntu 20.04
   to retain glibc 2.31; macOS requests deployment target 12. Native runner versions
   do not prove minimum-OS compatibility. The workflow has read-only permissions
   and never publishes.
   Linux containers use OTP 27 / Elixir 1.18; Windows and Macs use OTP 29 /
   Elixir 1.20. Linux explicitly selects
   the container's ImageOS for setup-beam rather than the newer host runner.
3. Review both backend tests, library dependencies, licenses and the unpacked
   source-package checks. Obtain archives, `.sha256` and `.json` from one reviewed
   CI run. Do not mix native source fingerprints or claim cross/Wine/QEMU checks
   as native validation. Inspect ELF dependencies, Mach-O load paths and Windows
   imports; retain all redistribution notices in each complete runtime.
4. Generate a candidate manifest and review every target and build record:

   ```sh
   elixir scripts/prepare_native_manifest.exs /absolute/artifacts v0.1.0 > /tmp/swi-manifest.json
   ```

   Substitute the chosen unused tag. Copy the approved candidate into
   `native/manifest.json`, commit it, tag the reviewed commit and push that tag.
   The builder's archives include the wrapper version. Keep source files unchanged
   between the builds and manifest approval; rebuild if native inputs change.
5. With authenticated GitHub CLI, prepare the draft release:

   ```sh
   SWI_ARTIFACT_DIR=/absolute/artifacts elixir scripts/publish_native.exs
   ```

   This requires a clean tagged checkout and all five artifacts with matching
   build metadata. It only creates a draft and refuses to replace an existing
   release. Review its assets and enable GitHub release immutability before
   publishing. Never overwrite assets or move published tags.
6. Verify anonymous cold-cache downloads on every native target, without an
   offline override or authenticated mirror. Then verify a warm offline cache:

   ```sh
   export SWI_CACHE_DIR="$(mktemp -d)"
   unset SWI_ELIXIR_BUNDLE SWI_RELEASE_BASE_URL
   mix compile
   mix run scripts/check_native.exs
   SWI_RELEASE_BASE_URL=https://offline.invalid mix compile
   mix hex.build -o /tmp/swi.tar
   elixir scripts/check_package.exs /tmp/swi.tar
   elixir scripts/check_packaged_install.exs /tmp/swi.tar
   ```

   Use another empty cache for the final unpacked-package check. Candidate CI
   uses an explicit bundle override and does not establish public download delivery.
   Run the Livebook checker on supported native runtimes before claiming support.
7. Publish Hex from the reviewed release tag. The package guard rejects binary
   payloads and enforces conservative package budgets. Check Hex's current limits
   when publishing. Subsequent releases repeat the same review; never silently
   reuse a mismatched payload for changed native code.

Release immutability: https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases .
