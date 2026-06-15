# Jellyfin Desktop Player

A native **C++ / Qt6 (QML) / libmpv** Jellyfin client for Linux. We talk to the
Jellyfin server over its HTTP API and render the UI ourselves in QML; video
plays through libmpv embedded directly in the window. **No web engine, no
wrapper libraries.** (Ground-up rewrite; the old CEF/Rust app was scrapped —
see *History* below.)

## Principles (hard-won from the old CEF rewrite)
- **Own the core.** Copy the small bit of glue we need (e.g. the mpv OpenGL
  render sequence); do **not** depend on wrapper libraries (MpvQt, media_kit,
  Jellyfin SDKs) for core features.
- **One engine dependency: `libmpv`.** Like every real mpv player. The Jellyfin
  client and the UI are entirely ours (Qt's own networking/JSON is fine — that's
  the framework, not a third-party SDK).
- **Always provide fallbacks** for optional platform/Wayland features.

## Build / Run
Dependencies (Debian/Ubuntu — all already installed on the dev machine):
```
sudo apt install build-essential cmake ninja-build \
  qt6-base-dev qt6-declarative-dev libmpv-dev
```
Build & run:
```
cmake -B build -G Ninja
cmake --build build
./build/jellyfin-desktop                 # interactive: type server + login
./build/jellyfin-desktop /path/file.mkv  # play a local file directly
```
**Dev/test auto-login + auto-play** (env vars → QML context properties in
`main.cpp`; absent => normal interactive login):
```
JFD_SERVER=http://192.168.1.11:8096 JFD_USER=Testing JFD_PASS=testing123 \
JFD_AUTOPLAY=1 ./build/jellyfin-desktop
```
Test account: **`Testing` / `testing123`** on the user's server
**`http://192.168.1.11:8096`** (works; has media).

## Project structure
```
src/
  main.cpp                  entry: forces OpenGL scene-graph backend, sets
                            LC_NUMERIC=C (mpv needs it), seeds dev context props,
                            loads the QML module
  core/Paths.*              config dir (~/.config/jellyfin-desktop) + base
                            mpv.conf generation
  mpv/MpvVideoItem.*        OUR QQuickFramebufferObject embedding libmpv via the
                            GL render API; observes state (position/duration/
                            pause/volume/mute/track-list) as bindable properties;
                            seek/skip/setPaused/setVolume/setMuted/setAudio|
                            SubtitleTrack invokables; mpv_node->QVariant converter
  jellyfin/JellyfinClient.* OUR Jellyfin REST client on QNetworkAccessManager:
                            auth (/Users/AuthenticateByName + MediaBrowser auth
                            header), /UserViews, /Users/{id}/Items[/Resume],
                            image + direct-play stream URLs, /Sessions/Playing[...]
                            progress. Items emitted as QVariantList of QVariantMap.
  qml/
    Main.qml                thin router: Loader -> LoginView | BrowseView, + PlayerView
    LoginView.qml           server + username/password form
    BrowseView.qml          PLACEHOLDER library grid (libraries -> items -> folders)
    PlayerView.qml          playback layer: mpv surface + OSD auto-hide + resume +
                            10s progress reporting + fullscreen
    PlayerControls.qml      OSD: scrubber, play/pause, skip ±10/30, volume/mute,
                            audio + subtitle menus, fullscreen
```

## mpv-in-Qt6 gotchas (all handled — don't regress)
- `QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL)` **before** the
  first window (mpv's GL render API needs the OpenGL scene-graph backend).
- `std::setlocale(LC_NUMERIC, "C")` after `QGuiApplication` (mpv refuses a
  non-C numeric locale; `mpv_create()` fails otherwise).
- shared_ptr ownership (`MpvHandle` + `MpvRenderResources`) so the mpv handle
  outlives the GL render context (freed on the scene-graph render thread).
- `vo=libmpv` is set as a **property after** config load so a stray `vo=` in the
  user's mpv.conf can't break embedding.
- QML_ELEMENT header dirs must be on the include path (the generated
  `*_qmltyperegistrations.cpp` does `#include <Basename.h>`).

## Status — what works (verified live against the server)
- ✅ Login → browse libraries/items (poster art) → direct-play stream → mpv.
- ✅ **Player matches jellyfin-web base controls:** play/pause, scrubber/seek,
  skip ±10/30, time, volume+mute, audio-track menu, subtitle-track menu,
  fullscreen, resume-from-position, progress reporting back to the server.
- ✅ mpv reads a standard editable `~/.config/jellyfin-desktop/mpv.conf`
  (documented base generated on first run) — fully configurable (deinterlace,
  hwdec, scaling, etc.).

## NEXT — build the real UI (this is the active work)
**Direction (from the user):** baseline is a **skinnable** UI, but **start by
replicating the jellyfin-web desktop look** (the dark library UI seen in the
browser) as the *default skin*. Replicate the *layout/style* ourselves in QML;
do not copy jellyfin-web assets/code.
1. **Home screen** — jellyfin-web-style horizontal rows: Continue Watching,
   Next Up, Latest-per-library. Establish a **skin/theme structure** (colors,
   metrics, card styles centralized) from the start so it's reskinnable.
2. **Item detail pages** — backdrop, overview, cast, ratings, Play / Mark-watched.
3. **Series → seasons → episodes** navigation (currently treated as generic folders).
4. Search, genres/collections, favorites, watched/unwatched marking.
5. **Next-Up / auto-play next episode** (needs a play queue).

### Player extras still owed (after UI; beyond "base controls")
Chapter markers + trickplay thumbnails on the scrubber; playback speed;
subtitle offset/styling; quality/transcode selection + fallback (currently
direct-play only — fine for mpv but no fallback).

### Infra still owed
- **Saved login / session** (no re-auth each launch) — store token+server in
  `~/.config/jellyfin-desktop` (QSettings). Currently re-login each launch.
- The config dir still has leftover `instance.json`/`settings.json`/`mpv/` from
  the OLD CEF app — harmless, unused; clean up when we add settings.

## Git workflow
Work in the git **worktree**, commit to the `claude/*` branch. Do **not** push or
touch `main` — the user merges to `main` and pushes (force-push, since `main` was
reset to a clean Initial commit for this rewrite).

## References (read-only, `../jellyfin-reference/`)
Qt+mpv: `haruna`, `mpvqt`, `mpc-qt`, `mpv-examples`. Jellyfin client+features:
`delfin` (Rust/GTK), `Fladder` (Flutter) — model new Jellyfin API calls on
Fladder. The scrapped CEF/Rust app is archived at
`../jellyfin-cef-archive-20260615/`.
