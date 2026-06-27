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
    file.write(R"cfg(# =============================================================================
#  jellyfin-desktop — mpv.conf
#
#  This is a standard mpv configuration. The app embeds a full, stock mpv and
#  reads this file, so ANY mpv option works here — full option reference:
#  https://mpv.io/manual/stable/#options . Changes apply on the next playback.
#
#  Style: ACTIVE (uncommented) lines are what the app sets by default. COMMENTED
#  (#) lines show common options you can turn on — mpv uses its own default for
#  each until you uncomment it. Bad options are reported in the app (mpv log).
# =============================================================================

# ---- Renderer + hardware decode (active defaults) ---------------------------
vo=gpu-next             # libplacebo renderer — required for modern tone-mapping/HDR.
gpu-api=vulkan          # graphics API. vulkan is the recommended pairing with gpu-next.
hwdec=auto-safe         # GPU decode via known-reliable paths, else software.
                        #   choices: no | auto-safe | auto-copy | vaapi | nvdec

# ---- Quality (commented = mpv default) --------------------------------------
# profile=high-quality  # mpv's built-in higher-quality tier (heavier scaling).
# scale=ewa_lanczossharp   # sharp luma upscaler
# dscale=mitchell          # smooth luma downscaler (4K -> 1080p)
# deband=yes               # remove banding in skies/gradients
# deinterlace=yes          # deinterlace interlaced sources (also toggle with 'd')

# ---- Color / HDR / tone mapping (commented = mpv default; needs gpu-next) ----
# target-colorspace-hint=yes   # enable correct HDR signalling/passthrough
# tone-mapping=auto            # HDR->SDR curve: auto|spline|bt.2446a|bt.2390|reinhard|hable
# hdr-compute-peak=yes         # adapt mapping to each scene's real peak

# ---- Audio ------------------------------------------------------------------
# ao=pipewire             # output driver: pipewire | pulse | alsa
# audio-channels=auto     # auto | stereo | 5.1 | 7.1

# ---- Subtitles --------------------------------------------------------------
sub-auto=fuzzy            # auto-load matching external subtitle files
                          # (subtitle styling is also managed from app Settings)

# ---- Cache / streaming ------------------------------------------------------
cache=yes
)cfg");
}

} // namespace Paths
