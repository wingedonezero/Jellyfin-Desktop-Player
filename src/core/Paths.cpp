#include "Paths.h"

#include <QDir>
#include <QFile>
#include <QStandardPaths>

namespace Paths {

QString configDir()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    QDir().mkpath(dir);
    return dir;
}

void ensureDefaultMpvConfig()
{
    const QString path = configDir() + QStringLiteral("/mpv.conf");
    if (QFile::exists(path)) {
        return;
    }
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        return;
    }
    file.write(R"cfg(# jellyfin-desktop — mpv configuration
#
# This is a standard mpv.conf. Edit it to change playback behaviour; the full
# option reference is at https://mpv.io/manual/stable/#options
# Changes apply the next time playback starts.
#
# NOTE: the video output (vo) is managed by the app and cannot be overridden
# here — the player embeds mpv through its render API.

# ---- Video ----
hwdec=auto-safe          # hardware decoding; "no" forces software decoding
# profile=gpu-hq         # higher-quality (heavier) scaling/rendering
# deinterlace=no         # set to "yes" to deinterlace interlaced sources

# ---- Audio ----
# audio-channels=auto    # e.g. 5.1 / 7.1 for surround / passthrough setups
# volume-max=100

# ---- Subtitles ----
sub-auto=fuzzy           # auto-load matching external subtitle files

# ---- Streaming ----
cache=yes
)cfg");
}

} // namespace Paths
