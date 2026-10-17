#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
host=$(uname -s)-$(uname -m)
case "$host" in
  Linux-x86_64) default_target=linux-x86_64 ;;
  Linux-aarch64) default_target=linux-aarch64 ;;
  Darwin-x86_64) default_target=macos-x86_64 ;;
  Darwin-arm64) default_target=macos-aarch64 ;;
  MINGW*-x86_64) default_target=windows-x86_64 ;;
  *) echo "Unsupported build host: $host" >&2; exit 1 ;;
esac
target=${SWI_TARGET:-$default_target}
repo=$(cd "${1:-../swipl-devel}" && pwd -P)
mkdir -p _native native/licenses
root=${SWI_BUILD_ROOT:-$(mktemp -d "$PWD/_native/runtime.XXXXXX")}
mkdir -p "$root"
root=$(cd "$root" && pwd -P)
cleanup() {
  if [ -z "${SWI_BUILD_ROOT:-}" ]; then
    git -C "$repo" worktree remove --force "$root/source" 2>/dev/null || true
    rm -r "$root"
  fi
}
trap cleanup EXIT
fetch() {
  [ -f "$2" ] || curl -fLsS "$1" -o "$2"
  elixir --erl '+S 1:1' -e 'actual = :crypto.hash(:sha256, File.read!(hd(System.argv()))) |> Base.encode16(case: :lower); if actual != List.last(System.argv()), do: raise("Download checksum mismatch")' "$2" "$3"
}

if [ ! -d "$root/source" ]; then
  git -C "$repo" worktree add --detach "$root/source" e58621a91ab7dd530e1e8185ed518f63d851c414
  git -C "$root/source" submodule update --init packages/clib packages/http packages/sgml packages/json
fi
# The bridge uses HTTP's JSON API, without its optional TLS client.
sed -i.bak 's/set(SWIPL_PKG_DEPS_http clib sgml json ssl)/set(SWIPL_PKG_DEPS_http clib sgml json)/' "$root/source/cmake/PackageSelection.cmake"
sed -i.bak '/^clib_plugin(crypt$/,/PL_LIBS crypt.pl)/d' "$root/source/packages/clib/CMakeLists.txt"

flags=()
cmake_flags=()
compiler=${CC:-cc}
strip_command=strip
strip_flags=()
nif_ext=so
case "$target" in
  linux-x86_64) triplet=x86_64-linux-gnu ;;
  linux-aarch64)
    triplet=aarch64-linux-gnu
    if [ "$default_target" != "$target" ]; then
      compiler=aarch64-linux-gnu-gcc
      strip_command=aarch64-linux-gnu-strip
      cmake_flags+=(-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64
        -DCMAKE_C_COMPILER="$compiler" -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++
        "-DCMAKE_CROSSCOMPILING_EMULATOR=qemu-aarch64-static;-L;${SWI_BUILD_SYSROOT:-/usr/aarch64-linux-gnu}")
    fi
    ;;
  macos-x86_64|macos-aarch64)
    [ "$default_target" = "$target" ] || { echo 'Build macOS bundles on matching macOS runners.' >&2; exit 1; }
    export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-12.0}
    strip_flags=(-x)
    cmake_flags+=(-DBUILD_MACOS_BUNDLE=OFF -DMACOSX_DEPENDENCIES_FROM=None
      "-DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET")
    ;;
  windows-x86_64)
    # Windows preserves all 32 exit bits, including SWI's internal unwind flag.
    sed -i.bak 's/exit(status);/exit(status \& ~PL_HALT_WITH_EXCEPTION);/g' "$root/source/src/pl-fli.c"
    nif_ext=dll
    flags+=(-static -static-libgcc)
    cmake_flags+=(-DWIN32_DLLS= -DCMAKE_SHARED_LINKER_FLAGS=-static -DCMAKE_MODULE_LINKER_FLAGS=-static)
    if [ "$default_target" != "$target" ]; then
      compiler=x86_64-w64-mingw32-gcc-posix
      strip_command=x86_64-w64-mingw32-strip
      cmake_flags+=(-DCMAKE_SYSTEM_NAME=Windows -DCMAKE_C_COMPILER="$compiler"
        -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++-posix
        -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres -DCMAKE_CROSSCOMPILING_EMULATOR=wine)
      export WINEDEBUG=-all WINEARCH=win64
      export WINEPREFIX=${WINEPREFIX:-$PWD/_native/wine}
      wineboot -u
    fi
    ;;
  *) echo "Unsupported build target: $target" >&2; exit 1 ;;
