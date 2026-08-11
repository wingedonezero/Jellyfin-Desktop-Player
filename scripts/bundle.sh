#!/usr/bin/env bash
# =============================================================================
# bundle.sh — package jellyfin-desktop into a portable, self-contained AppImage.
#
# Bundles Qt6 + the vendored libmpv/libplacebo + ffmpeg + every non-system dep,
# with relative ($ORIGIN) rpaths, so the single .AppImage runs from anywhere and
# on other machines (same arch) — no dependence on this worktree's paths.
#
# Prereqs: scripts/build-mpv.sh has run (vendored mpv in .cache/mpv-prefix), and
# the deploy tools are in .cache/tools (linuxdeploy, linuxdeploy-plugin-qt,
# appimagetool — fetched once; see README/commit).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WT="$(cd "$SCRIPT_DIR/.." && pwd)"
PREFIX="$WT/.cache/mpv-prefix"
TOOLS="$WT/.cache/tools"
APPDIR="$WT/.cache/AppDir"
OUT="$WT/dist"

export APPIMAGE_EXTRACT_AND_RUN=1            # run the tool AppImages without FUSE
export PATH="$TOOLS:$PATH"

# Fetch the deploy tools once (idempotent).
mkdir -p "$TOOLS"
fetch() { [ -f "$TOOLS/$1" ] || { echo "==> fetching $1"; curl -fsSL -o "$TOOLS/$1" "$2"; chmod +x "$TOOLS/$1"; }; }
fetch linuxdeploy.AppImage           https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
fetch linuxdeploy-plugin-qt.AppImage https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage
fetch appimagetool.AppImage          https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage

# linuxdeploy finds plugins/appimagetool by these exact names on PATH:
ln -sf linuxdeploy-plugin-qt.AppImage "$TOOLS/linuxdeploy-plugin-qt"
ln -sf appimagetool.AppImage          "$TOOLS/appimagetool"

# 1. build the app against the vendored mpv
cmake --build "$WT/build"
echo "==> app built"

# 2. AppDir skeleton + desktop entry + icon
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" \
         "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/128x128/apps"
cp "$WT/build/jellyfin-desktop" "$APPDIR/usr/bin/"

cat > "$APPDIR/usr/share/applications/jellyfin-desktop.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Jellyfin Desktop
Comment=Native Qt6/mpv Jellyfin client
Exec=jellyfin-desktop
Icon=jellyfin-desktop
Categories=AudioVideo;Player;
Terminal=false
EOF

# placeholder icon (mpv's, from the vendored prefix) — swap a real one later
ICON="$APPDIR/usr/share/icons/hicolor/128x128/apps/jellyfin-desktop.png"
cp "$PREFIX/share/icons/hicolor/128x128/apps/mpv.png" "$ICON"

# 3. deploy Qt (incl. QML modules + platform plugins) + mpv + non-system deps
export QMAKE="$(command -v qmake6 || echo /usr/lib/qt6/bin/qmake6)"
export QML_SOURCES_PATHS="$WT/src/qml"       # so the qt plugin bundles the right QML modules
export LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}"  # so libmpv/libplacebo are found
export EXTRA_PLATFORM_PLUGINS="libqwayland-egl.so;libqwayland-generic.so"

rm -rf "$OUT"; mkdir -p "$OUT"
# Populate the AppDir (Qt + mpv + every non-system dep), but DON'T let the
# plugin emit the AppImage — under extract-and-run its temp cwd can swallow the
# output. Pack it ourselves to an explicit path instead.
linuxdeploy.AppImage --appdir "$APPDIR" \
  --executable "$APPDIR/usr/bin/jellyfin-desktop" \
  --desktop-file "$APPDIR/usr/share/applications/jellyfin-desktop.desktop" \
  --icon-file "$ICON" \
  --plugin qt

# linuxdeploy-plugin-qt bundles the wayland PLATFORM plugin but misses the
# Wayland client-buffer / shell / decoration INTEGRATION plugins — without them
# Qt aborts: "Failed to load client buffer integration: wayland-egl". Add them
# and point their rpath at the bundled Qt libs.
QTPLUGINS="$(qmake6 -query QT_INSTALL_PLUGINS 2>/dev/null || echo /usr/lib/x86_64-linux-gnu/qt6/plugins)"
for cat in wayland-graphics-integration-client wayland-shell-integration wayland-decoration-client; do
  [ -d "$QTPLUGINS/$cat" ] || continue
  mkdir -p "$APPDIR/usr/plugins/$cat"
  cp "$QTPLUGINS/$cat"/*.so "$APPDIR/usr/plugins/$cat/" 2>/dev/null || true
  patchelf --set-rpath '$ORIGIN/../../lib' "$APPDIR/usr/plugins/$cat"/*.so 2>/dev/null || true
done
echo "==> added Wayland integration plugins"

# 3.5. Overlay the vendored, null-guarded QtWaylandClient (scripts/
# build-qtwayland.sh) over the system copies linuxdeploy just bundled — the
# stock lib segfaults on zombie wl_output/wl_surface event args, which our
# shared-display mpv embed provokes whenever screens blank (see
# patches/qtwayland/). Same-version ABI, so third-party extras that link it
# (adwaita decoration, layer-shell) keep working.
QTWL="$WT/.cache/qtwayland-prefix/lib/x86_64-linux-gnu"
if [ -d "$QTWL" ]; then
  for lib in libQt6WaylandClient libQt6WaylandEglClientHwIntegration libQt6WlShellIntegration; do
    cp "$QTWL/$lib".so.6.* "$APPDIR/usr/lib/$lib.so.6"   # .so.6.x.y → the bundled .so.6
    patchelf --set-rpath '$ORIGIN' "$APPDIR/usr/lib/$lib.so.6"  # like linuxdeploy's deployed libs
  done
  cp "$QTWL"/qt6/plugins/platforms/libqwayland-*.so "$APPDIR/usr/plugins/platforms/"
  patchelf --set-rpath '$ORIGIN/../../lib' "$APPDIR/usr/plugins/platforms"/libqwayland-*.so
  for cat in wayland-graphics-integration-client wayland-shell-integration wayland-decoration-client; do
    [ -d "$QTWL/qt6/plugins/$cat" ] || continue
    cp "$QTWL/qt6/plugins/$cat"/*.so "$APPDIR/usr/plugins/$cat/"
    patchelf --set-rpath '$ORIGIN/../../lib' "$APPDIR/usr/plugins/$cat"/*.so
  done
  echo "==> overlaid patched QtWaylandClient"
else
  echo "WARNING: no vendored qtwayland ($QTWL) — bundling stock (crashy) QtWaylandClient." >&2
  echo "         Run scripts/build-qtwayland.sh first." >&2
fi

# Pack with an ABSOLUTE AppDir path — appimagetool runs from a temp cwd under
# extract-and-run, so a relative path wouldn't resolve.
ARCH=x86_64 appimagetool.AppImage "$APPDIR" "$OUT/Jellyfin-Desktop-x86_64.AppImage"
echo "==> done:"; ls -la "$OUT/Jellyfin-Desktop-x86_64.AppImage"
