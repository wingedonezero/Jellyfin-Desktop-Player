# Jellyfin Desktop Player

A native **C++ / Qt6 (QML) / libmpv** Jellyfin client for Linux. We talk to the
Jellyfin server over its HTTP + WebSocket API and render the UI ourselves in
QML; video plays through libmpv embedded directly in the window. No web engine,
no wrapper libraries.

## Principles (learned from the previous CEF rewrite)
- **Own the core.** We copy the small bit of glue we actually need (e.g. the mpv
  OpenGL render sequence) into our own `src/`. We do **not** take a dependency on
  wrapper libraries (MpvQt, media_kit, jellyfin SDKs, …) for core features —
  that's how you get stuck retrofitting someone else's API.
- **One engine dependency: `libmpv`.** Like every real mpv-based player. The
  Jellyfin client and the UI are entirely ours.
- **Always provide fallbacks** for optional platform/Wayland features. The old
  app died from hard-requiring things (single-pixel-buffer, etc.) with no
  fallback.

## Build
Dependencies (Debian/Ubuntu):
```
sudo apt install build-essential cmake ninja-build \
  qt6-base-dev qt6-declarative-dev libmpv-dev
```
Build & run:
```
cmake -B build -G Ninja
cmake --build build
./build/jellyfin-desktop [media-file-or-url]
```

## Structure
```
src/
  main.cpp            entry: forces the OpenGL scene-graph backend, loads QML
  mpv/
    MpvVideoItem.*    our QQuickFramebufferObject that embeds libmpv (GL render API)
  qml/
    Main.qml          window + video surface + controls
```

## How the video reaches the screen
`MpvVideoItem` is a `QQuickFramebufferObject`; mpv renders through its OpenGL
render API (`MPV_RENDER_API_TYPE_OPENGL`) into the item's FBO. Two non-obvious
requirements that crash naive integrations if missed:
- The Qt Quick scene graph must run on OpenGL —
  `QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL)` in `main.cpp`,
  before the first window.
- The mpv handle must outlive the GL render context (which lives on the
  scene-graph render thread). We use shared_ptr ownership (`MpvHandle` +
  `MpvRenderResources`) so teardown order is always correct.

## Roadmap
1. **[done] mpv spike** — embed libmpv in a Qt6 window, play a file (GL path).
2. **Jellyfin client** (`src/jellyfin/`) — our own HTTP/WS client: auth, server
   discovery, libraries, items, image art, stream URLs, playback progress
   reporting. Reference: Fladder's client + the archived old `jellyfin` crate.
   **No external Jellyfin SDK.**
3. **UI** — skinnable Netflix-style grid; default skin modeled on jellyfin-web.
4. **mpv build-out** — move the controller to a worker thread, typed property
   API (mpv_node <-> QVariant), full config surface (hwdec, deinterlace,
   scaling, shaders, video-sync, audio).
5. **Vulkan** — let mpv own its surface for the Vulkan backend
   (mpv-owns-surface embedding); the GL render-API path stays the default and
   the fallback.

## References (read-only, in `../jellyfin-reference/`)
- Qt + mpv: `haruna`, `mpvqt`, `mpc-qt`, `mpv-examples`
- Jellyfin client + features: `delfin` (Rust/GTK), `Fladder` (Flutter)
- The scrapped CEF/Rust app: `../jellyfin-cef-archive-20260615/`