esac
if [ -n "${SWI_BUILD_SYSROOT:-}" ]; then
  flags+=("--sysroot=$SWI_BUILD_SYSROOT" "-B$SWI_BUILD_SYSROOT/usr/lib/$triplet/")
  cmake_flags+=("-DCMAKE_SYSROOT=$SWI_BUILD_SYSROOT")
fi
read -r -a user_flags <<< "${CFLAGS:-}"
flags+=("${user_flags[@]}")

fetch https://zlib.net/fossils/zlib-1.3.2.tar.gz "$root/zlib.tar.gz" bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16
mkdir -p "$root/zlib"
tar -xzf "$root/zlib.tar.gz" -C "$root/zlib" --strip-components=1
(
  cd "$root/zlib"
  CC="$compiler" CFLAGS="-O2 -fPIC ${flags[*]}" ./configure --static --prefix="$root/zlib-prefix"
  make -j "${BUILD_JOBS:-4}"
  make install
)

cmake -S "$root/source" -B "$root/build" -G Ninja \
  "${cmake_flags[@]}" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$root/install" \
  -DCMAKE_C_FLAGS="${flags[*]}" -DCMAKE_CXX_FLAGS="${flags[*]}" \
  -DUSE_GMP=OFF -DUSE_LIBBF=ON -DUSE_TCMALLOC=OFF \
  -DINSTALL_DOCUMENTATION=OFF -DBUILD_TESTING=OFF \
  '-DSWIPL_PACKAGE_LIST=clib;http' -DZLIB_ROOT="$root/zlib-prefix" \
  -DZLIB_LIBRARY="$root/zlib-prefix/lib/libz.a" -DZLIB_INCLUDE_DIR="$root/zlib-prefix/include" \
  -DZLIB_USE_STATIC_LIBS=ON -DCMAKE_DISABLE_FIND_PACKAGE_Curses=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_LibUUID=ON
cmake --build "$root/build" -j "${BUILD_JOBS:-4}"
cmake --install "$root/build"

# Normalize executable locations, keeping SWI's architecture-specific plugins.
elixir --erl '+S 1:1' -e 'File.rm_rf!(hd(System.argv()))' "$root/stage"
mkdir -p "$root/stage"
if [ "$target" = windows-x86_64 ]; then
  cp -a "$root/install" "$root/stage/swipl"
  libdir="$root/stage/swipl/bin"
else
  cp -a "$root/install/lib/swipl" "$root/stage/swipl"
  for executable in "$root/stage/swipl"/bin/*/swipl; do
    arch=$(basename "$(dirname "$executable")")
    cp "$executable" "$root/stage/swipl/bin/swipl"
  done
  libdir="$root/stage/swipl/lib/$arch"
fi
home="$root/stage/swipl"
echo "$target" > "$home/target"
elixir --erl '+S 1:1' -e '
  [home] = System.argv()
  for path <- Path.wildcard(home <> "/**/*.qlf"), do: File.rm!(path)
  for path <- ~w(cmake app customize demo doc library/http/web library/ext/http/http/web), do: File.rm_rf!(Path.join(home,path))
  for path <- Path.wildcard(home <> "/bin/*") do
    if File.dir?(path) or (String.ends_with?(path, ".exe") and Path.basename(path) != "swipl.exe"), do: File.rm_rf!(path)
  end
' "$home"

mkdir -p "$root/otp"
fetch https://raw.githubusercontent.com/erlang/otp/OTP-27.0/erts/emulator/beam/erl_nif.h "$root/otp/erl_nif.h" beb942fe93d08ddc0d3014788bb5008f59b8f5e58d42f6523ca147d04fd15015
fetch https://raw.githubusercontent.com/erlang/otp/OTP-27.0/erts/emulator/beam/erl_drv_nif.h "$root/otp/erl_drv_nif.h" eb95a13eafe45b5984893fc1ccddbc7151a2e81e67c21cc327e2d65b15d2b51c
fetch https://raw.githubusercontent.com/erlang/otp/OTP-27.0/erts/emulator/beam/erl_nif_api_funcs.h "$root/otp/erl_nif_api_funcs.h" 182774c90e4c3c730fa312e2c0c423e5c0017ff4726cbef14de5128265cabada
include=$(erl +S 1:1 -noshell -eval 'io:format("~s/usr/include", [code:root_dir()]), halt().')
cp "$include/erl_int_sizes_config.h" "$root/otp/"
if [ "$target" = windows-x86_64 ]; then
  sed -i.bak 's/#define SIZEOF_LONG 8/#define SIZEOF_LONG 4/' "$root/otp/erl_int_sizes_config.h"
