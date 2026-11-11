#!/usr/bin/env bash
# =============================================================================
# build-mpv.sh — build a vendored, version-pinned libmpv (+ libplacebo) so the
# app can ship a known, modern mpv instead of whatever the distro packages.
#
# Why vendored:
#   * mpv 0.42 needs libplacebo >= 7.387, but Debian 13 ships 7.349 (too old) and
#     mpv 0.40. We want mpv 0.42 with the gpu-next/Vulkan renderer.
#   * ffmpeg from the system (>= 6.1; Debian has 7.1) is new enough, so we DON'T
#     vendor it. Also needs Vulkan headers >= 1.4.309, libwayland >= 1.23,
#     wayland-protocols >= 1.38 (all satisfied by Debian 13).
#   * libcurl dev headers are optional: without them mpv's curl network backend
#     is simply left out and ffmpeg does the HTTP, as before 0.42.
#
# Result: $PREFIX (.cache/mpv-prefix) containing libmpv.so + libplacebo.so + the
#   mpv CLI (handy for standalone testing) + their pkg-config files. The app's
#   CMake picks this up automatically when present (see CMakeLists.txt).
#
# Updating mpv later = bump the versions below and rerun (build.sh notices the
# pin changed and rebuilds). The only non-stock part is patches/mpv/*.patch.
# =============================================================================
set -euo pipefail

MPV_VERSION="${MPV_VERSION:-0.42.0}"
LIBPLACEBO_VERSION="${LIBPLACEBO_VERSION:-7.387.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$REPO_ROOT/.cache/mpv-src"
PREFIX="$REPO_ROOT/.cache/mpv-prefix"
JOBS="$(nproc)"

# What a finished prefix was built from: the two pins + the exact patch set.
# Written to $PREFIX/.jfd-stamp at the end; `--stamp` prints the value this
# checkout expects, so build.sh can tell a stale prefix from a current one.
PATCH_HASH="$(cat "$REPO_ROOT"/patches/mpv/*.patch 2>/dev/null | sha256sum | cut -c1-16)"
STAMP="mpv=$MPV_VERSION libplacebo=$LIBPLACEBO_VERSION patches=$PATCH_HASH"
if [ "${1:-}" = "--stamp" ]; then echo "$STAMP"; exit 0; fi

# The vendored prefix takes priority over system libs for both build and the
# verification run below.
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}"

mkdir -p "$SRC_DIR" "$PREFIX"
echo "==> repo:   $REPO_ROOT"
echo "==> prefix: $PREFIX"
echo "==> mpv $MPV_VERSION / libplacebo $LIBPLACEBO_VERSION / $JOBS jobs"

# ---------------------------------------------------------------------------
# libplacebo (only because the distro's is too old for mpv 0.42)
# ---------------------------------------------------------------------------
if pkg-config --exists libplacebo \
   && pkg-config --atleast-version="$LIBPLACEBO_VERSION" libplacebo; then
  echo "==> libplacebo >= $LIBPLACEBO_VERSION already in prefix — skipping"
else
  echo "==> Building libplacebo $LIBPLACEBO_VERSION"
  cd "$SRC_DIR"
  # a checkout of another version (left from before a pin bump) is useless
  if [ -d libplacebo ] && [ "$(git -C libplacebo describe --tags 2>/dev/null)" != "v$LIBPLACEBO_VERSION" ]; then
    echo "==> libplacebo source is not v$LIBPLACEBO_VERSION — re-fetching"
    rm -rf libplacebo
  fi
  if [ ! -d libplacebo ]; then
    git clone --recursive --depth 1 --branch "v$LIBPLACEBO_VERSION" \
      https://code.videolan.org/videolan/libplacebo.git
  fi
  cd libplacebo
  rm -rf build
  # demos/tests pull extra deps (glfw/SDL) we don't need; glslang is present so
  # shaderc isn't required; libdovi/unwind are optional and absent here.
  meson setup build --prefix="$PREFIX" --libdir=lib --buildtype=release \
    -Dvulkan=enabled -Dopengl=enabled -Dglslang=enabled -Dshaderc=disabled \
    -Dlcms=enabled -Ddemos=false -Dtests=false
  meson compile -C build -j "$JOBS"
  meson install -C build
  echo "==> libplacebo installed: $(pkg-config --modversion libplacebo)"
fi

# ---------------------------------------------------------------------------
# mpv (libmpv + the CLI for standalone testing)
# ---------------------------------------------------------------------------
echo "==> Building mpv $MPV_VERSION"
cd "$SRC_DIR"
# The source tree is only reusable if it is this exact version with this exact
# patch set applied (.jfd-patches records what was applied). Anything else —
# a pin bump, an edited patch — starts from a fresh clone, because re-applying
# patches onto an already-patched tree would conflict.
# (Porting a patch by hand in this tree? Regenerate the patch file with
#  `git -C .cache/mpv-src/mpv diff`, then `echo <new hash> > .jfd-patches`, or
#  just let the next run re-clone and prove the patch applies cleanly.)
if [ -d mpv ] && { [ "$(cat mpv/MPV_VERSION 2>/dev/null)" != "$MPV_VERSION" ] \
                   || [ "$(cat mpv/.jfd-patches 2>/dev/null)" != "$PATCH_HASH" ]; }; then
  echo "==> mpv source is not $MPV_VERSION with the current patch set — re-fetching"
  rm -rf mpv
fi
if [ ! -d mpv ]; then
  git clone --depth 1 --branch "v$MPV_VERSION" \
    https://github.com/mpv-player/mpv.git
  for p in "$REPO_ROOT"/patches/mpv/*.patch; do
    [ -e "$p" ] || continue
    echo "==> applying patch $(basename "$p")"
    git -C mpv apply "$p" || { echo "ERROR: patch failed: $p (needs re-port for $MPV_VERSION)"; rm -rf mpv; exit 1; }
  done
  echo "$PATCH_HASH" > mpv/.jfd-patches
fi
cd mpv
rm -rf build
# Force the renderer-critical features ON (deps verified present) so the build
# fails loudly if something's missing rather than silently disabling Vulkan.
# Everything else auto-detects (all needed -dev packages are installed).
meson setup build --prefix="$PREFIX" --libdir=lib --buildtype=release \
  -Dlibmpv=true -Dcplayer=true \
  -Dvulkan=enabled -Dx11=enabled -Dwayland=enabled
meson compile -C build -j "$JOBS"
meson install -C build

# ---------------------------------------------------------------------------
# Verify the vendored build
# ---------------------------------------------------------------------------
echo
echo "===================== VENDORED BUILD SUMMARY ====================="
echo "libmpv:     $(pkg-config --modversion mpv)"
echo "libplacebo: $(pkg-config --modversion libplacebo)"
echo "--- mpv --version (vendored) ---"
"$PREFIX/bin/mpv" --version 2>/dev/null | head -3
echo "--- gpu-next + vulkan available? ---"
"$PREFIX/bin/mpv" --vo=help 2>/dev/null | grep -iE "gpu-next|gpu " || true
"$PREFIX/bin/mpv" --gpu-api=help 2>/dev/null | grep -iE "vulkan" || true
echo "=================================================================="
echo "$STAMP" > "$PREFIX/.jfd-stamp"
echo "==> DONE. App build: point PKG_CONFIG_PATH at $PREFIX/lib/pkgconfig"
