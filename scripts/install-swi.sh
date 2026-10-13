#!/usr/bin/env bash
set -euo pipefail
# Build a pinned stable version from the existing checkout, without changing it.
repo=$(realpath "${1:-../swipl-devel}")
revision=${SWI_REVISION:-V10.0.1}
prefix=${SWI_PREFIX:-/usr/local}
build_root=$(mktemp -d)
cleanup() {
  git -C "$repo" worktree remove --force "$build_root/source" 2>/dev/null || true
  rm -rf "$build_root"
}
trap cleanup EXIT

git -C "$repo" worktree add --detach "$build_root/source" "$revision"
git -C "$build_root/source" submodule update --init \
  packages/clib packages/http packages/sgml packages/json packages/ssl packages/zlib
cmake -S "$build_root/source" -B "$build_root/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DINSTALL_DOCUMENTATION=OFF '-DSWIPL_PACKAGE_LIST=clib;http'
cmake --build "$build_root/build" -j "${BUILD_JOBS:-4}"
cmake --install "$build_root/build"
"$prefix/bin/swipl" --version
