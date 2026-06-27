#pragma once

#include <QString>

// Standard config locations + default-config seeding.
namespace Paths {

// ~/.config/jellyfin-desktop (created if missing). This doubles as mpv's
// config-dir, so users edit ~/.config/jellyfin-desktop/mpv.conf directly.
QString configDir();

// Write a documented default mpv.conf into configDir() if none exists yet.
void ensureDefaultMpvConfig();

// Write a default input.conf (mpv key bindings) into configDir() if none exists.
void ensureDefaultInputConf();

} // namespace Paths
