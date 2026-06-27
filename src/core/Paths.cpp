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
#  jellyfin-desktop  —  mpv.conf  —  fully annotated reference
#  Renderer: gpu-next (libplacebo) + Vulkan.   Targets mpv 0.41.
#
#  HOW TO READ THIS FILE
#  ---------------------
#    * ACTIVE (uncommented) lines OVERRIDE mpv's defaults. By default that's
#      only the renderer + hardware decode below — everything else is left at
#      mpv's own default, so nothing here fights good defaults.
#    * COMMENTED (#) lines are the MENU of what's available: what each option
#      does, its choices, a >>recommended<< note where there's a clear pick, and
#      mpv's default. Uncomment one only when you want to override that default.
#    * Unknown/bad options are reported in the app (it captures mpv's log), so
#      you can edit freely and tell if something didn't take.
#
#  THE APP MANAGES THESE — don't set them here:
#    * window / fullscreen (the video is embedded), resume position (server-side
#      "continue watching"), screen blanking (handled over D-Bus), and the
#      on-screen controls (the app draws its own Jellyfin OSD; mpv's OSC stays
#      off). Subtitle appearance is driven by Settings -> Subtitles (it writes
#      the sub-* options for you).
#
#  NO PROFILE IS AUTO-APPLIED — the optional quality tiers sit, commented, at
#  the very bottom so nothing overrides your settings unless you ask.
# =============================================================================


# =============================================================================
# RENDERER + HARDWARE DECODE   (active — the intentional base)
# =============================================================================
vo=gpu-next                 # libplacebo renderer. Required for all modern tone-mapping/HDR below.
                            #   choices: gpu-next >>use this<< | gpu (legacy) | dmabuf-wayland
gpu-api=vulkan              # graphics API. vulkan is the recommended pairing with gpu-next on Linux.
                            #   choices: auto | vulkan >>recommended<< | opengl (fallback)
hwdec=auto-safe             # GPU-offload decode via known-reliable paths, else software.
                            #   choices: no | auto-safe >>recommended<< | auto-copy (copies frames to
                            #            RAM so all shaders work) | vaapi (Intel/AMD) | nvdec (NVIDIA)

# --- decode / runtime knobs (commented = mpv default) ---
#hwdec-codecs=all           # allow HW decode for every codec. Default already covers the common ones.
#vd-lavc-dr=yes             # direct-render decoded frames into GPU memory (less copying). Default: yes.
#vd-lavc-threads=0          # software-decoder threads. 0 = auto (one per core). Default: 0.
#vulkan-async-compute=yes   # overlap compute work on the GPU. Default: yes. Off only to debug drivers.
#framedrop=vo               # drop late frames to hold A/V sync. choices: no | vo (default) | decoder | decoder+vo

# --- THE PROFILE TRIGGER -----------------------------------------------------
# A profile applies a whole BUNDLE of settings at once. Turn one on by
# uncommenting ONE line here (it must live in this global area, before any
# [section] header). The profile bodies are listed, commented, at the BOTTOM so
# you can read exactly what each sets. A profile overrides settings written
# ABOVE it — so keep your own picks BELOW the profile line if you want them to win.
#profile=high-quality       # mpv's built-in dGPU tier (sharp scaling + HDR peak tuning). See bottom.
#profile=fast               # mpv's built-in low-overhead tier (bilinear, no extras). See bottom.


# =============================================================================
# SCALING — luma up (scale) / luma down (dscale) / chroma (cscale)
#   Eyes are most sensitive to LUMA upscaling, so spend GPU there first.
#   mpv defaults: scale=lanczos  cscale=lanczos  dscale=mitchell.
# =============================================================================
#scale=ewa_lanczossharp      # luma upscaler. soft->sharp: bilinear | spline36 | lanczos (default) |
                            #   ewa_lanczos | ewa_lanczossharp >>best general, needs a capable GPU<<
#cscale=ewa_lanczossharp     # chroma upscaler. spline36 is a lighter, near-identical-looking option.
#dscale=mitchell             # luma downscaler (4K->1080p). mitchell >>smooth<< | catmull_rom (sharper) |
                            #   hermite (sharp, cheap) | box
#scale-antiring=0.6          # anti-halo for a sharp luma upscaler, 0.0..1.0. 0.6 is a common sweet spot.
                            #   (dscale-antiring / cscale-antiring are IGNORED by gpu-next.)
