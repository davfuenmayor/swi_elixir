# Native builds and releases

## Build locally

Install a C toolchain, CMake, Ninja, Git, curl, make and Elixir/OTP. Linux also
needs `patchelf` and glibc 2.31 or a matching sysroot. Use Xcode Command Line Tools
on macOS and MSYS2 MINGW64 on Windows. The macOS deployment target is 12.

```sh
git clone --branch V10.0.1 https://github.com/SWI-Prolog/swipl-devel.git ../swipl-devel
scripts/build-runtime.sh ../swipl-devel
export SWI_ELIXIR_BUNDLE=/absolute/path/to/the/printed/archive.tar.gz
mix test
```

Keep the `.sha256` sidecar. `SWI_ARTIFACT_DIR` sets the build output directory.
`SWI_CACHE_DIR` sets the download cache. Restart the BEAM after replacing a NIF.
For a system SWI executable, set `SWIPL` or pass `swipl:` to a Port session.

Wrapper CI checks formatting and packaging and tests against the published
runtime when the manifest matches. Native CI builds all five targets when
native inputs change or when started manually for a release.

## Release

1. Set the wrapper version in `mix.exs` on a release branch. Run native CI
   and collect the five archives, checksums and build records from one run.
   CI installs the package and runs both backends per target. Linux x86-64
   also runs the full suite.
2. Set `artifacts` to the download directory and `tag` to the wrapper
   version with a `v` prefix. Generate the manifest, commit it and push the tag.

   ```sh
   elixir scripts/prepare_native_manifest.exs "$artifacts" "$tag" > "$artifacts/manifest.json" &&
     cp "$artifacts/manifest.json" native/manifest.json
   ```

3. Create the draft release. Review the five archives and their sidecars
   before publishing.

   ```sh
   SWI_ARTIFACT_DIR="$artifacts" elixir scripts/publish_native.exs
   ```

4. Verify the public downloads and check both backends from an empty cache
   with `SWI_ELIXIR_BUNDLE` unset. Publish to Hex before fast-forwarding
   `main` so the Livebooks can resolve their pinned version. Runtime archives
   stay out of Git and Hex.

   ```sh
   mix hex.build -o swi.tar
   elixir scripts/check_package.exs swi.tar
   elixir scripts/check_packaged_install.exs swi.tar
   ```

Run **Livebook cold installs** manually in GitHub Actions to try the
notebooks against the public package and bundles on all five targets.
