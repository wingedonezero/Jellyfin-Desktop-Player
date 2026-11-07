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
- **Consumer client only — no server administration.** This is a media player +
  browse + user-settings client at 1:1 parity with the jellyfin-web *consumer*
  UI. The server-admin Dashboard was scrapped (2026-06-17) and is out of scope.

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
JFD_SERVER=http://192.168.1.13:8096 JFD_USER=Testing JFD_PASS=testing123 \
JFD_AUTOPLAY=1 ./build/jellyfin-desktop
```
Test account: **`Testing` / `testing123`** on the user's server
**`http://192.168.1.13:8096`** (works; has media).

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
    Main.qml                app shell + router: AppBar + NavDrawer + StackView,
                            login Loader, PlayerView overlay, routing funcs
    theme/Theme.qml         skin singleton — ALL colors/metrics/fonts (default jf-web dark)
    theme/Features.qml      capability flags (cast/syncPlay/downloads/... gated off)
    components/             JIconButton, DarkMenu(Item), MediaCard, MediaRow, AppBar, NavDrawer
    screens/LoginView.qml   server + username/password form
    screens/HomeScreen.qml  jf-web rows: Continue Watching / Next Up / My Media / Latest
    screens/LibraryScreen.qml type-aware tabs + sort/filter grid (also Favorites/genre/studio)
    screens/DetailScreen.qml  movie/series/season/person/boxset detail + version/audio/sub
    screens/SearchScreen.qml  debounced search grid
    screens/SettingsScreen.qml Profile/Display/Home/Playback/Subtitles/Controls/Player/QuickConnect/About
    screens/PlayerView.qml  mpv surface + OSD + resume + 10s progress + queue + segments
    screens/PlayerControls.qml OSD: scrubber/trickplay/chapters, play/pause, skip, vol, tracks, FS
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
- **Shared wl_display zombie crashes (screen blank!):** Qt + embedded mpv are
  ONE Wayland client, so each side receives events referencing the OTHER
  side's proxies — or NULL once a proxy is destroyed mid-flight (libwayland
  "zombie"). Both sides are patched to tolerate this: mpv via
  `patches/mpv/0001-*` (foreign-output guards in surface enter/leave) and
  QtWaylandClient via `patches/qtwayland/0001-*` + `scripts/build-qtwayland.sh`
  (null guard in every generated `fromObject()`; bundle.sh overlays the
  patched lib into the AppImage — rebuild it when system Qt changes minor
  version). Don't regress either; stock qtwayland segfaults on DPMS blank.

## Status — what works (verified live against the server)
- ✅ Saved login/session → Home (jf-web rows) → Library (tabs/sort/filter) →
  Detail (backdrop/cast/version+audio+sub selectors/chapters/next-up) →
  direct-play or transcode → mpv.
- ✅ **Player at jellyfin-web OSD parity:** play/pause, scrubber + buffered
  ranges, trickplay hover thumbnails, chapter nav/menu, skip ±10/30,
  time↔remaining, volume/mute, audio + subtitle menus, media-segment skip,
  up-next card, fullscreen, resume, progress reporting. (Keyboard still owed.)
- ✅ **User settings** feature-complete (Profile/Display/Home/Playback/
  Subtitles/Player mpv.conf/Quick Connect/About); subtitle appearance → mpv.
- ✅ mpv reads an editable `~/.config/jellyfin-desktop/mpv.conf` (documented
  base on first run — deinterlace/hwdec/scaling/etc.).
- ✅ Screen/monitor sleep inhibited during playback (host-side D-Bus).

## NEXT — consumer parity with jellyfin-web (the active work)
The foundation (shell, Home, Library, Detail, Search, Settings, player OSD,
saved session) is built; the **server-admin surface was scrapped (2026-06-17)**.
**2026-07-04: the big parity items landed** — library browse depth (view modes,
alphabet picker, real paging + TotalRecordCount, full sorts, all filter groups),
type-grouped Search with People/Studios/Collections + suggestions panel, Home
on web's HomeSectionType tokens (7 slots, legacy values migrate on read),
missing-episode rendering, card/episode-row context menus ("⋮" + right-click,
mark played/favorite with instant refresh), watched-state refresh after
playback/toggles (`playbackStopReported`/`userDataChanged` → per-screen
`refreshUserData()`), player keyboard forwarding, playback-health toasts,
buffering spinner, and the OSD Playback Info panel (play method / transcode
reasons / source container). **Trailer button: dropped by user decision** —
don't re-add. Remaining ideas (user will ask): hold-key speed boost, visible
queue panel with reorder (both exceed web), server-side displayPreferences
sync for settings interop.

**2026-11-07 audit (Jellyfin 12 prep + rough edges):** three audits (C++,
QML, jellyfin-web delta f0e06c7→v12.4) → Tier 1 (data-safety/12-auth) and
Tier 2 (robustness/OSD/nav) and Tier 3 (off the `[Obsolete]` `/Users/{id}/…`
routes onto `/Items?userId=`, `/UserItems/Resume`, `/UserFavoriteItems`,
`/UserPlayedItems`, `/Users/Me|Configuration|Password`; playlist create as a
JSON body) landed in five commits, all verified live — **the user's server
moved to 12.4.0 on 2026-11-07**, so the client now runs against 12 for real.
**Still owed:** Tier 4 — new web parity since June:
audio/subtitle-language library filters (`/Items/Filters2` → `audioLanguages`/
`subtitleLanguages`), Collections row on Details (`/Items/{id}/Collections`),
Creators + merged crew cards, chapter name in the scrubber bubble, version-
persistent next-episode. jellyfin-web v12.4 moved `src/controllers/*` to
`src/apps/legacy/controllers/*` and `experimental`→`modern`; Modern reuses the
Legacy screens except Library browse, so our Legacy-mirroring UI is current.

`docs/web-parity-audit-2026-06-16.md` is now largely historical — verify any
claim against code before acting on it. Theme stays the single dark skin; a
swappable-skin *picker* is a separate later project. Cast/SyncPlay render
disabled (genuine engine limits); Live TV/DVR + Music browsing are out of scope.

**Dev/test sandbox:** `JFD_PROFILE=<name>` isolates ALL config (settings/
session/mpv.conf) under `jellyfin-desktop-<name>` and registers as a separate
labelled device ("host (name)") on the server; `JFD_AUTOSTOP=<secs>` backs out
of playback automatically (pairs with `JFD_AUTOPLAY=1` for headless testing).

### Cleanup still owed
- The config dir still has leftover `instance.json`/`settings.json`/`mpv/` from
  the OLD CEF app — harmless, unused.

## Git workflow
Work in the git **worktree**, commit to the `claude/*` branch. Do **not** push or
touch `main` — the user merges to `main` and pushes (force-push, since `main` was
reset to a clean Initial commit for this rewrite).

## References (read-only, `../jellyfin-reference/`)
Qt+mpv: `haruna`, `mpvqt`, `mpc-qt`, `mpv-examples`. Jellyfin client+features:
`delfin` (Rust/GTK), `Fladder` (Flutter) — model new Jellyfin API calls on
Fladder. The scrapped CEF/Rust app is archived at
`../jellyfin-cef-archive-20260615/`.