#correct-downscaling=yes    # ON BY DEFAULT — widen the kernel when shrinking so detail isn't aliased.
#linear-downscaling=yes     # ON BY DEFAULT — average brightness in linear light when downscaling.
#sigmoid-upscaling=yes      # ON BY DEFAULT — upscale through a sigmoid curve to cut edge ringing.
                            #   ^ those three are mpv defaults; set one =no only to TURN IT OFF.

# --- external scaler shaders (advanced; ~~/ = this config dir) ---
#glsl-shader="~~/shaders/ArtCNN_C4F16.glsl"   # neural luma upscaler for anime / low-res.
#glsl-shaders-append="~~/shaders/CfL_Prediction.glsl"  # stack more (Anime4K, FSRCNNX, …).


# =============================================================================
# DITHERING — stops banding when writing the final image to your panel
#   Defaults (dither on, fruit method, depth auto) are already good.
# =============================================================================
#dither-depth=auto          # match dither to output bit depth. auto >>rec<< | no | 8 | 10
#dither=fruit               # algorithm. fruit (default, good) | ordered (cheap) | error-diffusion >>best<< | no
#error-diffusion=sierra-lite # kernel when dither=error-diffusion. sierra-lite | floyd-steinberg | burkes


# =============================================================================
# DEBANDING — removes banding baked into the SOURCE (skies, gradients, anime)
#   mpv default: deband=no. Uncomment the block to enable + tune.
# =============================================================================
#deband=yes                 # master switch. Default: no.
#deband-iterations=1        # passes 1..16. Higher = cleaner + more GPU; >4-5 is wasted. Default: 1.
#deband-threshold=64        # flatten strength 0..4096. Higher = stronger. Default: 64.
#deband-range=16            # sample radius 1..64. Too high erases detail. Default: 16.
#deband-grain=48            # masking noise 0..4096. Higher for poor sources. Default: 48.
                            #   tuning: clean/anime 2:35:20:5 | bad BD/web 3:45:25:15


# =============================================================================
# MOTION INTERPOLATION — smooths judder when fps != refresh ("soap-opera" look)
#   mpv default: interpolation off, video-sync=audio (the normal cinematic look).
#   interpolation NEEDS video-sync=display-resample to look right — enable both.
# =============================================================================
#video-sync=audio           # master clock. audio >>rock-solid, use when interpolation is OFF<< |
                            #   display-resample (use WITH interpolation) | display-tempo (with audio-spdif)
#interpolation=no           # frame-interpolation master switch. Default: no.
#tscale=oversample          # temporal filter when interpolation is on. oversample >>fewest artifacts<< | mitchell


# =============================================================================
# COLOR / HDR / TONE MAPPING   (gpu-next only — that's why vo=gpu-next above)
#   HDR carries highlights up to thousands of nits; an SDR screen does ~100-300.
#   Tone mapping compresses that to fit. All commented => mpv auto-detects: on an
#   SDR screen it tone-maps down; on an HDR screen it passes HDR through.
# =============================================================================
#target-colorspace-hint=yes # tell the display the real colorspace so HDR passthrough works.
                            #   >>turn ON if you play HDR on an HDR display<<. Safe; only acts on HDR. Default: no.
#tone-mapping=auto          # HDR->SDR curve. choices:
                            #   auto >>default = spline<< | spline >>best all-round<< | bt.2446a (broadcast) |
                            #   bt.2390 (reference) | st2094-40 (HDR10+ dynamic) | reinhard/hable/gamma (taste) |
                            #   clip (HDR->HDR only) | mobius/linear (avoid / diagnostic)
#hdr-compute-peak=yes       # measure each frame's true peak so mapping adapts. Default: yes. >>keep on<<
#hdr-peak-percentile=99.995 # ignore the brightest 0.005% (rejects stray hot specks). Default: 100.
#hdr-contrast-recovery=0.30 # restore local contrast lost in compression, 0.0..2.0. Default: 0.
#gamut-mapping-mode=auto    # out-of-gamut colours. auto (=perceptual) | perceptual >>natural<< | relative |
                            #   saturation | absolute | clip
#inverse-tone-mapping=no    # fake HDR from SDR. >>keep OFF<< — looks unnatural. Default: no.


# =============================================================================
# AUDIO
# =============================================================================
#ao=pipewire                # output driver. pipewire >>modern Linux<< | pulse | alsa
#audio-channels=auto        # negotiate layout with the device. auto >>rec<< | stereo | 5.1 | 7.1
#audio-exclusive=no         # take exclusive control of the device? Default: no (share with system sounds).
#volume-max=130             # highest volume the player allows, in %. Default: 130.
#audio-spdif=ac3,eac3,dts,dts-hd,truehd  # BITSTREAM these UNDECODED to an AVR over HDMI/SPDIF.
                            #   Default: off (mpv decodes). This is the REAL audio-passthrough switch.
                            #   If you enable it, also set video-sync=display-tempo above.
