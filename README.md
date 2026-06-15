# Jellyfin Desktop Player

A native **C++ / Qt6 (QML) / libmpv** Jellyfin client for Linux — our own UI,
mpv for playback, no embedded web engine and no third-party SDKs (just `libmpv`
as the playback engine + Qt).

## Quick start
```sh
sudo apt install build-essential cmake ninja-build qt6-base-dev qt6-declarative-dev libmpv-dev
cmake -B build -G Ninja && cmake --build build
./build/jellyfin-desktop          # enter your server URL + login
```
mpv is configured the normal way via `~/.config/jellyfin-desktop/mpv.conf`
(a documented default is written on first run).

## Status
Working end-to-end: **log in → browse libraries → play**, with a player that
matches jellyfin-web's base video controls (seek, skip ±, volume/mute,
audio + subtitle track menus, fullscreen, resume, progress sync).

**In progress:** the real UI — a jellyfin-web-style home/library interface on a
skinnable baseline. See **[CLAUDE.md](CLAUDE.md)** for full architecture, build
notes, status, and the roadmap.

The previous CEF/Rust implementation was scrapped; it's archived in
`../jellyfin-cef-archive-20260615/`.
