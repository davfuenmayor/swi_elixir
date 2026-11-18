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

## Release

1. Set the wrapper version in `mix.exs`. Run native CI and collect the five
   archives, checksums and build records from one run. CI installs the package
   and runs both backends per target. Linux x86-64 also runs the full suite.
2. Generate the manifest. Commit it and push the matching tag.

   ```sh
   elixir scripts/prepare_native_manifest.exs /path/to/artifacts v0.1.0 > native/manifest.json
   ```

3. Create and publish the reviewed draft release. Use the tag matching `mix.exs`.

   ```sh
   SWI_ARTIFACT_DIR=/path/to/artifacts elixir scripts/publish_native.exs
   ```

4. On each target, install from an empty cache with `SWI_ELIXIR_BUNDLE` unset.
   Check both backends, then publish Hex. Runtime archives stay out of Git and Hex.

   ```sh
   mix hex.build -o swi.tar
   elixir scripts/check_package.exs swi.tar
   elixir scripts/check_packaged_install.exs swi.tar
   ```
