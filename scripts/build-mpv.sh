#!/usr/bin/env bash
# =============================================================================
# build-mpv.sh — build a vendored, version-pinned libmpv (+ libplacebo) so the
# app can ship a known, modern mpv instead of whatever the distro packages.
#
# Why vendored:
#   * mpv 0.41 needs libplacebo >= 7.360, but Debian 13 ships 7.349 (too old) and
#     mpv 0.40. We want mpv 0.41 with the gpu-next/Vulkan renderer.
#   * ffmpeg from the system (>= 7.1) is new enough, so we DON'T vendor it.
#
# Result: $PREFIX (.cache/mpv-prefix) containing libmpv.so + libplacebo.so + the
#   mpv CLI (handy for standalone testing) + their pkg-config files. The app's
#   CMake picks this up automatically when present (see CMakeLists.txt).
#
# Updating mpv later = bump the versions below and rerun. mpv stays 100% stock.
# =============================================================================
set -euo pipefail

MPV_VERSION="${MPV_VERSION:-0.41.0}"
LIBPLACEBO_VERSION="${LIBPLACEBO_VERSION:-7.360.1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$REPO_ROOT/.cache/mpv-src"
PREFIX="$REPO_ROOT/.cache/mpv-prefix"
JOBS="$(nproc)"

# The vendored prefix takes priority over system libs for both build and the
# verification run below.
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}"

mkdir -p "$SRC_DIR" "$PREFIX"
echo "==> repo:   $REPO_ROOT"
echo "==> prefix: $PREFIX"
echo "==> mpv $MPV_VERSION / libplacebo $LIBPLACEBO_VERSION / $JOBS jobs"

# ---------------------------------------------------------------------------
# libplacebo (only because the distro's is too old for mpv 0.41)
# ---------------------------------------------------------------------------
if pkg-config --exists libplacebo \
   && pkg-config --atleast-version="$LIBPLACEBO_VERSION" libplacebo; then
  echo "==> libplacebo >= $LIBPLACEBO_VERSION already in prefix — skipping"
else
  echo "==> Building libplacebo $LIBPLACEBO_VERSION"
  cd "$SRC_DIR"
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
if [ ! -d mpv ]; then
  git clone --depth 1 --branch "v$MPV_VERSION" \
    https://github.com/mpv-player/mpv.git
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
echo "==> DONE. App build: point PKG_CONFIG_PATH at $PREFIX/lib/pkgconfig"
