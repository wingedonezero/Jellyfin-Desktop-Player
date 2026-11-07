#!/usr/bin/env bash
# =============================================================================
# build.sh — the one command that produces the Jellyfin Desktop AppImage.
#
#   ./build.sh              build everything → dist/Jellyfin-Desktop-x86_64.AppImage
#   ./build.sh install      same, then copy it over ~/Jellyfin_Desktop-x86_64.AppImage
#                           (override the target with INSTALL_PATH=/some/where.AppImage)
#   ./build.sh app          just the binary → build/jellyfin-desktop (no AppImage)
#   ./build.sh deps         (re)build the vendored libmpv/libplacebo + patched QtWayland
#   ./build.sh clean        remove build/, dist/ and the AppDir (keeps the vendored deps)
#   ./build.sh clean-all    also remove .cache/ (vendored deps + sources + tools)
#
# What it chains (each step is its own script under scripts/, usable alone):
#   1. scripts/build-mpv.sh       vendored mpv 0.41 + libplacebo with our Wayland
#                                 subsurface-embed patch → .cache/mpv-prefix
#                                 (only when missing; the distro mpv can't embed)
#   2. scripts/build-qtwayland.sh patched QtWaylandClient matching the SYSTEM Qt
#                                 → .cache/qtwayland-prefix (only when missing;
#                                 stock qtwayland segfaults on screen blank)
#   3. cmake configure + build    → build/jellyfin-desktop
#   4. scripts/bundle.sh          → dist/Jellyfin-Desktop-x86_64.AppImage
#
# Running it again rebuilds only what changed. The vendored deps live under
# .cache/ (gitignored) and are per-checkout: a fresh clone builds them once
# (expect several minutes for mpv + libplacebo), after that only the app.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"

mode="${1:-appimage}"
case "$mode" in
  appimage|install|app|deps|clean|clean-all) ;;
  -h|--help|help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "usage: $0 [appimage|install|app|deps|clean|clean-all]" >&2; exit 2 ;;
esac

MPV_PREFIX="$ROOT/.cache/mpv-prefix"
QTWL_PREFIX="$ROOT/.cache/qtwayland-prefix"
APPIMAGE="$ROOT/dist/Jellyfin-Desktop-x86_64.AppImage"
INSTALL_PATH="${INSTALL_PATH:-$HOME/Jellyfin_Desktop-x86_64.AppImage}"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# clean
# ---------------------------------------------------------------------------
if [ "$mode" = clean ] || [ "$mode" = clean-all ]; then
  say "removing build/ dist/ .cache/AppDir"
  rm -rf "$ROOT/build" "$ROOT/dist" "$ROOT/.cache/AppDir"
  if [ "$mode" = clean-all ]; then
    say "removing .cache/ (vendored deps, sources, deploy tools)"
    rm -rf "$ROOT/.cache"
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# tools
# ---------------------------------------------------------------------------
missing=
for tool in cmake ninja meson git pkg-config qmake6 patchelf curl; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
  echo "build.sh: missing tools:$missing" >&2
  echo "          Debian/Ubuntu: sudo apt install build-essential cmake ninja-build meson git pkg-config patchelf curl \\" >&2
  echo "                         qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-wayland-dev" >&2
  exit 1
fi
SYSTEM_QT="$(qmake6 -query QT_VERSION)"
case "$SYSTEM_QT" in 6.*) ;; *) echo "build.sh: need Qt 6 (qmake6 reports '$SYSTEM_QT')" >&2; exit 1 ;; esac

# ---------------------------------------------------------------------------
# 1+2. vendored deps (built when missing, or always with `deps`)
# ---------------------------------------------------------------------------
# The mpv prefix bakes its absolute path into the .pc files — a checkout that
# was moved/copied has a stale prefix that pkg-config would resolve elsewhere.
mpv_ok=0
if [ -f "$MPV_PREFIX/lib/pkgconfig/mpv.pc" ] \
   && grep -q "^prefix=$MPV_PREFIX\$" "$MPV_PREFIX/lib/pkgconfig/mpv.pc"; then
  mpv_ok=1
elif [ -f "$MPV_PREFIX/lib/pkgconfig/mpv.pc" ]; then
  echo "build.sh: .cache/mpv-prefix was built for another path — rebuilding it" >&2
  rm -rf "$MPV_PREFIX" "$ROOT/.cache/mpv-src"
fi
if [ "$mode" = deps ] || [ "$mpv_ok" = 0 ]; then
  say "vendored mpv + libplacebo (scripts/build-mpv.sh)"
  scripts/build-mpv.sh
fi

qtwl_ok=0
ls "$QTWL_PREFIX"/lib/x86_64-linux-gnu/libQt6WaylandClient.so.6.* >/dev/null 2>&1 && qtwl_ok=1
# The bundled lib must match the system Qt's ABI; rebuild after a Qt upgrade.
if [ "$qtwl_ok" = 1 ] && ! ls "$QTWL_PREFIX"/lib/x86_64-linux-gnu/libQt6WaylandClient.so."$SYSTEM_QT" >/dev/null 2>&1; then
  echo "build.sh: .cache/qtwayland-prefix doesn't match system Qt $SYSTEM_QT — rebuilding it" >&2
  rm -rf "$QTWL_PREFIX" "$ROOT/.cache/qtwayland-src"
  qtwl_ok=0
fi
if [ "$mode" = deps ] || [ "$qtwl_ok" = 0 ]; then
  say "vendored patched QtWaylandClient $SYSTEM_QT (scripts/build-qtwayland.sh)"
  QTWAYLAND_VERSION="$SYSTEM_QT" scripts/build-qtwayland.sh
fi
[ "$mode" = deps ] && { say "deps done"; exit 0; }

# ---------------------------------------------------------------------------
# 3. the app
# ---------------------------------------------------------------------------
# Configure once (or again if the cache is gone / was made before the vendored
# mpv existed — CMake caches which libmpv it found).
if [ ! -f "$ROOT/build/CMakeCache.txt" ] \
   || ! grep -q "mpv-prefix" "$ROOT/build/CMakeCache.txt" 2>/dev/null; then
  say "cmake configure"
  cmake -B "$ROOT/build" -G Ninja -DCMAKE_BUILD_TYPE=Release
fi
say "cmake build"
cmake --build "$ROOT/build"
[ "$mode" = app ] && { say "done: $ROOT/build/jellyfin-desktop"; exit 0; }

# ---------------------------------------------------------------------------
# 4. the AppImage
# ---------------------------------------------------------------------------
say "AppImage (scripts/bundle.sh)"
scripts/bundle.sh

if [ "$mode" = install ]; then
  say "installing → $INSTALL_PATH"
  cp -f "$APPIMAGE" "$INSTALL_PATH"
  chmod +x "$INSTALL_PATH"
fi

say "done"
ls -la "$APPIMAGE"
[ "$mode" = install ] && ls -la "$INSTALL_PATH"
exit 0