#af=dynaudnorm              # audio filters, e.g. dynaudnorm / loudnorm for night-time level smoothing.


# =============================================================================
# SUBTITLES
#   Settings -> Subtitles writes sub-scale / sub-pos / sub-font / sub-color /
#   sub-bold / sub-outline-* / sub-ass-override for you — prefer that UI. Set
#   things here only to go beyond it.
# =============================================================================
#sub-auto=fuzzy             # auto-load external subs by loose filename match. no | exact (default) | fuzzy | all
#slang=eng,en,English       # fallback subtitle-language order (your server preference is applied first).
#sub-ass-override=scale     # how much to override embedded ASS styling. no (keep file) | scale | force (plain look)
#blend-subtitles=no         # blend subtitles in linear light (slightly nicer edges). Default: no.


# =============================================================================
# CACHE / STREAM
#   mpv already enables a cache for network sources automatically (cache=auto).
# =============================================================================
#cache=auto                 # demuxer cache. auto (default; caches network) | yes (always) | no
#demuxer-max-bytes=150MiB   # forward read-ahead. Bigger = more prefetch for network. Default: ~150MiB.
#demuxer-max-back-bytes=50MiB # played data kept for instant back-seek. Default: ~50MiB.
#cache-secs=10              # seconds to prefetch while the cache is active. Default: high when cache is on.


# =============================================================================
# SCREENSHOTS / OSD   (the app draws its own OSD; mpv's OSC stays off)
# =============================================================================
#screenshot-format=png      # png >>lossless<< | jpg | webp | jxl | avif
#screenshot-high-bit-depth=yes # capture in 10/12-bit when the source is HDR. Default: yes.
#screenshot-directory=~/Pictures/mpv
#osd-font-size=55           # size of mpv's own status/seek text (the toasts on key presses). Default: 55.


# =============================================================================
# OPTIONAL QUALITY-TIER PROFILES   (NONE auto-applied — enable via the #profile=
#   line in the RENDERER section above. Reproduced from mpv's built-in
#   etc/builtin.conf so you can read exactly what each tier changes. mpv already
#   has these internally; the #profile= line just switches one on.)
# =============================================================================

# ----- mpv's [fast] profile (runs on anything; bilinear + no extras) -----
#[fast]
#scale=bilinear
#dscale=bilinear
#dither=no
#correct-downscaling=no
#linear-downscaling=no
#sigmoid-upscaling=no
#hdr-compute-peak=no
#allow-delayed-peak-detect=yes

# ----- mpv's [high-quality] profile (just 3 overrides on top of the defaults) -----
#[high-quality]
#scale=ewa_lanczossharp
#hdr-peak-percentile=99.995
#hdr-contrast-recovery=0.30

# ----- example custom tier (enable with profile=my-hq up top) -----
#[my-hq]
#profile-desc=HQ + deband + error-diffusion dither
#scale=ewa_lanczossharp
#cscale=ewa_lanczossharp
#dscale=mitchell
#scale-antiring=0.6
#deband=yes
#deband-iterations=2
#dither=error-diffusion
#hdr-compute-peak=yes
#hdr-peak-percentile=99.995
#hdr-contrast-recovery=0.30
)cfg");
}

void ensureDefaultInputConf()
{
    const QString path = configDir() + QStringLiteral("/input.conf");
    if (QFile::exists(path)) {
        return;
    }
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        return;
    }
    file.write(R"cfg(# jellyfin-desktop — mpv input.conf
#
# mpv's default key bindings are ALWAYS active (the app forwards your key
# presses to mpv), so most keys already work in the player without being listed
# here, e.g.:
#   d   cycle deinterlace          i   stats overlay (I = toggle)
#   SPACE / p   pause              LEFT/RIGHT  seek 5s     UP/DOWN  seek 1m
#   [ ]  speed down/up            v   subtitle visibility  m  mute
# Full reference: https://mpv.io/manual/stable/#interactive-control
#
# NOTE: f / F11 / Esc are handled by the app (fullscreen / exit), not mpv.

# Cycle the HDR->SDR tone-mapping curve live; the OSD names the active curve.
t cycle-values tone-mapping "auto" "spline" "bt.2446a" "bt.2390" "reinhard" "hable"
)cfg");
}

} // namespace Paths
