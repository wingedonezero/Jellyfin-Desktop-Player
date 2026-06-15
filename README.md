# Jellyfin Desktop Player

A native **C++ / Qt6 (QML) / libmpv** Jellyfin client for Linux — own UI, mpv for
playback, no embedded web engine.

See **[CLAUDE.md](CLAUDE.md)** for build instructions, architecture, and roadmap.

```sh
sudo apt install build-essential cmake ninja-build qt6-base-dev qt6-declarative-dev libmpv-dev
cmake -B build -G Ninja && cmake --build build
./build/jellyfin-desktop /path/to/video.mkv
```

The previous CEF/Rust implementation is archived in `../jellyfin-cef-archive-20260615/`.
