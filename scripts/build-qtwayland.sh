#!/usr/bin/env bash
# =============================================================================
# build-qtwayland.sh — build a vendored, patched QtWaylandClient (client only).
#
# Why: on our shared wl_display (Qt + embedded mpv are ONE Wayland client, see
# patches/mpv/0001-wayland-embed-subsurface.patch), output/surface churn — e.g.
# screens blanking — can deliver events whose object argument demarshals to
# NULL (a libwayland "zombie": the proxy was destroyed with events in flight).
# Stock qtwayland's generated fromObject() feeds that NULL straight into
# wl_proxy_get_listener() and segfaults (verified from core dumps: crash in
# QWaylandScreen::fromWlOutput on screen blank). Upstream 6.8.2 has no guard.
#
# patches/qtwayland/* adds a null check to the scanner-generated fromObject()
# for every interface. The version MUST match the system Qt (ABI): the built
# libQt6WaylandClient replaces the system copy inside the AppImage only —
# nothing is installed system-wide.
#
# Result: $PREFIX (.cache/qtwayland-prefix); bundle.sh overlays it into the
# AppDir after linuxdeploy's Qt deploy. Rerun after a system Qt minor upgrade
# (bump QTWAYLAND_VERSION to match `qmake6 -query QT_VERSION`).
# =============================================================================
set -euo pipefail

QTWAYLAND_VERSION="${QTWAYLAND_VERSION:-6.8.2}"
JOBS="${JOBS:-$(nproc)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$REPO_ROOT/.cache/qtwayland-src"
PREFIX="$REPO_ROOT/.cache/qtwayland-prefix"

SYSTEM_QT="$(qmake6 -query QT_VERSION 2>/dev/null || echo unknown)"
if [ "$SYSTEM_QT" != "$QTWAYLAND_VERSION" ]; then
  echo "ERROR: system Qt is $SYSTEM_QT but building qtwayland $QTWAYLAND_VERSION."
  echo "       The bundled lib must match the system Qt ABI — set QTWAYLAND_VERSION=$SYSTEM_QT."
  exit 1
fi

echo "==> qtwayland $QTWAYLAND_VERSION (client only) / $JOBS jobs"
echo "==> prefix: $PREFIX"
mkdir -p "$(dirname "$SRC_DIR")"

if [ ! -d "$SRC_DIR" ]; then
  git clone --depth 1 --branch "v$QTWAYLAND_VERSION" \
    https://github.com/qt/qtwayland.git "$SRC_DIR"
  # Apply our patches only on a fresh clone (re-applying would conflict).
  # Update = delete .cache/qtwayland-src, bump version, rerun.
  for p in "$REPO_ROOT"/patches/qtwayland/*.patch; do
    [ -e "$p" ] || continue
    echo "==> applying patch $(basename "$p")"
    git -C "$SRC_DIR" apply "$p" || { echo "ERROR: patch failed: $p (needs re-port for $QTWAYLAND_VERSION)"; exit 1; }
  done
fi

# Client only: the compositor half needs qt6-declarative private headers and we
# don't ship a compositor.
cmake -S "$SRC_DIR" -B "$SRC_DIR/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DFEATURE_wayland_server=OFF \
  -DQT_BUILD_EXAMPLES=OFF \
  -DQT_BUILD_TESTS=OFF
cmake --build "$SRC_DIR/build" --parallel "$JOBS"
cmake --install "$SRC_DIR/build"

LIBDIR="$PREFIX/lib/x86_64-linux-gnu"
echo
echo "================== VENDORED QTWAYLAND SUMMARY =================="
ls "$LIBDIR"/libQt6WaylandClient.so.* | head -2
echo "null guard present in generated code:"
grep -A2 "wl_output \*wl_output::fromObject" \
  "$SRC_DIR/build/src/client/qwayland-wayland.cpp" | head -4 || true
echo "================================================================"
echo "==> DONE. bundle.sh overlays this into the AppImage."