fi
sed -n '/%CopyrightBegin%/,/%CopyrightEnd%/p' "$root/otp/"*.h > native/licenses/Erlang-NOTICES.txt
make -B CC="$compiler" ERL_INCLUDE="$root/otp" SWI_HOME="$home" SWI_LIBDIR="$libdir" \
  TARGET="$home/bin/swi_nif.$nif_ext" NIF_EXT="$nif_ext" CFLAGS="-O2 -Wall -Wextra -Werror ${flags[*]}"

case "$target" in
  linux-*)
    patchelf --set-rpath "\$ORIGIN/../lib/$arch" "$home/bin/swipl"
    for library in "$libdir"/*.so*; do
      [ -L "$library" ] || patchelf --set-rpath '$ORIGIN' "$library"
    done
    ;;
  macos-*)
    for binary in "$home/bin/swipl" "$home/bin/swi_nif.so" "$libdir"/*.so "$libdir"/*.dylib; do
      [ -L "$binary" ] && continue
      while read -r dependency; do
        case "$dependency" in
          */libswipl*.dylib) install_name_tool -change "$dependency" "@rpath/$(basename "$dependency")" "$binary" ;;
        esac
      done < <(otool -L "$binary" | awk 'NR>1 {print $1}')
      while read -r old_rpath; do
        install_name_tool -delete_rpath "$old_rpath" "$binary"
      done < <(otool -l "$binary" | awk '/cmd LC_RPATH/ {getline; getline; sub(/^[[:space:]]*path /, ""); sub(/ \(offset.*$/, ""); print}')
      case "$binary" in
        "$home/bin/"*) rpath="@loader_path/../lib/$arch" ;;
        *) rpath='@loader_path' ;;
      esac
      install_name_tool -add_rpath "$rpath" "$binary"
      case "$binary" in *.dylib) install_name_tool -id "@rpath/$(basename "$binary")" "$binary" ;; esac
    done
    ;;
esac
elixir --erl '+S 1:1' scripts/runtime-notices.exs "$root/source" native/licenses/SWI-Prolog-NOTICES.txt
cp "$root/source/LICENSE" native/licenses/SWI-Prolog-LICENSE.txt
cp "$root/zlib/LICENSE" native/licenses/zlib-LICENSE.txt
cp -a native/licenses "$home/"
for binary in "$home"/bin/swipl* "$home/bin/swi_nif.$nif_ext" "$libdir"/*; do
  [ -L "$binary" ] && continue
  case "$binary" in *.so*|*.dylib|*.dll|*/swipl|*.exe) ;; *) continue ;; esac
  "$strip_command" "${strip_flags[@]}" "$binary"
  if [[ "$target" == linux-* ]]; then
    required=$(readelf --version-info "$binary" | sed -n 's/.*Name: GLIBC_\([0-9.]*\).*/\1/p' | sort -V | tail -n 1)
    if [ "$(printf '%s\n' "$required" 2.31 | sort -V | tail -n 1)" != 2.31 ]; then
      echo "$binary requires glibc $required; build on glibc 2.31 or set SWI_BUILD_SYSROOT." >&2
      exit 1
    fi
  fi
done
# Sign only after all Mach-O modifications, including strip.
if [[ "$target" == macos-* ]]; then
  for binary in "$home/bin/swipl" "$home/bin/swi_nif.so" "$libdir"/*.so "$libdir"/*.dylib; do
    [ -L "$binary" ] || codesign --force --sign - "$binary"
  done
fi
archive="native/swi-10.0.1-$target.tar.gz"
tar -czf "$archive" -C "$root/stage" swipl
elixir --erl '+S 1:1' -e '[file] = System.argv(); hash = :crypto.hash(:sha256, File.read!(file)) |> Base.encode16(case: :lower); File.write!(file <> ".sha256", hash <> "\n")' "$archive"
