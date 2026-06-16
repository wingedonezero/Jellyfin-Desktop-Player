import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import JellyfinDesktop

// The server administration dashboard (jellyfin-web's Dashboard), reachable only
// for admins. Grouped nav mirrors the web drawer. Read-only GET panels are
// wired (System info, Users, Devices, Activity, Plugins, API Keys, Logs,
// Scheduled Tasks); editing-heavy pages are present but stubbed (manage in the
// web dashboard for now). All data via client.getJson → jsonReady.
Item {
    id: screen
    property var client
    property string pageTitle: qsTr("Administration")

    property int sel: 0
    property var panelData: null
    property var dashInfo: null
    property var dashCounts: null
    property var dashSessions: []
    property var tasksData: []
    property var usersData: []
    property var selectedUser: null
    property var editPolicy: ({})
    property string editUserName: ""
    property bool userAddMode: false
    property string newUserName: ""
    property string newUserPw: ""
    property var mediaFoldersData: []   // [{id,name}] for the Access section
    property var channelsData: []
    property var devicesData: []
    property var parentalRatings: []    // grouped [{name, score, subScore}] for the Parental section
    readonly property var parentalOptions: {
        var o = [{value: -1, text: qsTr("None")}]
        for (var i = 0; i < parentalRatings.length; i++) o.push({value: i, text: parentalRatings[i].name})
        return o
    }
    readonly property var unratedTypes: [{id: "Movie", name: qsTr("Movies")}, {id: "Series", name: qsTr("Shows")}, {id: "Music", name: qsTr("Music")}, {id: "Trailer", name: qsTr("Trailers")}, {id: "Book", name: qsTr("Books")}, {id: "LiveTvChannel", name: qsTr("Live TV")}, {id: "ChannelContent", name: qsTr("Channels")}]
    readonly property var dayOptions: [{value: "Everyday", text: qsTr("Every day")}, {value: "Sunday", text: qsTr("Sunday")}, {value: "Monday", text: qsTr("Monday")}, {value: "Tuesday", text: qsTr("Tuesday")}, {value: "Wednesday", text: qsTr("Wednesday")}, {value: "Thursday", text: qsTr("Thursday")}, {value: "Friday", text: qsTr("Friday")}, {value: "Saturday", text: qsTr("Saturday")}]
    property string schedDay: "Everyday"
    property int schedStart: 0
    property int schedEnd: 24
    readonly property var syncPlayOptions: [{value: "CreateAndJoinGroups", text: qsTr("Allow creating and joining groups")}, {value: "JoinGroups", text: qsTr("Allow joining groups")}, {value: "None", text: qsTr("No access")}]
    property var serverConfig: null
    property var editConfig: ({})
    property var dynOptions: ({})          // dynamically-fetched select options (e.g. {users: [...]})
    property var pendingAction: null
    property string _dirPickKey: ""        // config key the directory picker is editing
    property string _dirPickMode: "config" // config | newlib | addpath
    property var librariesData: []
    property string logName: ""            // currently-open log file (empty = list view)
    property string logContent: ""
    property string inputValue: ""         // generic input dialog
    property var inputAction: null
    property var selectedLib: null         // the library being managed (detail view), or null (list)
    property bool addMode: false           // showing the add-library form
    property string newLibName: ""
    property string newLibType: "movies"
    property string newLibPath: ""
    property string renameValue: ""
    property var availOpts: null   // GET /Libraries/AvailableOptions (JSON-roundtripped to plain JS)
    property var subLangAll: []    // [{lang(3-letter), name}] from /Localization/Cultures
    property var provState: ({})   // provider-table working state (see rebuildProv)
    // per-type "Fetcher settings" (ImageOptions) dialog state
    property int fsIndex: -1
    property string fsType: ""
    property var fsSupported: []
    property var fsLimits: ({})    // {imageType: bool}
    property int fsMaxBackdrops: 0
    property int fsMinBackdropWidth: 0
    readonly property var contentTypes: [{value: "movies", text: qsTr("Movies")}, {value: "tvshows", text: qsTr("Shows")}, {value: "music", text: qsTr("Music")}, {value: "homevideos", text: qsTr("Home Videos & Photos")}, {value: "musicvideos", text: qsTr("Music Videos")}, {value: "books", text: qsTr("Books")}, {value: "boxsets", text: qsTr("Collections")}, {value: "mixed", text: qsTr("Mixed Content")}]
    readonly property var selEntry: navModel[sel] || ({})

    // field sets for the data-driven server-config editors (kind "config")
    readonly property var generalFields: [
        {group: qsTr("Settings"), label: qsTr("Server name"), key: "ServerName", type: "text", help: qsTr("This name will be used to identify the server and will default to the server's hostname.")},
        {label: qsTr("Preferred display language"), key: "UICulture", type: "select", optionsKey: "uiCultures", help: qsTr("Translating Jellyfin is an ongoing project. <a href=\"https://jellyfin.org/docs/general/contributing/#translating\">Learn how you can contribute.</a>")},
        {group: qsTr("Paths"), label: qsTr("Cache path"), key: "CachePath", type: "text", browse: true, help: qsTr("Specify a custom location for server cache files such as images. Leave blank to use the server default.")},
        {label: qsTr("Metadata path"), key: "MetadataPath", type: "text", browse: true, help: qsTr("Specify a custom location for downloaded artwork and metadata.")},
        {group: qsTr("Quick Connect"), label: qsTr("Enable Quick Connect on this server"), key: "QuickConnectAvailable", type: "toggle"},
        {group: qsTr("Performance"), label: qsTr("Parallel library scan tasks limit"), key: "LibraryScanFanoutConcurrency", type: "number", help: qsTr("Maximum number of parallel tasks during library scans. Leaving this empty will choose a limit based on your system's core count. WARNING: Setting this number too high may cause issues with network file systems; if you encounter problems lower this number.")},
        {label: qsTr("Parallel image encoding limit"), key: "ParallelImageEncodingLimit", type: "number", help: qsTr("Maximum number of image encodings that are allowed to run in parallel. Leaving this empty will choose a limit based on your system's core count.")}
    ]
    readonly property var brandingFields: [
        {label: qsTr("Enable splash screen"), key: "SplashscreenEnabled", type: "toggle"},
        {label: qsTr("Login disclaimer"), key: "LoginDisclaimer", type: "text", help: qsTr("A message that will be displayed at the bottom of the login page.")},
        {label: qsTr("Custom CSS"), key: "CustomCss", type: "text", help: qsTr("Apply your custom CSS code for theming/branding on the web interface.")}
    ]
    readonly property var metadataFields: [
        {group: qsTr("Preferred metadata language"), label: qsTr("Language"), key: "PreferredMetadataLanguage", type: "select", optionsKey: "cultures", help: qsTr("These are your defaults and can be customized on a per-library basis.")},
        {label: qsTr("Country"), key: "MetadataCountryCode", type: "select", optionsKey: "countries"},
        {group: qsTr("Chapter images"), label: qsTr("Interval"), key: "DummyChapterDuration", type: "number", help: qsTr("The interval between dummy chapters in seconds. Set to 0 to disable dummy chapter generation. Changing this will have no effect on existing dummy chapters.")},
        {label: qsTr("Resolution"), key: "ChapterImageResolution", type: "select", help: qsTr("The resolution of the extracted chapter images. Changing this will have no effect on existing dummy chapters."),
         options: [{value: "MatchSource", text: qsTr("Match Source")}, {value: "P2160", text: "2160p"}, {value: "P1440", text: "1440p"}, {value: "P1080", text: "1080p"}, {value: "P720", text: "720p"}, {value: "P480", text: "480p"}, {value: "P360", text: "360p"}, {value: "P240", text: "240p"}, {value: "P144", text: "144p"}]}
    ]
    readonly property var networkFields: [
        {group: qsTr("Server addresses"), label: qsTr("Local HTTP port number"), key: "InternalHttpPort", type: "number", help: qsTr("The TCP port number for the HTTP server.")},
        {label: qsTr("Enable HTTPS"), key: "EnableHttps", type: "toggle", help: qsTr("Listen on the configured HTTPS port. A valid certificate must also be supplied for this to take effect.")},
        {label: qsTr("Local HTTPS port number"), key: "InternalHttpsPort", type: "number", help: qsTr("The TCP port number for the HTTPS server.")},
        {label: qsTr("Base URL"), key: "BaseUrl", type: "text", help: qsTr("Add a custom subdirectory to the server URL. For example: https://example.com/<baseurl>")},
        {label: qsTr("Bind to local network address"), key: "LocalNetworkAddresses", type: "list", help: qsTr("Override the local IP address for the HTTP server. If left empty, the server will bind to all available addresses. Changing this value requires a restart.")},
        {label: qsTr("LAN networks"), key: "LocalNetworkSubnets", type: "list", help: qsTr("Comma separated list of IP addresses or IP/netmask entries for networks that will be considered on local network. If left blank, all RFC1918 addresses are considered local.")},
        {label: qsTr("Known proxies"), key: "KnownProxies", type: "list", help: qsTr("Comma separated list of IP addresses or hostnames of known proxies. Required to make proper use of 'X-Forwarded-For' headers. Requires a reboot after saving.")},
        {group: qsTr("HTTPS settings"), label: qsTr("Require HTTPS"), key: "RequireHttps", type: "toggle", help: qsTr("If checked, the server will automatically redirect all requests over HTTP to HTTPS. No effect if the server is not listening on HTTPS.")},
        {label: qsTr("Custom SSL certificate path"), key: "CertificatePath", type: "text", browse: true, help: qsTr("Path to a PKCS #12 file containing a certificate and private key to enable TLS support on a custom domain.")},
        {label: qsTr("Certificate password"), key: "CertificatePassword", type: "password", help: qsTr("If your certificate requires a password, please enter it here.")},
        {group: qsTr("Remote access"), label: qsTr("Allow remote connections to this server"), key: "EnableRemoteAccess", type: "toggle", help: qsTr("If unchecked, all remote connections will be blocked.")},
        {label: qsTr("Remote IP address filter"), key: "RemoteIPFilter", type: "list", help: qsTr("Comma separated list of IP addresses or IP/netmask entries that will be allowed to connect remotely. If left blank, all remote addresses will be allowed.")},
        {label: qsTr("Remote IP filter mode"), key: "IsRemoteIPFilterBlacklist", type: "select", options: [{value: false, text: qsTr("Whitelist — only the addresses above may connect")}, {value: true, text: qsTr("Blacklist — the addresses above are blocked")}]},
        {label: qsTr("Public HTTP port number"), key: "PublicHttpPort", type: "number", help: qsTr("The public port number that should be mapped to the local HTTP port.")},
        {label: qsTr("Public HTTPS port number"), key: "PublicHttpsPort", type: "number", help: qsTr("The public port number that should be mapped to the local HTTPS port.")},
        {group: qsTr("IP protocols"), label: qsTr("Enable IPv4"), key: "EnableIPv4", type: "toggle", help: qsTr("Enable IPv4 functionality.")},
        {label: qsTr("Enable IPv6"), key: "EnableIPv6", type: "toggle", help: qsTr("Enable IPv6 functionality.")},
        {group: qsTr("Network discovery"), label: qsTr("Enable Auto Discovery"), key: "AutoDiscovery", type: "toggle", help: qsTr("Allow applications to automatically detect Jellyfin by using UDP port 7359.")}
    ]
    readonly property var encodingFields: [
        {group: qsTr("Hardware acceleration"), label: qsTr("Hardware acceleration"), key: "HardwareAccelerationType", type: "select", help: qsTr("Hardware acceleration requires additional configuration."),
         options: [{value: "none", text: qsTr("None")}, {value: "amf", text: "AMD AMF"}, {value: "nvenc", text: "Nvidia NVENC"}, {value: "qsv", text: "Intel Quicksync (QSV)"}, {value: "vaapi", text: "Video Acceleration API (VAAPI)"}, {value: "rkmpp", text: "Rockchip MPP (RKMPP)"}, {value: "videotoolbox", text: "Apple VideoToolBox"}, {value: "v4l2m2m", text: "Video4Linux2 (V4L2)"}]},
        {label: qsTr("VA-API device"), key: "VaapiDevice", type: "text", showWhen: {key: "HardwareAccelerationType", eq: "vaapi"}, help: qsTr("This is the render node that is used for hardware acceleration.")},
        {label: qsTr("QSV device"), key: "QsvDevice", type: "text", showWhen: {key: "HardwareAccelerationType", eq: "qsv"}, help: qsTr("Specify the device for Intel QSV on a multi-GPU system. On Linux this is the render node, e.g. /dev/dri/renderD128; on Windows the device index from 0.")},
        {label: qsTr("Enable hardware decoding for"), key: "HardwareDecodingCodecs", type: "list", showWhen: {key: "HardwareAccelerationType", neq: "none"}, help: qsTr("Comma-separated list of codecs to hardware-decode (e.g. h264, hevc, mpeg2video, vc1, vp8, vp9, av1).")},
        {label: qsTr("HEVC 10bit decoding"), key: "EnableDecodingColorDepth10Hevc", type: "toggle", showWhen: {key: "HardwareAccelerationType", oneOf: ["amf", "nvenc", "qsv", "vaapi", "rkmpp"]}},
        {label: qsTr("VP9 10bit decoding"), key: "EnableDecodingColorDepth10Vp9", type: "toggle", showWhen: {key: "HardwareAccelerationType", oneOf: ["amf", "nvenc", "qsv", "vaapi", "rkmpp"]}},
        {label: qsTr("HEVC RExt 8/10bit decoding"), key: "EnableDecodingColorDepth10HevcRext", type: "toggle", showWhen: {key: "HardwareAccelerationType", oneOf: ["nvenc", "qsv", "vaapi"]}},
        {label: qsTr("HEVC RExt 12bit decoding"), key: "EnableDecodingColorDepth12HevcRext", type: "toggle", showWhen: {key: "HardwareAccelerationType", oneOf: ["nvenc", "qsv", "vaapi"]}},
        {label: qsTr("Enable enhanced NVDEC decoder"), key: "EnableEnhancedNvdecDecoder", type: "toggle", showWhen: {key: "HardwareAccelerationType", eq: "nvenc"}, help: qsTr("Enhanced NVDEC implementation; disable to use CUVID if you encounter decoding errors.")},
        {label: qsTr("Prefer OS native DXVA or VA-API decoders"), key: "PreferSystemNativeHwDecoder", type: "toggle", showWhen: {key: "HardwareAccelerationType", eq: "qsv"}},
        {label: qsTr("Enable hardware encoding"), key: "EnableHardwareEncoding", type: "toggle", showWhen: {key: "HardwareAccelerationType", neq: "none"}},
        {label: qsTr("Enable Intel Low-Power H.264 hardware encoder"), key: "EnableIntelLowPowerH264HwEncoder", type: "toggle", showWhen: {key: "HardwareAccelerationType", oneOf: ["qsv", "vaapi"]}},
        {label: qsTr("Enable Intel Low-Power HEVC hardware encoder"), key: "EnableIntelLowPowerHevcHwEncoder", type: "toggle", showWhen: {key: "HardwareAccelerationType", oneOf: ["qsv", "vaapi"]}, help: qsTr("On Linux these must be disabled if the i915 HuC firmware is not configured.")},

        {group: qsTr("Encoding format"), label: qsTr("Allow encoding in HEVC format"), key: "AllowHevcEncoding", type: "toggle", help: qsTr("The video format Jellyfin transcodes to. Software encoding is used when hardware acceleration for the format is unavailable. H264 is always enabled.")},
        {label: qsTr("Allow encoding in AV1 format"), key: "AllowAv1Encoding", type: "toggle"},

        {group: qsTr("Tone mapping"), label: qsTr("Tone mapping algorithm"), key: "TonemappingAlgorithm", type: "select", showWhen: {key: "HardwareAccelerationType", neq: "v4l2m2m"}, help: qsTr("If unfamiliar with these options, keep the default. The recommended value is 'BT.2390'."),
         options: [{value: "none", text: qsTr("None")}, {value: "clip", text: "Clip"}, {value: "linear", text: "Linear"}, {value: "gamma", text: "Gamma"}, {value: "reinhard", text: "Reinhard"}, {value: "hable", text: "Hable"}, {value: "mobius", text: "Mobius"}, {value: "bt2390", text: "BT.2390"}]},
        {label: qsTr("Tone mapping mode"), key: "TonemappingMode", type: "select", showWhen: {key: "HardwareAccelerationType", oneOf: ["amf", "nvenc", "qsv", "vaapi", "rkmpp", "videotoolbox"]}, help: qsTr("If you experience blown-out highlights try switching to RGB mode."),
         options: [{value: "auto", text: qsTr("Auto")}, {value: "max", text: "MAX"}, {value: "rgb", text: "RGB"}, {value: "lum", text: "LUM"}, {value: "itp", text: "ITP"}]},
        {label: qsTr("Tone mapping range"), key: "TonemappingRange", type: "select", showWhen: {key: "HardwareAccelerationType", neq: "v4l2m2m"}, help: qsTr("Output color range. Auto matches the input range."),
         options: [{value: "auto", text: qsTr("Auto")}, {value: "tv", text: "TV"}, {value: "pc", text: "PC"}]},
        {label: qsTr("Tone mapping desat"), key: "TonemappingDesat", type: "float", showWhen: {key: "HardwareAccelerationType", neq: "v4l2m2m"}, help: qsTr("Desaturate highlights exceeding this brightness. Recommended value 0 (disable).")},
        {label: qsTr("Tone mapping peak"), key: "TonemappingPeak", type: "float", showWhen: {key: "HardwareAccelerationType", neq: "v4l2m2m"}, help: qsTr("Override the embedded peak metadata for the input signal. Default 100 (1000nit).")},
        {label: qsTr("Tone mapping param"), key: "TonemappingParam", type: "float", showWhen: {key: "HardwareAccelerationType", neq: "v4l2m2m"}, help: qsTr("Tune the tone mapping algorithm. Generally leave blank.")},
        {label: qsTr("Enable tone mapping"), key: "EnableTonemapping", type: "toggle", showWhen: {key: "HardwareAccelerationType", oneOf: ["amf", "nvenc", "qsv", "vaapi", "rkmpp", "videotoolbox"]}, help: qsTr("Transforms HDR to SDR while keeping detail and color. Works with 10bit HDR10, HLG and DoVi; requires the corresponding GPGPU runtime.")},
        {label: qsTr("Enable VPP tone mapping"), key: "EnableVppTonemapping", type: "toggle", showWhen: {key: "HardwareAccelerationType", oneOf: ["qsv", "vaapi"]}, help: qsTr("Full Intel driver based tone-mapping. Works only on certain hardware with HDR10 videos.")},
        {label: qsTr("VPP tone mapping brightness gain"), key: "VppTonemappingBrightness", type: "float", showWhen: {key: "HardwareAccelerationType", oneOf: ["qsv", "vaapi"]}, help: qsTr("Recommended value 16.")},
        {label: qsTr("VPP tone mapping contrast gain"), key: "VppTonemappingContrast", type: "float", showWhen: {key: "HardwareAccelerationType", oneOf: ["qsv", "vaapi"]}, help: qsTr("Recommended value 1.")},
        {label: qsTr("Enable VideoToolbox tone mapping"), key: "EnableVideoToolboxTonemapping", type: "toggle", showWhen: {key: "HardwareAccelerationType", eq: "videotoolbox"}, help: qsTr("Works with most HDR formats (HDR10, HDR10+, HLG) but not Dolby Vision Profile 5.")},

        {group: qsTr("Encoding quality"), label: qsTr("Encoding preset"), key: "EncoderPreset", type: "select", help: qsTr("Pick a faster value to improve performance, or a slower value to improve quality."),
         options: [{value: "auto", text: qsTr("Auto")}, {value: "veryslow", text: "veryslow"}, {value: "slower", text: "slower"}, {value: "slow", text: "slow"}, {value: "medium", text: "medium"}, {value: "fast", text: "fast"}, {value: "faster", text: "faster"}, {value: "veryfast", text: "veryfast"}, {value: "superfast", text: "superfast"}, {value: "ultrafast", text: "ultrafast"}]},
        {label: qsTr("H.265 encoding CRF"), key: "H265Crf", type: "number"},
        {label: qsTr("H.264 encoding CRF"), key: "H264Crf", type: "number", help: qsTr("The 'Constant Rate Factor' for the x264/x265 software encoders. Values 0-51, lower = better quality / larger files. Sane values 18-28 (x264 default 23, x265 28). Hardware encoders ignore this.")},
        {label: qsTr("Transcoding thread count"), key: "EncodingThreadCount", type: "select", help: qsTr("Max threads when transcoding. Reducing lowers CPU usage but may not convert fast enough for smooth playback."),
         options: [{value: -1, text: qsTr("Auto")}, {value: 1, text: "1"}, {value: 2, text: "2"}, {value: 3, text: "3"}, {value: 4, text: "4"}, {value: 5, text: "5"}, {value: 6, text: "6"}, {value: 7, text: "7"}, {value: 8, text: "8"}, {value: 9, text: "9"}, {value: 10, text: "10"}, {value: 11, text: "11"}, {value: 12, text: "12"}, {value: 13, text: "13"}, {value: 14, text: "14"}, {value: 15, text: "15"}, {value: 16, text: "16"}, {value: 0, text: qsTr("Max")}]},
        {label: qsTr("Max muxing queue size"), key: "MaxMuxingQueueSize", type: "number", help: qsTr("Packets buffered while streams initialize. Increase if you meet \"Too many packets buffered for output stream\" errors. Recommended 2048.")},

        {group: qsTr("Deinterlacing"), label: qsTr("Deinterlacing method"), key: "DeinterlaceMethod", type: "select", help: qsTr("Method used when software transcoding interlaced content. Hardware deinterlacing is used instead when available."),
         options: [{value: "yadif", text: "YADIF"}, {value: "bwdif", text: "BWDIF"}]},
        {label: qsTr("Double the frame rate when deinterlacing"), key: "DeinterlaceDoubleRate", type: "toggle", help: qsTr("Uses the field rate (bob deinterlacing), doubling the frame rate for full motion like interlaced video on a TV.")},

        {group: qsTr("Subtitles & audio"), label: qsTr("Allow subtitle extraction on the fly"), key: "EnableSubtitleExtraction", type: "toggle", help: qsTr("Extract embedded subtitles to plain text to help avoid transcoding. Can be slow on some systems; disable to burn in instead when not natively supported.")},
        {label: qsTr("Enable VBR audio encoding"), key: "EnableAudioVbr", type: "toggle", help: qsTr("Better quality-to-bitrate, but in rare cases may cause buffering/compatibility issues.")},
        {label: qsTr("Audio boost when downmixing"), key: "DownMixAudioBoost", type: "float", help: qsTr("Boost audio when downmixing. A value of one preserves the original volume.")},
        {label: qsTr("Stereo downmix algorithm"), key: "DownMixStereoAlgorithm", type: "select", help: qsTr("Algorithm used to downmix multi-channel audio to stereo."),
         options: [{value: "None", text: qsTr("None")}, {value: "Dave750", text: "Dave750"}, {value: "NightmodeDialogue", text: "Nightmode Dialogue"}, {value: "Rfc7845", text: "RFC7845"}, {value: "Ac4", text: "AC-4"}]},

        {group: qsTr("Paths"), label: qsTr("FFmpeg path"), key: "EncoderAppPathDisplay", type: "text", readonly: true, help: qsTr("The path to the ffmpeg application file or folder containing ffmpeg. Detected automatically.")},
        {label: qsTr("Transcode path"), key: "TranscodingTempPath", type: "text", browse: true, help: qsTr("Custom path for transcode files served to clients. Leave blank to use the server default.")},
        {label: qsTr("Fallback font folder path"), key: "FallbackFontPath", type: "text", browse: true, help: qsTr("Fonts used by some clients to render subtitles.")},
        {label: qsTr("Enable fallback fonts"), key: "EnableFallbackFont", type: "toggle", help: qsTr("Enable custom alternate fonts to avoid incorrect subtitle rendering.")},

        {group: qsTr("Transcode throttling"), label: qsTr("Throttle transcodes"), key: "EnableThrottling", type: "toggle", help: qsTr("When a transcode gets far enough ahead of playback, pause it to use fewer resources. Turn off if you experience playback issues.")},
        {label: qsTr("Throttle after (seconds)"), key: "ThrottleDelaySeconds", type: "number", help: qsTr("Seconds after which the transcoder is throttled. Must be large enough for the client to keep a healthy buffer. Only works if throttling is enabled.")},
        {label: qsTr("Delete segments"), key: "EnableSegmentDeletion", type: "toggle", help: qsTr("Delete old segments after the client downloads them, avoiding storing the whole transcoded file. Turn off if you experience playback issues.")},
        {label: qsTr("Time to keep segments (seconds)"), key: "SegmentKeepSeconds", type: "number", help: qsTr("Seconds to keep segments after the client downloads them. Only works if segment deletion is enabled.")}
    ]
    readonly property var resumeFields: [
        {label: qsTr("Minimum resume percentage"), key: "MinResumePct", type: "number", help: qsTr("Titles are assumed unplayed if stopped before this time.")},
        {label: qsTr("Maximum resume percentage"), key: "MaxResumePct", type: "number", help: qsTr("Titles are assumed fully played if stopped after this time.")},
        {label: qsTr("Minimum audiobook resume (%)"), key: "MinAudiobookResume", type: "number", help: qsTr("Titles are assumed unplayed if stopped before this time.")},
        {label: qsTr("Maximum audiobook resume (%)"), key: "MaxAudiobookResume", type: "number", help: qsTr("Titles are assumed fully played if stopped when the remaining duration is less than this value.")},
        {label: qsTr("Minimum resume duration (seconds)"), key: "MinResumeDurationSeconds", type: "number", help: qsTr("The shortest video length in seconds that will save playback location and let you resume.")}
    ]
    readonly property var streamingFields: [
        {label: qsTr("Remote client bitrate limit (Mbps, 0 = unlimited)"), key: "RemoteClientBitrateLimit", type: "number", scale: 1000000, help: qsTr("An optional per-stream bitrate limit for all out of network devices. This is useful to prevent devices from requesting a higher bitrate than your internet connection can handle. This may result in increased CPU load on your server in order to transcode videos on the fly to a lower bitrate.")}
    ]
    readonly property var displayFields: [
        {label: qsTr("Display a folder view to show plain media folders"), key: "EnableFolderView", type: "toggle", help: qsTr("Display folders alongside your other media. This may be useful if you'd like to have a plain folder view.")},
        {label: qsTr("Display specials within the seasons they aired in"), key: "DisplaySpecialsWithinSeasons", type: "toggle"},
        {label: qsTr("Group movies into collections"), key: "EnableGroupingMoviesIntoCollections", type: "toggle", help: qsTr("When displaying movie lists, movies belonging to a collection will be displayed as one grouped item.")},
        {label: qsTr("Group shows into collections"), key: "EnableGroupingShowsIntoCollections", type: "toggle", help: qsTr("When displaying show lists, shows belonging to a collection will be displayed as one grouped item.")},
        {label: qsTr("Enable external content in suggestions"), key: "EnableExternalContentInSuggestions", type: "toggle", help: qsTr("Allow internet trailers and Live TV programs to be included within suggested content.")}
    ]
    readonly property var nfoFields: [
        {label: qsTr("Kodi metadata user"), key: "UserId", type: "select", optionsKey: "users", help: qsTr("Save watch data to NFO files for other applications to use.")},
        {label: qsTr("Save image paths in NFO"), key: "SaveImagePathsInNfo", type: "toggle", help: qsTr("This is recommended if you have image file names that don't conform to Kodi guidelines.")},
        {label: qsTr("Enable path substitution"), key: "EnablePathSubstitution", type: "toggle", help: qsTr("Enable path substitution of image paths using the server's path substitution settings.")},
        {label: qsTr("Duplicate extra thumbnails (extrafanart/extrathumbs)"), key: "EnableExtraThumbsDuplication", type: "toggle", help: qsTr("When downloading images they can be saved into both extrafanart and extrathumbs for maximum Kodi skin compatibility.")}
    ]
    // Trickplay lives in the nested ServerConfiguration.TrickplayOptions object → dot-path keys.
    readonly property var trickplayFields: [
        {label: qsTr("Enable hardware decoding"), key: "TrickplayOptions.EnableHwAcceleration", type: "toggle"},
        {label: qsTr("Enable hardware encoding"), key: "TrickplayOptions.EnableHwEncoding", type: "toggle", help: qsTr("Currently only available on QSV, VA-API, VideoToolbox and RKMPP, this option has no effect on other hardware acceleration methods.")},
        {label: qsTr("Key-frame-only extraction"), key: "TrickplayOptions.EnableKeyFrameOnlyExtraction", type: "toggle", help: qsTr("Extract key frames only for significantly faster processing with less accurate timing. If the configured hardware decoder does not support this mode, will use the software decoder instead.")},
        {label: qsTr("Scan behavior"), key: "TrickplayOptions.ScanBehavior", type: "select", options: [{value: "NonBlocking", text: qsTr("Non-blocking")}, {value: "Blocking", text: qsTr("Blocking")}], help: qsTr("The default behavior is non blocking, which will add media to the library before trickplay generation is done. Blocking will ensure trickplay files are generated before media is added to the library, but will make scans significantly longer.")},
        {label: qsTr("Process priority"), key: "TrickplayOptions.ProcessPriority", type: "select", options: [{value: "High", text: qsTr("High")}, {value: "AboveNormal", text: qsTr("Above normal")}, {value: "Normal", text: qsTr("Normal")}, {value: "BelowNormal", text: qsTr("Below normal")}, {value: "Idle", text: qsTr("Idle")}], help: qsTr("Setting this lower or higher will determine how the CPU prioritizes the ffmpeg trickplay generation process in relation to other processes. If you notice slowdown while generating trickplay images but don't want to fully stop their generation, try lowering this as well as the thread count.")},
        {label: qsTr("Image interval (ms)"), key: "TrickplayOptions.Interval", type: "number", help: qsTr("Interval of time (ms) between each new trickplay image.")},
        {label: qsTr("Width resolutions (comma-separated)"), key: "TrickplayOptions.WidthResolutions", type: "csv", help: qsTr("Comma separated list of the widths (px) that trickplay images will be generated at. All images should generate proportionally to the source, so a width of 320 on a 16:9 video ends up around 320x180.")},
        {label: qsTr("Tile width (images per tile)"), key: "TrickplayOptions.TileWidth", type: "number", help: qsTr("Maximum number of images per tile in the X direction.")},
        {label: qsTr("Tile height (images per tile)"), key: "TrickplayOptions.TileHeight", type: "number", help: qsTr("Maximum number of images per tile in the Y direction.")},
        {label: qsTr("JPEG quality (1–100)"), key: "TrickplayOptions.JpegQuality", type: "number", help: qsTr("The JPEG compression quality for trickplay images.")},
        {label: qsTr("Qscale (2–31)"), key: "TrickplayOptions.Qscale", type: "number", help: qsTr("The quality scale of images output by ffmpeg, with 2 being the highest quality and 31 being the lowest.")},
        {label: qsTr("Process threads (0 = auto)"), key: "TrickplayOptions.ProcessThreads", type: "number", help: qsTr("The number of threads to pass to the '-threads' argument of ffmpeg.")}
    ]
    // LibraryOptions field visibility by content type (mirrors web's setContentType).
    readonly property var tChapter: ["homevideos", "movies", "musicvideos", "tvshows", "mixed"]      // chapter + trickplay
    readonly property var tEmbedded: ["movies", "tvshows", "homevideos", "musicvideos", "mixed"]      // embedded titles
    readonly property var tSubs: ["movies", "tvshows", "musicvideos", "mixed"]                        // subtitles
    // Per-library LibraryOptions (edited against a deep copy of the selected
    // library's options; Save → updateLibraryOptions). Mirrors web's
    // libraryoptionseditor: each field's `types` gates it to applicable content
    // types. These are the SCALAR options; the provider tables (savers /
    // downloaders / image fetchers / …) are built separately from
    // GET /Libraries/AvailableOptions (see rebuildProv). Reuses cultures/countries.
    readonly property var libraryOptionsFields: [
        {group: qsTr("Library"), label: qsTr("Enable the library"), key: "Enabled", type: "toggle", help: qsTr("Disabling the library will hide it from all user views.")},
        {label: qsTr("Download metadata and images from the internet"), key: "EnableInternetProviders", type: "toggle"},
        {label: qsTr("Preferred download language"), key: "PreferredMetadataLanguage", type: "select", optionsKey: "cultures"},
        {label: qsTr("Country / Region"), key: "MetadataCountryCode", type: "select", optionsKey: "countries"},
        {label: qsTr("Automatically refresh metadata from the internet (days; 0 = never)"), key: "AutomaticRefreshIntervalDays", type: "number"},
        {label: qsTr("Save artwork into media folders"), key: "SaveLocalMetadata", type: "toggle", help: qsTr("Saving artwork into media folders puts it where it can be easily edited.")},
        {label: qsTr("Enable real-time monitoring"), key: "EnableRealtimeMonitor", type: "toggle", help: qsTr("Changes to files will be processed immediately on supported file systems.")},
        {label: qsTr("Display photos"), key: "EnablePhotos", type: "toggle", types: ["homevideos"], help: qsTr("Images will be detected and displayed alongside other media files.")},
        {label: qsTr("Enable LUFS scan"), key: "EnableLUFSScan", type: "toggle", types: ["music"], help: qsTr("Lets clients normalize playback loudness across tracks. Makes library scans longer and use more resources.")},
        {label: qsTr("Automatically add to collection"), key: "AutomaticallyAddToCollection", type: "toggle", types: ["movies", "mixed"], help: qsTr("When at least 2 movies share the same collection name, they are added to the collection automatically.")},
        {label: qsTr("Automatically merge series spread across multiple folders"), key: "EnableAutomaticSeriesGrouping", type: "toggle", types: ["tvshows"], help: qsTr("Series spread across multiple folders in this library are merged into a single series.")},
        {label: qsTr("Special season display name"), key: "SeasonZeroDisplayName", type: "text", types: ["tvshows"]},

        {group: qsTr("Embedded info"), label: qsTr("Prefer embedded titles over filenames"), key: "EnableEmbeddedTitles", type: "toggle", types: screen.tEmbedded, help: qsTr("Title to use when no internet or local metadata is available.")},
        {label: qsTr("Prefer embedded titles over filenames for extras"), key: "EnableEmbeddedExtrasTitles", type: "toggle", types: screen.tEmbedded, help: qsTr("Extras often share the parent's embedded name; check to use embedded titles for them anyway.")},
        {label: qsTr("Prefer embedded episode information over filenames"), key: "EnableEmbeddedEpisodeInfos", type: "toggle", types: ["tvshows"], help: qsTr("Use embedded episode information when available.")},
        {label: qsTr("Disable different types of embedded subtitles"), key: "AllowEmbeddedSubtitles", type: "select", types: screen.tSubs, options: [{value: "AllowAll", text: qsTr("Allow All")}, {value: "AllowText", text: qsTr("Allow Text")}, {value: "AllowImage", text: qsTr("Allow Image")}, {value: "AllowNone", text: qsTr("Allow None")}], help: qsTr("Disable subtitles packaged within media containers. Requires a full library refresh.")},

        {group: qsTr("Trickplay"), label: qsTr("Enable trickplay image extraction"), key: "EnableTrickplayImageExtraction", type: "toggle", types: screen.tChapter, help: qsTr("Trickplay images span the content and show a preview when scrubbing through videos.")},
        {label: qsTr("Extract trickplay images during the library scan"), key: "ExtractTrickplayImagesDuringLibraryScan", type: "toggle", types: screen.tChapter, help: qsTr("Otherwise they are extracted during the trickplay scheduled task.")},
        {label: qsTr("Save trickplay images next to media"), key: "SaveTrickplayWithMedia", type: "toggle", types: screen.tChapter, help: qsTr("Puts trickplay images next to your media for easy migration and access.")},

        {group: qsTr("Chapter images"), label: qsTr("Enable chapter image extraction"), key: "EnableChapterImageExtraction", type: "toggle", types: screen.tChapter, help: qsTr("Lets clients display graphical scene-selection menus. Can be slow and resource intensive.")},
        {label: qsTr("Extract chapter images during the library scan"), key: "ExtractChapterImagesDuringLibraryScan", type: "toggle", types: screen.tChapter, help: qsTr("Otherwise they are extracted during the chapter-images scheduled task.")},

        {group: qsTr("Subtitle downloads"), label: qsTr("Only download subtitles that perfectly match the video"), key: "RequirePerfectSubtitleMatch", type: "toggle", types: screen.tSubs, help: qsTr("Filters to subtitles verified with your exact file. Unchecking increases coverage but risks mistimed/incorrect subtitles.")},
        {label: qsTr("Skip if the default audio track matches the download language"), key: "SkipSubtitlesIfAudioTrackMatches", type: "toggle", types: screen.tSubs, help: qsTr("Uncheck to ensure all videos have subtitles regardless of audio language.")},
        {label: qsTr("Skip if the video already contains embedded subtitles"), key: "SkipSubtitlesIfEmbeddedSubtitlesPresent", type: "toggle", types: screen.tSubs, help: qsTr("Keeping text subtitles means more efficient delivery and less transcoding.")},
        {label: qsTr("Save subtitles into media folders"), key: "SaveSubtitlesWithMedia", type: "toggle", types: screen.tSubs, help: qsTr("Storing subtitles next to video files makes them easier to manage.")},

        {group: qsTr("Lyrics"), label: qsTr("Save lyrics into media folders"), key: "SaveLyricsWithMedia", type: "toggle", types: ["music"], help: qsTr("Storing lyrics next to audio files makes them easier to manage.")},

        {group: qsTr("Audio tags"), label: qsTr("Prefer ARTISTS tag if available"), key: "PreferNonstandardArtistsTag", type: "toggle", types: ["music"], help: qsTr("Use the non-standard ARTISTS tag instead of ARTIST when available.")},
        {label: qsTr("Use custom tag delimiters"), key: "UseCustomTagDelimiters", type: "toggle", types: ["music"], help: qsTr("Split artist/genre tags with custom characters.")},
        {label: qsTr("Custom tag delimiters (comma-separated)"), key: "CustomTagDelimiters", type: "list", types: ["music"]},
        {label: qsTr("Delimiter whitelist (comma-separated)"), key: "DelimiterWhitelist", type: "list", types: ["music"], help: qsTr("Items to be excluded from tag splitting.")}
    ]

    // group | label | kind (config/info/list/stub) | endpoint | fields | primary/secondary | fmt
    readonly property var navModel: [
        { group: qsTr("Server"),   label: qsTr("Dashboard"),     kind: "dashboard" },
        { group: qsTr("Server"),   label: qsTr("General"),       kind: "config", ep: "/System/Configuration", fields: screen.generalFields },
        { group: qsTr("Server"),   label: qsTr("Branding"),      kind: "config", ep: "/System/Configuration/branding", fields: screen.brandingFields },
        { group: qsTr("Server"),   label: qsTr("Users"),         kind: "users" },
        { group: qsTr("Server"),   label: qsTr("Libraries"),     kind: "libraries" },
        { group: qsTr("Server"),   label: qsTr("Display"),       kind: "config", ep: "/System/Configuration", fields: screen.displayFields },
        { group: qsTr("Server"),   label: qsTr("Metadata"),      kind: "config", ep: "/System/Configuration", fields: screen.metadataFields },
        { group: qsTr("Server"),   label: qsTr("NFO"),           kind: "config", ep: "/System/Configuration/xbmcmetadata", fields: screen.nfoFields },
        { group: qsTr("Server"),   label: qsTr("Playback / Transcoding"), kind: "config", ep: "/System/Configuration/encoding", fields: screen.encodingFields },
        { group: qsTr("Server"),   label: qsTr("Resume"),        kind: "config", ep: "/System/Configuration", fields: screen.resumeFields },
        { group: qsTr("Server"),   label: qsTr("Streaming"),     kind: "config", ep: "/System/Configuration", fields: screen.streamingFields },
        { group: qsTr("Server"),   label: qsTr("Trickplay"),     kind: "config", ep: "/System/Configuration", fields: screen.trickplayFields },
        { group: qsTr("Devices"),  label: qsTr("Devices"),       kind: "list", ep: "/Devices", fmt: "devices" },
        { group: qsTr("Devices"),  label: qsTr("Activity"),      kind: "list", ep: "/System/ActivityLog/Entries?Limit=60", fmt: "activity" },
        { group: qsTr("Live TV"),  label: qsTr("Live TV"),       kind: "stub" },
        { group: qsTr("Live TV"),  label: qsTr("DVR"),           kind: "stub" },
        { group: qsTr("Plugins"),  label: qsTr("Plugins"),       kind: "list", ep: "/Plugins", fmt: "plugins" },
        { group: qsTr("Advanced"), label: qsTr("Networking"),    kind: "config", ep: "/System/Configuration/network", fields: screen.networkFields },
        { group: qsTr("Advanced"), label: qsTr("API Keys"),      kind: "list", ep: "/Auth/Keys", fmt: "apikeys", primary: "AppName", secondary: "DateCreated" },
        { group: qsTr("Advanced"), label: qsTr("Backups"),       kind: "stub" },
        { group: qsTr("Advanced"), label: qsTr("Logs"),          kind: "list", ep: "/System/Logs", fmt: "logs", primary: "Name", secondary: "Size" },
        { group: qsTr("Advanced"), label: qsTr("Scheduled Tasks"), kind: "tasks" }
    ]

    onSelChanged: loadSel()
    Component.onCompleted: loadSel()
    function loadSel() {
        // Read the entry FRESH from navModel[sel]. We must NOT use the selEntry
        // binding here: loadSel runs from onSelChanged (sel's change handler), and
        // at that point the selEntry binding hasn't re-evaluated yet — it still
        // holds the PREVIOUS tab's entry, which made every navigation load the
        // wrong (off-by-one) tab and left the panel blank.
        var entry = navModel[sel] || ({})
        panelData = null; logName = ""
        if (!client) return
        if (entry.kind === "dashboard") {
            client.getJson("/System/Info", "admin:dash:info")
            client.getJson("/Items/Counts", "admin:dash:counts")
            client.getJson("/Sessions", "admin:dash:sessions")
        } else if (entry.kind === "tasks") {
            tasksData = []
            client.getJson("/ScheduledTasks", "admin:tasks")
        } else if (entry.kind === "users") {
            usersData = []; selectedUser = null; userAddMode = false
            client.getJson("/Users", "admin:users")
        } else if (entry.kind === "libraries") {
            librariesData = []; selectedLib = null; addMode = false; dynOptions = ({})
            client.getJson("/Library/VirtualFolders", "admin:libs")
            fetchOptionSources(libraryOptionsFields) // cultures/countries for the per-library options editor
        } else if (entry.kind === "config") {
            serverConfig = null; editConfig = ({}); dynOptions = ({})
            client.getJson(entry.ep, "admin:config")
            fetchOptionSources(entry.fields)
        } else if (entry.kind !== "stub") {
            client.getJson(entry.ep, "admin:panel")
        }
    }
    // GET any dynamic dropdown option sources the field set needs (deduped); tagged admin:opt:<key>
    readonly property var optionEndpoints: ({ users: "/Users", uiCultures: "/Localization/Options", cultures: "/Localization/Cultures", countries: "/Localization/Countries" })
    function fetchOptionSources(fields) {
        var seen = ({})
        var fs = fields || []
        for (var i = 0; i < fs.length; i++) {
            var k = fs[i].optionsKey
            if (k && !seen[k] && optionEndpoints[k]) { seen[k] = true; client.getJson(optionEndpoints[k], "admin:opt:" + k) }
        }
    }
    // confirm a destructive action before running it (server actions)
    function confirm(msg, action) { confirmPopup.message = msg; pendingAction = action; confirmPopup.open() }
    function openDirPicker(key) { _dirPickMode = "config"; _dirPickKey = key; dirPicker.openAt(cfgGet(key) || "") }
    function pickNewLibFolder() { _dirPickMode = "newlib"; dirPicker.openAt("") }
    function pickAddPathFolder() { _dirPickMode = "addpath"; dirPicker.openAt("") }
    function selectLib(lib) {
        selectedLib = lib; renameValue = ("" + (lib.Name || ""))
        editConfig = lib.LibraryOptions ? JSON.parse(JSON.stringify(lib.LibraryOptions)) : ({})
        availOpts = null; provState = ({})
        // fetch the provider catalogue for this content type (mixed = empty type)
        client.getJson("/Libraries/AvailableOptions?libraryContentType=" + (lib.CollectionType || "") + "&isNewLibrary=false", "admin:availopts")
    }
    function reloadLibs() { if (client) client.getJson("/Library/VirtualFolders", "admin:libs") }
    function relTime(iso) {
        if (!iso) return ""
        const t = Date.parse(iso); if (isNaN(t)) return ""
        const diff = (Date.now() - t) / 1000
        if (diff < 0) return ""
        if (diff < 60) return qsTr("just now")
        if (diff < 3600) return qsTr("%1m ago").arg(Math.floor(diff / 60))
        if (diff < 86400) return qsTr("%1h ago").arg(Math.floor(diff / 3600))
        return qsTr("%1d ago").arg(Math.floor(diff / 86400))
    }
    function durationStr(s, e) {
        if (!s || !e) return ""
        const d = (Date.parse(e) - Date.parse(s)) / 1000
        if (isNaN(d) || d < 0) return ""
        if (d < 90) return qsTr("%1s").arg(Math.round(d))
        if (d < 5400) return qsTr("%1m").arg(Math.round(d / 60))
        return qsTr("%1h").arg(Math.round(d / 3600))
    }
    function infoRows(d) {
        if (!d || typeof d !== "object") return []
        return Object.keys(d).map(function (k) {
            const v = d[k]
            return { k: k, v: (v !== null && typeof v === "object") ? JSON.stringify(v) : ("" + v) }
        })
    }
    // getJson hands back a QVariantList, which QML does NOT see as a native JS
    // Array (Array.isArray is false) — detect list-like by .length, and unwrap
    // the paged { Items: [...] } shape some endpoints use.
    function asArray(d) {
        if (!d) return []
        if (d.length !== undefined) return d
        return d.Items || []
    }
    function listRows(d) { return asArray(d) }
    function listTitle(entry, item) {
        if (!item) return "—"
        if (entry.fmt === "devices") return ("" + (item.CustomName || item.Name || "—"))
        if (entry.fmt === "apikeys") return ("" + (item.AppName || "—"))
        if (entry.fmt === "logs") return ("" + (item.Name || "—"))
        return ("" + (item.Name || item[entry.primary] || "—"))
    }
    function listSub(entry, item) {
        if (!item) return ""
        var parts = []
        if (entry.fmt === "activity") parts = [relTime(item.Date), item.Severity, item.ShortOverview]
        else if (entry.fmt === "devices") parts = [item.AppName, item.LastUserName, item.DateLastActivity ? relTime(item.DateLastActivity) : ""]
        else if (entry.fmt === "plugins") parts = [item.Version ? ("v" + item.Version) : "", item.Status, item.Description]
        else if (entry.fmt === "apikeys") parts = [("" + (item.AccessToken || "")), item.DateCreated ? relTime(item.DateCreated) : ""]
        else if (entry.fmt === "logs") parts = [item.Size ? (Math.round(item.Size / 1024) + " KB") : ""]
        else return entry.secondary ? ("" + (item[entry.secondary] || "")) : ""
        return parts.filter(function (x) { return x }).join("  ·  ")
    }

    Connections {
        target: screen.client
        function onJsonReady(tag, data) {
            if (tag === "admin:panel") screen.panelData = data
            else if (tag === "admin:dash:info") screen.dashInfo = data
            else if (tag === "admin:dash:counts") screen.dashCounts = data
            else if (tag === "admin:dash:sessions") screen.dashSessions = screen.asArray(data)
            else if (tag === "admin:tasks") screen.tasksData = screen.asArray(data)
            else if (tag === "admin:users") screen.usersData = screen.asArray(data)
            else if (tag === "u:folders") { var fa = screen.asArray(data); var fo = []; for (var fi = 0; fi < fa.length; fi++) fo.push({id: fa[fi].Id, name: fa[fi].Name}); screen.mediaFoldersData = fo }
            else if (tag === "u:channels") { var ca = screen.asArray(data); var co = []; for (var ci = 0; ci < ca.length; ci++) co.push({id: ca[ci].Id, name: ca[ci].Name}); screen.channelsData = co }
            else if (tag === "u:devices") { var da = screen.asArray(data); var dvo = []; for (var di = 0; di < da.length; di++) { var dv = da[di]; var nm = ("" + (dv.CustomName || dv.Name || "")); if (dv.AppName) nm += " - " + dv.AppName; dvo.push({id: dv.Id, name: nm}) } screen.devicesData = dvo }
            else if (tag === "u:ratings") {
                var ra = screen.asArray(data); var grouped = []
                for (var rri = 0; rri < ra.length; rri++) {
                    var rr = ra[rri]; if (!rr.RatingScore) continue       // skip "Unrated" (no score)
                    var sc = rr.RatingScore.score, ssc = rr.RatingScore.subScore
                    if (grouped.length) { var last = grouped[grouped.length - 1]; if (last.score === sc && last.subScore === ssc) { last.name += "/" + rr.Name; continue } }
                    grouped.push({name: ("" + rr.Name), score: sc, subScore: ssc})
                }
                screen.parentalRatings = grouped
            }
            else if (tag === "admin:config") { screen.serverConfig = data; screen.editConfig = data ? JSON.parse(JSON.stringify(data)) : ({}) }
            else if (tag === "admin:libs") {
                screen.librariesData = screen.asArray(data)
                if (screen.selectedLib) { // re-point to the refreshed entry so the detail view updates
                    var ll = screen.librariesData
                    for (var li = 0; li < ll.length; li++) if (ll[li].ItemId === screen.selectedLib.ItemId) { screen.selectedLib = ll[li]; break }
                }
            }
            else if (tag === "admin:availopts") {
                screen.availOpts = data ? JSON.parse(JSON.stringify(data)) : null
                screen.rebuildProv()
            }
            else if (tag.indexOf("admin:opt:") === 0) {
                var key = tag.substring(10)
                var src = screen.asArray(data)
                var opts = []
                if (key === "users") { opts.push({value: "", text: qsTr("None")}); for (var i = 0; i < src.length; i++) opts.push({value: src[i].Id, text: src[i].Name}) }
                else if (key === "uiCultures") { for (var j = 0; j < src.length; j++) opts.push({value: src[j].Value || "", text: src[j].Name}) }
                else if (key === "cultures") {
                    opts.push({value: "", text: qsTr("Any language")})
                    var langs = []
                    for (var m = 0; m < src.length; m++) {
                        opts.push({value: src[m].TwoLetterISOLanguageName || "", text: src[m].DisplayName || src[m].Name})
                        var three = src[m].ThreeLetterISOLanguageName
                        if (three) langs.push({lang: ("" + three).toLowerCase(), name: src[m].DisplayName || src[m].Name})
                    }
                    screen.subLangAll = langs
                    screen.rebuildProv() // subtitle-language checklist needs the 3-letter codes
                }
                else if (key === "countries") { opts.push({value: "", text: qsTr("Any country")}); for (var n = 0; n < src.length; n++) opts.push({value: src[n].TwoLetterISORegionName || "", text: src[n].DisplayName || src[n].Name}) }
                var dd = Object.assign({}, screen.dynOptions); dd[key] = opts; screen.dynOptions = dd
            }
        }
        function onTextReady(tag, content) { if (tag === "admin:logfile") screen.logContent = content }
    }

    function selectUser(u) {
        selectedUser = u
        editUserName = ("" + (u && u.Name ? u.Name : ""))
        editPolicy = (u && u.Policy) ? JSON.parse(JSON.stringify(u.Policy)) : ({})
        mediaFoldersData = []; channelsData = []; devicesData = []; parentalRatings = []
        if (client) {
            client.getJson("/Library/MediaFolders?IsHidden=false", "u:folders")
            client.getJson("/Channels", "u:channels")
            client.getJson("/Devices", "u:devices")
            client.getJson("/Localization/ParentalRatings", "u:ratings")
        }
    }
    // Parental: index of the grouped rating matching the user's max (exact score+sub, else highest <=score)
    function parentalSelectedIndex() {
        var um = editPolicy.MaxParentalRating
        if (um === undefined || um === null) return -1
        var us = editPolicy.MaxParentalSubRating
        var idx = -1
        for (var i = 0; i < parentalRatings.length; i++) if (parentalRatings[i].score === um && parentalRatings[i].subScore === us) idx = i
        if (idx < 0) for (var j = 0; j < parentalRatings.length; j++) if (parentalRatings[j].score != null && parentalRatings[j].score <= um) idx = j
        return idx
    }
    function setMaxParental(index) {
        var p = JSON.parse(JSON.stringify(editPolicy))
        if (index < 0) { p.MaxParentalRating = null; p.MaxParentalSubRating = null }
        else { p.MaxParentalRating = parentalRatings[index].score; p.MaxParentalSubRating = parentalRatings[index].subScore }
        editPolicy = p
    }
    function addTag(flag, tag) { var p = JSON.parse(JSON.stringify(editPolicy)); var a = p[flag] || []; if (tag && a.indexOf(tag) < 0) a.push(tag); p[flag] = a; editPolicy = p }
    function removeTag(flag, tag) { var p = JSON.parse(JSON.stringify(editPolicy)); p[flag] = (p[flag] || []).filter(function (t) { return t !== tag }); editPolicy = p }
    function addSchedule() {
        var p = JSON.parse(JSON.stringify(editPolicy)); var a = p.AccessSchedules || []
        a.push({DayOfWeek: schedDay, StartHour: schedStart, EndHour: schedEnd}); p.AccessSchedules = a; editPolicy = p
    }
    function removeSchedule(i) { var p = JSON.parse(JSON.stringify(editPolicy)); var a = p.AccessSchedules || []; a.splice(i, 1); p.AccessSchedules = a; editPolicy = p }
    function setFlag(key, val) { var p = Object.assign({}, editPolicy); p[key] = val; editPolicy = p }
    // Access lists: membership of an id in an editPolicy array (EnabledFolders/Channels/Devices)
    function inEnabled(listKey, id) { var a = editPolicy[listKey]; return !!a && a.indexOf(id) >= 0 }
    function toggleEnabled(listKey, id) {
        var p = JSON.parse(JSON.stringify(editPolicy)); var a = p[listKey] || []
        var i = a.indexOf(id); if (i >= 0) a.splice(i, 1); else a.push(id)
        p[listKey] = a; editPolicy = p
    }
    // save a user: name via POST /Users/{id} (whole dto), policy via POST /Users/{id}/Policy — mirrors web's Profile save
    function saveUser() {
        var u = selectedUser; if (!u || !client) return
        var pol = JSON.parse(JSON.stringify(editPolicy))
        if (pol.EnableAllFolders) pol.EnabledFolders = []          // mirror web: clear the list when "all" is on
        if (pol.EnableAllChannels) pol.EnabledChannels = []
        if (pol.EnableAllDevices) pol.EnabledDevices = []
        var dto = JSON.parse(JSON.stringify(u)); dto.Name = editUserName; dto.Policy = pol
        client.postJson("/Users/" + u.Id, dto)
        client.setUserPolicy(u.Id, pol)
    }

    // ---- LibraryOptions provider tables — mirrors components/libraryoptionseditor ----
    function typePlural(t) {
        var m = { Movie: qsTr("Movies"), Series: qsTr("Shows"), Season: qsTr("Seasons"), Episode: qsTr("Episodes"),
                  MusicAlbum: qsTr("Albums"), MusicArtist: qsTr("Artists"), Audio: qsTr("Songs"), MusicVideo: qsTr("Music Videos"),
                  BoxSet: qsTr("Collections"), Book: qsTr("Books"), AudioBook: qsTr("Audiobooks"), Photo: qsTr("Photos"), Trailer: qsTr("Trailers") }
        return m[t] || t
    }
    // sort plugins by their position in the configured order (web's getOrderedPlugins)
    function orderedPlugins(plugins, order) {
        var arr = (plugins || []).slice()
        var ord = order || []
        arr.sort(function (a, b) { return ord.indexOf(a.Name) - ord.indexOf(b.Name) })
        return arr
    }
    // (re)build the provider working state from availOpts + the saved LibraryOptions
    function rebuildProv() {
        var a = availOpts
        if (!a) { provState = ({}); return }
        var saved = editConfig || ({})
        function typeOpt(t) { var to = saved.TypeOptions || []; for (var i = 0; i < to.length; i++) if (to[i].Type === t) return to[i]; return ({}) }
        // checked = in the saved list, else the plugin's DefaultEnabled (web's fallback)
        function mapChecked(plugins, order, savedList) {
            return orderedPlugins(plugins, order).map(function (p) {
                return { name: p.Name, checked: savedList ? (savedList.indexOf(p.Name) >= 0) : !!p.DefaultEnabled }
            })
        }
        // inverse: checked = NOT in the disabled list, else DefaultEnabled
        function mapDisabled(plugins, order, disabledList) {
            return orderedPlugins(plugins, order).map(function (p) {
                return { name: p.Name, checked: disabledList ? (disabledList.indexOf(p.Name) < 0) : !!p.DefaultEnabled }
            })
        }
        var s = ({})
        s.metadataSavers = (a.MetadataSavers || []).map(function (p) {
            return { name: p.Name, checked: saved.MetadataSavers ? (saved.MetadataSavers.indexOf(p.Name) >= 0) : !!p.DefaultEnabled }
        })
        var rdrs = orderedPlugins(a.MetadataReaders, saved.LocalMetadataReaderOrder) // order-only; web shows only when >= 2
        s.metadataReaders = (rdrs.length >= 2) ? rdrs.map(function (p) { return p.Name }) : []
        var hasSub = (a.SubtitleFetchers || []).length > 0
        s.subtitleLanguages = hasSub ? subLangAll.map(function (c) {
            return { lang: c.lang, name: c.name, checked: saved.SubtitleDownloadLanguages ? (saved.SubtitleDownloadLanguages.indexOf(c.lang) >= 0) : false }
        }) : []
        s.subtitleFetchers = mapDisabled(a.SubtitleFetchers, saved.SubtitleFetcherOrder, saved.DisabledSubtitleFetchers)
        s.lyricFetchers = mapDisabled(a.LyricFetchers, saved.LyricFetcherOrder, saved.DisabledLyricFetchers)
        s.mediaSegmentProviders = mapDisabled(a.MediaSegmentProviders, saved.MediaSegmentProviderOrder, saved.DisabledMediaSegmentProviders)
        s.metadataFetchers = []; s.imageFetchers = []; s.similarItemProviders = []
        var to = a.TypeOptions || []
        for (var i = 0; i < to.length; i++) {
            var t = to[i]; var lt = typeOpt(t.Type); var pl = typePlural(t.Type)
            var mf = mapChecked(t.MetadataFetchers, lt.MetadataFetcherOrder, lt.MetadataFetchers)
            if (mf.length) s.metadataFetchers.push({ type: t.Type, plural: pl, plugins: mf })
            var imf = mapChecked(t.ImageFetchers, lt.ImageFetcherOrder, lt.ImageFetchers)
            if (imf.length) s.imageFetchers.push({ type: t.Type, plural: pl, plugins: imf,
                supportedImageTypes: t.SupportedImageTypes || [], defaultImageOptions: t.DefaultImageOptions || [],
                savedImageOptions: lt.ImageOptions || null, imageOptions: null }) // imageOptions: null = untouched (preserve saved)
            var sip = mapChecked(t.SimilarItemProviders, lt.SimilarItemProviderOrder, lt.SimilarItemProviders)
            if (sip.length) s.similarItemProviders.push({ type: t.Type, plural: pl, plugins: sip })
        }
        provState = s
    }
    function provClone() { return provState ? JSON.parse(JSON.stringify(provState)) : ({}) }
    function provToggle(table, typeIdx, i) {
        var s = provClone(); var arr = (typeIdx < 0) ? s[table] : (s[table] && s[table][typeIdx] ? s[table][typeIdx].plugins : null)
        if (!arr || !arr[i]) return; arr[i].checked = !arr[i].checked; provState = s
    }
    function provMove(table, typeIdx, i, dir) {
        var s = provClone(); var arr = (typeIdx < 0) ? s[table] : (s[table] && s[table][typeIdx] ? s[table][typeIdx].plugins : null)
        var j = i + dir; if (!arr || j < 0 || j >= arr.length) return
        var tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp; provState = s
    }
    function provMoveReader(i, dir) {
        var s = provClone(); var arr = s.metadataReaders || []
        var j = i + dir; if (j < 0 || j >= arr.length) return
        var tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp; provState = s
    }
    function provToggleLang(i) {
        var s = provClone(); var arr = s.subtitleLanguages || []
        if (!arr[i]) return; arr[i].checked = !arr[i].checked; provState = s
    }
    // serialize the provider tables back into a LibraryOptions object (web's getLibraryOptions)
    function serializeProviders(opts) {
        var s = provState || ({})
        function checkedNames(arr) { return (arr || []).filter(function (p) { return p.checked }).map(function (p) { return p.name }) }
        function uncheckedNames(arr) { return (arr || []).filter(function (p) { return !p.checked }).map(function (p) { return p.name }) }
        function allNames(arr) { return (arr || []).map(function (p) { return p.name }) }
        opts.MetadataSavers = checkedNames(s.metadataSavers)
        if (s.metadataReaders && s.metadataReaders.length) opts.LocalMetadataReaderOrder = s.metadataReaders.slice()
        if (s.subtitleLanguages && s.subtitleLanguages.length)
            opts.SubtitleDownloadLanguages = s.subtitleLanguages.filter(function (l) { return l.checked }).map(function (l) { return l.lang })
        if (s.subtitleFetchers && s.subtitleFetchers.length) { opts.DisabledSubtitleFetchers = uncheckedNames(s.subtitleFetchers); opts.SubtitleFetcherOrder = allNames(s.subtitleFetchers) }
        if (s.lyricFetchers && s.lyricFetchers.length) { opts.DisabledLyricFetchers = uncheckedNames(s.lyricFetchers); opts.LyricFetcherOrder = allNames(s.lyricFetchers) }
        if (s.mediaSegmentProviders && s.mediaSegmentProviders.length) { opts.DisabledMediaSegmentProviders = uncheckedNames(s.mediaSegmentProviders); opts.MediaSegmentProviderOrder = allNames(s.mediaSegmentProviders) }
        if (!opts.TypeOptions) opts.TypeOptions = []
        function getTO(t) { for (var i = 0; i < opts.TypeOptions.length; i++) if (opts.TypeOptions[i].Type === t) return opts.TypeOptions[i]; var n = { Type: t }; opts.TypeOptions.push(n); return n }
        var mf = s.metadataFetchers || []
        for (var x = 0; x < mf.length; x++) { var a = getTO(mf[x].type); a.MetadataFetchers = checkedNames(mf[x].plugins); a.MetadataFetcherOrder = allNames(mf[x].plugins) }
        var imf = s.imageFetchers || []
        for (var y = 0; y < imf.length; y++) {
            var b = getTO(imf[y].type); b.ImageFetchers = checkedNames(imf[y].plugins); b.ImageFetcherOrder = allNames(imf[y].plugins)
            if (imf[y].imageOptions !== null && imf[y].imageOptions !== undefined) b.ImageOptions = imf[y].imageOptions // only when edited via Fetcher settings
        }
        var sip = s.similarItemProviders || []
        for (var z = 0; z < sip.length; z++) { var c = getTO(sip[z].type); c.SimilarItemProviders = checkedNames(sip[z].plugins); c.SimilarItemProviderOrder = allNames(sip[z].plugins) }
        return opts
    }
    // per-type Fetcher settings (ImageOptions): which image types to fetch + backdrop count/min-width
    function findOpt(arr, tp) { for (var i = 0; i < (arr || []).length; i++) if (arr[i].Type === tp) return arr[i]; return null }
    function openFetcherSettings(idx) {
        var e = provState.imageFetchers[idx]; if (!e) return
        fsIndex = idx; fsType = e.type; fsSupported = e.supportedImageTypes || []
        var base = e.imageOptions || e.savedImageOptions || []
        var defs = e.defaultImageOptions || []
        var lims = ({})
        for (var i = 0; i < fsSupported.length; i++) {
            var tp = fsSupported[i]
            var cfg = findOpt(base, tp) || findOpt(defs, tp) || { Limit: (tp === "Primary" ? 1 : 0), MinWidth: 0 }
            lims[tp] = (cfg.Limit || 0) > 0
        }
        fsLimits = lims
        var bd = findOpt(base, "Backdrop") || findOpt(defs, "Backdrop") || { Limit: 0, MinWidth: 0 }
        fsMaxBackdrops = bd.Limit || 0
        fsMinBackdropWidth = bd.MinWidth || 0
        fsDialog.open()
    }
    function fsSetLimit(tp, val) { var m = Object.assign({}, fsLimits); m[tp] = val; fsLimits = m }
    function saveFetcherSettings() {
        var s = provClone(); var e = s.imageFetchers[fsIndex]; if (!e) { fsDialog.close(); return }
        var opts = []
        for (var i = 0; i < fsSupported.length; i++) {
            var tp = fsSupported[i]
            if (tp === "Backdrop") continue
            opts.push({ Type: tp, Limit: (fsLimits[tp] ? 1 : 0), MinWidth: 0 })
        }
        if (fsSupported.indexOf("Backdrop") >= 0)
            opts.push({ Type: "Backdrop", Limit: fsMaxBackdrops, MinWidth: fsMinBackdropWidth })
        e.imageOptions = opts; provState = s; fsDialog.close()
    }

    component PolicyToggle: RowLayout {
        id: pt
        property string label: ""
        property string flag: ""
        Layout.fillWidth: true
        Text { text: pt.label; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
        Rectangle {
            id: sw
            readonly property bool on: screen.editPolicy[pt.flag] === true
            width: 44; height: 24; radius: 12
            color: on ? Theme.accent : Theme.elevated
            Rectangle { width: 18; height: 18; radius: 9; y: 3; x: sw.on ? 23 : 3; color: Theme.textPrimary; Behavior on x { NumberAnimation { duration: 120 } } }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: screen.setFlag(pt.flag, !sw.on) }
        }
    }
    component PolicyNumber: RowLayout {
        id: pn
        property string label: ""
        property string flag: ""
        property real scale: 1     // display = value/scale; save = value*scale (e.g. 1e6 for Mbps)
        Layout.fillWidth: true
        Text { text: pn.label; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
        TextField {
            Layout.preferredWidth: 160
            text: { var v = screen.editPolicy[pn.flag]; if (v === undefined || v === null) return ""; return pn.scale !== 1 ? ("" + (v / pn.scale)) : ("" + v) }
            inputMethodHints: Qt.ImhFormattedNumbersOnly; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall
            onEditingFinished: screen.setFlag(pn.flag, pn.scale !== 1 ? Math.floor(parseFloat(text || "0") * pn.scale) : (parseInt(text || "0") || 0))
            background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 }
        }
    }
    component PolicySelect: RowLayout {
        id: psel
        property string label: ""
        property string flag: ""               // bind to editPolicy[flag], OR…
        property var currentValue: undefined   // …use currentValue + changed() when flag is empty
        signal changed(var value)
        property var options: []
        function sync() { var cur = psel.flag ? screen.editPolicy[psel.flag] : psel.currentValue; for (var i = 0; i < psel.options.length; i++) if (String(psel.options[i].value) === String(cur)) { pbox.currentIndex = i; return } pbox.currentIndex = -1 }
        onCurrentValueChanged: sync()
        onOptionsChanged: sync()
        Connections { target: screen; function onEditPolicyChanged() { psel.sync() } }
        Layout.fillWidth: true
        Text { text: psel.label; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
        ComboBox {
            id: pbox
            Layout.preferredWidth: 280; implicitHeight: 34
            model: psel.options; textRole: "text"
            Component.onCompleted: psel.sync()
            onActivated: (idx) => { if (psel.flag) screen.setFlag(psel.flag, psel.options[idx].value); else psel.changed(psel.options[idx].value) }
            background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: pbox.activeFocus || pbox.hovered ? Theme.accent : Theme.divider; border.width: 1 }
            contentItem: Text { text: pbox.currentIndex >= 0 ? pbox.displayText : qsTr("—"); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; leftPadding: 10; rightPadding: 26; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
            indicator: Text { x: pbox.width - width - 10; y: (pbox.height - height) / 2; text: "▾"; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall }
            popup: Popup {
                y: pbox.height + 2; width: pbox.width; implicitHeight: Math.min(plist.contentHeight + 2, 240); padding: 1
                background: Rectangle { color: Theme.elevated; radius: Theme.radius; border.color: Theme.divider; border.width: 1 }
                contentItem: ListView { id: plist; clip: true; model: pbox.popup.visible ? pbox.delegateModel : null; currentIndex: pbox.highlightedIndex; ScrollBar.vertical: ScrollBar {} }
            }
            delegate: ItemDelegate {
                required property var modelData
                required property int index
                width: pbox.width; implicitHeight: 32; hoverEnabled: true
                contentItem: Text { text: modelData.text; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; leftPadding: 10; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                background: Rectangle { color: hovered ? Theme.surfaceHover : "transparent" }
            }
        }
    }

    // a checkbox list whose checked ids live in an editPolicy array (Enabled{Folders,Channels,Devices})
    component AccessCheckList: ColumnLayout {
        id: acl
        property var items: []       // [{id, name}]
        property string listKey: ""
        Layout.fillWidth: true; spacing: 2
        Repeater {
            model: acl.items
            Rectangle {
                required property var modelData
                Layout.fillWidth: true; implicitHeight: 34; radius: Theme.radius; color: Theme.surface
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: Theme.spacingSmall; anchors.rightMargin: Theme.spacingSmall; spacing: Theme.spacingSmall
                    Rectangle {
                        id: aclChk
                        readonly property bool on: screen.inEnabled(acl.listKey, modelData.id)
                        width: 20; height: 20; radius: 4
                        color: on ? Theme.accent : Theme.elevated; border.color: Theme.divider; border.width: 1
                        Text { anchors.centerIn: parent; text: aclChk.on ? "✓" : ""; color: Theme.accentText; font.pixelSize: Theme.fontSmall; font.bold: true }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: screen.toggleEnabled(acl.listKey, modelData.id) }
                    }
                    Text { text: ("" + modelData.name); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; elide: Text.ElideRight }
                }
            }
        }
    }

    // editable list of string tags (AllowedTags / BlockedTags)
    component TagEditor: ColumnLayout {
        id: te
        property string flag: ""
        Layout.fillWidth: true; spacing: 4
        Flow {
            Layout.fillWidth: true; spacing: Theme.spacingSmall
            Repeater {
                model: screen.editPolicy[te.flag] || []
                Rectangle {
                    required property var modelData
                    implicitWidth: chipRow.implicitWidth + 16; implicitHeight: 28; radius: Theme.radius; color: Theme.surface; border.color: Theme.divider; border.width: 1
                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent; spacing: 6
                        Text { text: ("" + modelData); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall }
                        Text { text: "✕"; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; TapHandler { onTapped: screen.removeTag(te.flag, modelData) } }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.spacingSmall
            TextField {
                id: tagInput
                Layout.preferredWidth: 220; placeholderText: qsTr("Add tag…"); color: Theme.textPrimary; placeholderTextColor: Theme.textDisabled; font.pixelSize: Theme.fontSmall
                onAccepted: { if (text.length) { screen.addTag(te.flag, text); clear() } }
                background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 }
            }
            DashButton { text: qsTr("Add"); onClicked: { if (tagInput.text.length) { screen.addTag(te.flag, tagInput.text); tagInput.clear() } } }
        }
    }

    component DashButton: Rectangle {
        id: db
        property string text: ""
        property bool danger: false
        signal clicked()
        implicitHeight: 34; implicitWidth: lbl.implicitWidth + 28; radius: Theme.radius
        color: ma.containsMouse ? Theme.surfaceHover : Theme.surface
        border.color: danger ? Theme.error : Theme.divider; border.width: 1
        Text { id: lbl; anchors.centerIn: parent; text: db.text; color: db.danger ? Theme.error : Theme.textPrimary; font.pixelSize: Theme.fontSmall }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: db.clicked() }
    }

    // editConfig accessors with dot-path support (e.g. "TrickplayOptions.Interval").
    // setConfig deep-clones so a nested edit still flips the top-level ref (reactivity).
    function cfgGet(path) {
        var o = editConfig
        var parts = ("" + path).split(".")
        for (var i = 0; i < parts.length; i++) {
            if (o === null || o === undefined) return undefined
            o = o[parts[i]]
        }
        return o
    }
    function setConfig(path, val) {
        var c = editConfig ? JSON.parse(JSON.stringify(editConfig)) : ({})
        var parts = ("" + path).split(".")
        var o = c
        for (var i = 0; i < parts.length - 1; i++) {
            if (o[parts[i]] === null || o[parts[i]] === undefined) o[parts[i]] = ({})
            o = o[parts[i]]
        }
        o[parts[parts.length - 1]] = val
        editConfig = c
    }
    // Optional per-field conditional visibility: showWhen {key, eq|neq|oneOf}
    // evaluated against the live editConfig (e.g. show VAAPI device only for vaapi).
    function fieldVisible(fld) {
        if (!fld) return true
        // per-library-type gating for LibraryOptions (mirrors web's setContentType):
        // a field with a `types` list only shows for the selected library's type.
        if (fld.types) {
            var ct = selectedLib ? (selectedLib.CollectionType || "mixed") : "mixed"
            if (fld.types.indexOf(ct) < 0) return false
        }
        if (!fld.showWhen) return true
        var w = fld.showWhen
        var cur = cfgGet(w.key)
        if (w.eq !== undefined) return cur === w.eq
        if (w.neq !== undefined) return cur !== w.neq
        if (w.oneOf !== undefined) return w.oneOf.indexOf(cur) >= 0
        return true
    }
    component ConfigField: RowLayout {
        id: cf
        property string label: ""
        property string key: ""
        property string mode: "text"     // text | number | float | csv (int list) | list (string list)
        property real scale: 1           // number display divisor (e.g. 1e6 = bps shown as Mbps)
        property bool secret: false      // mask the input (passwords)
        property bool browse: false      // show a "Browse…" button → server directory picker
        property bool ro: false          // read-only display field (e.g. detected FFmpeg path)
        function display() {
            var v = screen.cfgGet(cf.key)
            if (v === undefined || v === null) return ""
            if (cf.mode === "csv") return (typeof v !== "string" && v.length !== undefined) ? v.join(",") : ("" + v)
            if (cf.mode === "list") return (typeof v !== "string" && v.length !== undefined) ? v.join(", ") : ("" + v)
            if (cf.mode === "number" && cf.scale !== 1) return v ? ("" + (v / cf.scale)) : ""
            return "" + v
        }
        function commit(t) {
            if (cf.mode === "csv")
                screen.setConfig(cf.key, ("" + t).replace(/\s/g, "").split(",").filter(function (x) { return x.length }).map(Number))
            else if (cf.mode === "list")
                screen.setConfig(cf.key, ("" + t).split(",").map(function (x) { return x.trim() }).filter(function (x) { return x.length }))
            else if (cf.mode === "float")
                screen.setConfig(cf.key, parseFloat(t) || 0)
            else if (cf.mode === "number")
                screen.setConfig(cf.key, cf.scale !== 1 ? Math.trunc(cf.scale * (parseFloat(t) || 0)) : (parseInt(t) || 0))
            else
                screen.setConfig(cf.key, t)
        }
        Layout.fillWidth: true
        Text { text: cf.label; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
        TextField {
            Layout.preferredWidth: 340
            text: cf.display()
            color: Theme.textPrimary; placeholderTextColor: Theme.textDisabled; font.pixelSize: Theme.fontSmall
            echoMode: cf.secret ? TextInput.Password : TextInput.Normal
            readOnly: cf.ro
            inputMethodHints: (cf.mode === "number" || cf.mode === "float") ? Qt.ImhFormattedNumbersOnly : Qt.ImhNone
            onEditingFinished: if (!cf.ro) cf.commit(text)
            background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 }
        }
        DashButton { visible: cf.browse; text: qsTr("Browse…"); onClicked: screen.openDirPicker(cf.key) }
    }
    component ConfigToggle: RowLayout {
        id: ct
        property string label: ""
        property string key: ""
        Layout.fillWidth: true
        Text { text: ct.label; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
        Rectangle {
            id: cs
            readonly property bool on: screen.cfgGet(ct.key) === true
            width: 44; height: 24; radius: 12; color: on ? Theme.accent : Theme.elevated
            Rectangle { width: 18; height: 18; radius: 9; y: 3; x: cs.on ? 23 : 3; color: Theme.textPrimary; Behavior on x { NumberAnimation { duration: 120 } } }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: screen.setConfig(ct.key, !cs.on) }
        }
    }
    component ConfigSelect: RowLayout {
        id: csel
        property string label: ""
        property string key: ""
        property var options: []          // [{value, text}]
        function syncIndex() {
            var cur = screen.cfgGet(csel.key)
            if (cur === undefined || cur === null) cur = "" // null resolves to the "Any/None" option
            for (var i = 0; i < csel.options.length; i++)
                if (String(csel.options[i].value) === String(cur)) { cbox.currentIndex = i; return }
            cbox.currentIndex = -1
        }
        onOptionsChanged: syncIndex()
        // editConfig is assigned just after serverConfig, but the Repeater builds us
        // synchronously on the serverConfig change — so re-sync once editConfig lands.
        Connections { target: screen; function onEditConfigChanged() { csel.syncIndex() } }
        Layout.fillWidth: true
        Text { text: csel.label; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
        ComboBox {
            id: cbox
            Layout.preferredWidth: 340
            implicitHeight: 34
            model: csel.options
            textRole: "text"
            Component.onCompleted: csel.syncIndex()
            onActivated: (idx) => screen.setConfig(csel.key, csel.options[idx].value)
            background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: cbox.activeFocus || cbox.hovered ? Theme.accent : Theme.divider; border.width: 1 }
            contentItem: Text { text: cbox.currentIndex >= 0 ? cbox.displayText : qsTr("—"); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; leftPadding: 10; rightPadding: 26; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
            indicator: Text { x: cbox.width - width - 10; y: (cbox.height - height) / 2; text: "▾"; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall }
            popup: Popup {
                y: cbox.height + 2; width: cbox.width
                implicitHeight: Math.min(clist.contentHeight + 2, 300); padding: 1
                background: Rectangle { color: Theme.elevated; radius: Theme.radius; border.color: Theme.divider; border.width: 1 }
                contentItem: ListView {
                    id: clist
                    clip: true
                    model: cbox.popup.visible ? cbox.delegateModel : null
                    currentIndex: cbox.highlightedIndex
                    ScrollBar.vertical: ScrollBar { active: true }
                }
            }
            delegate: ItemDelegate {
                required property var modelData
                required property int index
                width: cbox.width; implicitHeight: 32; hoverEnabled: true
                contentItem: Text { text: modelData.text; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; leftPadding: 10; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                background: Rectangle { color: hovered ? Theme.surfaceHover : "transparent" }
            }
        }
    }

    // Reusable renderer for a field descriptor list (group headers + control +
    // helper text + showWhen), editing the shared editConfig via cfgGet/setConfig.
    // Used by the server-config pages AND a library's LibraryOptions.
    component ConfigFieldList: ColumnLayout {
        id: cfl
        property var fields: []
        Layout.fillWidth: true
        spacing: Theme.spacingSmall
        Component { id: cflField; ConfigField { label: parent.modelData.label; key: parent.modelData.key; mode: parent.modelData.type === "csv" ? "csv" : (parent.modelData.type === "number" ? "number" : (parent.modelData.type === "float" ? "float" : (parent.modelData.type === "list" ? "list" : "text"))); scale: parent.modelData.scale || 1; secret: parent.modelData.type === "password"; browse: parent.modelData.browse === true; ro: parent.modelData.readonly === true } }
        Component { id: cflToggle; ConfigToggle { label: parent.modelData.label; key: parent.modelData.key } }
        Component { id: cflSelect; ConfigSelect { label: parent.modelData.label; key: parent.modelData.key; options: parent.modelData.options || (parent.modelData.optionsKey ? (screen.dynOptions[parent.modelData.optionsKey] || []) : []) } }
        Repeater {
            model: cfl.fields
            ColumnLayout {
                id: fieldRow
                required property var modelData
                required property int index
                Layout.fillWidth: true
                visible: screen.fieldVisible(fieldRow.modelData)
                spacing: 3
                Text {
                    visible: !!fieldRow.modelData.group && (fieldRow.index === 0 || cfl.fields[fieldRow.index - 1].group !== fieldRow.modelData.group)
                    text: fieldRow.modelData.group || ""
                    color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true
                    Layout.topMargin: fieldRow.index === 0 ? 0 : Theme.spacing
                    Layout.bottomMargin: 2
                }
                Loader {
                    property var modelData: fieldRow.modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: item ? item.implicitHeight : 0
                    sourceComponent: modelData.type === "toggle" ? cflToggle : (modelData.type === "select" ? cflSelect : cflField)
                }
                Text {
                    visible: !!fieldRow.modelData.help
                    text: fieldRow.modelData.help || ""
                    color: Theme.textSecondary; font.pixelSize: Theme.fontTiny
                    textFormat: Text.StyledText; linkColor: Theme.accent
                    onLinkActivated: (l) => Qt.openUrlExternally(l)
                    wrapMode: Text.Wrap; Layout.fillWidth: true; Layout.leftMargin: 4; Layout.maximumWidth: 760
                    Layout.bottomMargin: Theme.spacingSmall
                }
            }
        }
    }

    // A provider "table": header + helper text + rows of [checkbox] name [▲ ▼].
    // rows = [{name, checked}] for checkbox tables, or [name,…] for order-only.
    component PluginTable: ColumnLayout {
        id: ptbl
        property string title: ""
        property string help: ""
        property var rows: []
        property bool showCheck: true   // false = order-only list (e.g. metadata readers)
        property bool showOrder: true   // false = checkbox-only (savers, languages)
        property bool showFetcherSettings: false
        signal toggled(int index)
        signal movedUp(int index)
        signal movedDown(int index)
        signal fetcherSettings()
        visible: rows && rows.length > 0
        Layout.fillWidth: true
        spacing: 2
        RowLayout {
            Layout.fillWidth: true; Layout.topMargin: Theme.spacingSmall
            Text { text: ptbl.title; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true; Layout.fillWidth: true; verticalAlignment: Text.AlignVCenter }
            DashButton { visible: ptbl.showFetcherSettings; text: qsTr("Fetcher settings"); onClicked: ptbl.fetcherSettings() }
        }
        Repeater {
            model: ptbl.rows
            Rectangle {
                required property var modelData
                required property int index
                Layout.fillWidth: true; implicitHeight: 38; radius: Theme.radius; color: Theme.surface
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: Theme.spacingSmall; anchors.rightMargin: Theme.spacingSmall; spacing: Theme.spacingSmall
                    Rectangle {
                        visible: ptbl.showCheck
                        width: 22; height: 22; radius: 4
                        color: (modelData.checked === true) ? Theme.accent : Theme.elevated
                        border.color: Theme.divider; border.width: 1
                        Text { anchors.centerIn: parent; text: (modelData.checked === true) ? "✓" : ""; color: Theme.accentText; font.pixelSize: Theme.fontSmall; font.bold: true }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ptbl.toggled(index) }
                    }
                    Text { text: ptbl.showCheck ? ("" + modelData.name) : ("" + modelData); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; elide: Text.ElideRight; leftPadding: 2; verticalAlignment: Text.AlignVCenter }
                    DashButton { visible: ptbl.showOrder && index > 0; text: "▲"; onClicked: ptbl.movedUp(index) }
                    DashButton { visible: ptbl.showOrder && index < ptbl.rows.length - 1; text: "▼"; onClicked: ptbl.movedDown(index) }
                }
            }
        }
        Text {
            visible: !!ptbl.help; text: ptbl.help
            color: Theme.textSecondary; font.pixelSize: Theme.fontTiny; wrapMode: Text.Wrap
            Layout.fillWidth: true; Layout.maximumWidth: 760; Layout.leftMargin: 4; Layout.bottomMargin: Theme.spacingSmall
        }
    }

    Popup {
        id: confirmPopup
        property string message: ""
        x: (screen.width - width) / 2
        y: (screen.height - height) / 2
        modal: true; dim: true
        width: 380; padding: Theme.spacing
        background: Rectangle { color: Theme.elevated; radius: Theme.radius; border.color: Theme.divider; border.width: 1 }
        contentItem: ColumnLayout {
            spacing: Theme.spacing
            Text { text: confirmPopup.message; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; wrapMode: Text.Wrap; Layout.fillWidth: true; Layout.preferredWidth: 340 }
            RowLayout {
                Layout.alignment: Qt.AlignRight; spacing: Theme.spacingSmall
                DashButton { text: qsTr("Cancel"); onClicked: confirmPopup.close() }
                DashButton { text: qsTr("Confirm"); danger: true; onClicked: { confirmPopup.close(); if (screen.pendingAction) screen.pendingAction() } }
            }
        }
    }

    // generic single-field input dialog (rename device, new API key, …)
    Popup {
        id: inputPopup
        property string title: ""
        property string placeholder: ""
        x: (screen.width - width) / 2; y: (screen.height - height) / 2
        modal: true; dim: true; width: 380; padding: Theme.spacing
        background: Rectangle { color: Theme.elevated; radius: Theme.radius; border.color: Theme.divider; border.width: 1 }
        contentItem: ColumnLayout {
            spacing: Theme.spacing
            Text { text: inputPopup.title; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true; Layout.fillWidth: true }
            TextField {
                id: inputField
                Layout.fillWidth: true; placeholderText: inputPopup.placeholder
                color: Theme.textPrimary; placeholderTextColor: Theme.textDisabled; font.pixelSize: Theme.fontSmall
                onAccepted: { inputPopup.close(); if (screen.inputAction) screen.inputAction(text) }
                background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 }
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight; spacing: Theme.spacingSmall
                DashButton { text: qsTr("Cancel"); onClicked: inputPopup.close() }
                DashButton { text: qsTr("OK"); onClicked: { inputPopup.close(); if (screen.inputAction) screen.inputAction(inputField.text) } }
            }
        }
    }

    // per-type image "Fetcher settings" (ImageOptions) — mirrors imageOptionsEditor
    Popup {
        id: fsDialog
        x: (screen.width - width) / 2; y: (screen.height - height) / 2
        modal: true; dim: true; width: 440; padding: Theme.spacing
        background: Rectangle { color: Theme.elevated; radius: Theme.radius; border.color: Theme.divider; border.width: 1 }
        contentItem: ColumnLayout {
            spacing: Theme.spacingSmall
            Text { text: qsTr("Image fetcher settings — %1").arg(screen.typePlural(screen.fsType)); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true; Layout.fillWidth: true }
            Text { text: qsTr("Choose which image types to download."); color: Theme.textSecondary; font.pixelSize: Theme.fontTiny; Layout.fillWidth: true; Layout.bottomMargin: Theme.spacingSmall }
            Repeater {
                model: screen.fsSupported
                RowLayout {
                    required property var modelData
                    visible: modelData !== "Backdrop"
                    Layout.fillWidth: true
                    Text { text: qsTr("Fetch %1 images").arg(modelData); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4 }
                    Rectangle {
                        id: fsTog
                        readonly property bool on: screen.fsLimits[modelData] === true
                        width: 44; height: 24; radius: 12; color: on ? Theme.accent : Theme.elevated
                        Rectangle { width: 18; height: 18; radius: 9; y: 3; x: fsTog.on ? 23 : 3; color: Theme.textPrimary; Behavior on x { NumberAnimation { duration: 120 } } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: screen.fsSetLimit(modelData, !fsTog.on) }
                    }
                }
            }
            RowLayout {
                visible: screen.fsSupported.indexOf("Backdrop") >= 0
                Layout.fillWidth: true
                Text { text: qsTr("Maximum backdrops"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4 }
                TextField { Layout.preferredWidth: 120; text: "" + screen.fsMaxBackdrops; inputMethodHints: Qt.ImhDigitsOnly; onEditingFinished: screen.fsMaxBackdrops = parseInt(text) || 0; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall
                    background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 } }
            }
            RowLayout {
                visible: screen.fsSupported.indexOf("Backdrop") >= 0
                Layout.fillWidth: true
                Text { text: qsTr("Minimum backdrop download width"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4 }
                TextField { Layout.preferredWidth: 120; text: "" + screen.fsMinBackdropWidth; inputMethodHints: Qt.ImhDigitsOnly; onEditingFinished: screen.fsMinBackdropWidth = parseInt(text) || 0; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall
                    background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 } }
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight; Layout.topMargin: Theme.spacing; spacing: Theme.spacingSmall
                DashButton { text: qsTr("Cancel"); onClicked: fsDialog.close() }
                DashButton { text: qsTr("Apply"); onClicked: screen.saveFetcherSettings() }
            }
        }
    }

    DirectoryPicker {
        id: dirPicker
        client: screen.client
        onPicked: (chosenPath) => {
            if (screen._dirPickMode === "config") screen.setConfig(screen._dirPickKey, chosenPath)
            else if (screen._dirPickMode === "newlib") screen.newLibPath = chosenPath
            else if (screen._dirPickMode === "addpath" && screen.selectedLib)
                screen.confirm(qsTr("Add folder “%1” to “%2”?").arg(chosenPath).arg(screen.selectedLib.Name),
                               function () { screen.client.addMediaPath(screen.selectedLib.Name, chosenPath); screen.libReloadTimer.restart() })
        }
    }
    // Re-fetch the library list shortly after a (fire-and-forget) mutation so the
    // UI reflects it without the user re-entering the page.
    Timer { id: libReloadTimer; interval: 800; repeat: false; onTriggered: screen.reloadLibs() }
    Timer { id: usersReloadTimer; interval: 800; repeat: false; onTriggered: if (screen.client) screen.client.getJson("/Users", "admin:users") }
    Timer { id: panelReloadTimer; interval: 800; repeat: false; onTriggered: { var e = screen.navModel[screen.sel]; if (screen.client && e && e.ep) screen.client.getJson(e.ep, "admin:panel") } }
    function promptInput(title, placeholder, initial, action) { inputPopup.title = title; inputPopup.placeholder = placeholder; screen.inputValue = initial || ""; screen.inputAction = action; inputField.text = initial || ""; inputPopup.open(); inputField.forceActiveFocus() }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // grouped nav
        Rectangle {
            Layout.preferredWidth: 240
            Layout.fillHeight: true
            color: Theme.backgroundAlt
            Flickable {
                anchors.fill: parent
                contentHeight: navCol.implicitHeight + Theme.spacing
                clip: true
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: navCol
                    width: parent.width
                    y: Theme.spacingSmall
                    spacing: 1
                    Repeater {
                        model: screen.navModel
                        ColumnLayout {
                            required property int index
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                visible: index === 0 || screen.navModel[index - 1].group !== modelData.group
                                text: modelData.group
                                color: Theme.textDisabled
                                font.pixelSize: Theme.fontTiny
                                font.bold: true
                                Layout.leftMargin: Theme.spacing
                                Layout.topMargin: Theme.spacingSmall
                                Layout.bottomMargin: 2
                            }
                            ItemDelegate {
                                Layout.fillWidth: true
                                implicitHeight: 38
                                hoverEnabled: true
                                onClicked: screen.sel = index
                                contentItem: Text {
                                    text: modelData.label
                                    color: screen.sel === index ? Theme.accent : Theme.textPrimary
                                    font.pixelSize: Theme.fontNormal
                                    font.bold: screen.sel === index
                                    leftPadding: Theme.spacing + 6
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                background: Rectangle {
                                    color: parent.hovered ? Theme.surfaceHover : "transparent"
                                    Rectangle { width: 3; height: parent.height; color: Theme.accent; visible: screen.sel === index }
                                }
                            }
                        }
                    }
                }
            }
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.divider }
        }

        // content
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: body.implicitHeight + Theme.spacingLarge * 2
            clip: true
            ScrollBar.vertical: ScrollBar {}
            ColumnLayout {
                id: body
                width: parent.width - Theme.pagePad * 2
                x: Theme.pagePad
                y: Theme.spacingLarge
                spacing: Theme.spacingSmall

                Text {
                    text: screen.selEntry.label || ""
                    color: Theme.textPrimary; font.pixelSize: Theme.fontLarge; font.bold: true
                    Layout.bottomMargin: Theme.spacingSmall
                }

                // dashboard — formatted server card + library counts + sessions + actions
                ColumnLayout {
                    visible: screen.selEntry.kind === "dashboard"
                    Layout.fillWidth: true
                    spacing: Theme.spacing
                    Rectangle {
                        Layout.fillWidth: true; radius: Theme.radius; color: Theme.surface
                        implicitHeight: srv.implicitHeight + Theme.spacing * 2
                        ColumnLayout {
                            id: srv
                            x: Theme.spacing; y: Theme.spacing; width: parent.width - Theme.spacing * 2
                            spacing: 4
                            Text { text: (screen.dashInfo ? screen.dashInfo.ServerName : qsTr("Server")) + "  ·  Jellyfin " + (screen.dashInfo ? screen.dashInfo.Version : "—"); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true }
                            Text { text: screen.dashInfo ? (screen.dashInfo.OperatingSystemDisplayName + " · " + screen.dashInfo.SystemArchitecture) : ""; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall }
                            RowLayout {
                                Layout.topMargin: Theme.spacingSmall; spacing: Theme.spacingSmall
                                DashButton { text: qsTr("Scan all libraries"); onClicked: screen.confirm(qsTr("Start a scan of all libraries now?"), function() { screen.client.scanAllLibraries() }) }
                                DashButton { text: qsTr("Restart"); danger: true; onClicked: screen.confirm(qsTr("Restart the Jellyfin server now?"), function() { screen.client.restartServer() }) }
                                DashButton { text: qsTr("Shut down"); danger: true; onClicked: screen.confirm(qsTr("Shut down the Jellyfin server now?"), function() { screen.client.shutdownServer() }) }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Theme.spacingSmall
                        Repeater {
                            model: [{k: "MovieCount", t: qsTr("Movies")}, {k: "SeriesCount", t: qsTr("Series")}, {k: "EpisodeCount", t: qsTr("Episodes")}, {k: "BoxSetCount", t: qsTr("Collections")}]
                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true; implicitHeight: 64; radius: Theme.radius; color: Theme.surface
                                ColumnLayout {
                                    anchors.centerIn: parent; spacing: 0
                                    Text { text: screen.dashCounts ? ("" + (screen.dashCounts[modelData.k] || 0)) : "—"; color: Theme.accent; font.pixelSize: Theme.fontLarge; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                                    Text { text: modelData.t; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; Layout.alignment: Qt.AlignHCenter }
                                }
                            }
                        }
                    }
                    Text { text: qsTr("Active devices (%1)").arg(screen.dashSessions.length); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                    Repeater {
                        model: screen.dashSessions
                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; implicitHeight: 44; radius: Theme.radius; color: Theme.surface
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: Theme.spacing; anchors.rightMargin: Theme.spacing; spacing: Theme.spacing
                                Text { text: ("" + (modelData.UserName || "—")); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; Layout.preferredWidth: 140; elide: Text.ElideRight }
                                Text { text: ((modelData.Client || "") + " · " + (modelData.DeviceName || "")); color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { text: (modelData.NowPlayingItem ? ("▶ " + modelData.NowPlayingItem.Name) : ""); color: Theme.accent; font.pixelSize: Theme.fontSmall; elide: Text.ElideRight; Layout.maximumWidth: 260 }
                            }
                        }
                    }
                }

                // scheduled tasks — grouped list with Run / Stop
                ColumnLayout {
                    visible: screen.selEntry.kind === "tasks"
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall
                    Repeater {
                        model: screen.tasksData
                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; implicitHeight: 56; radius: Theme.radius; color: Theme.surface
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: Theme.spacing; anchors.rightMargin: Theme.spacing; spacing: Theme.spacing
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 2
                                    Text { text: ("" + (modelData.Name || "—")); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Text {
                                        text: {
                                            var s = ("" + (modelData.Category || ""))
                                            if (modelData.State === "Running")
                                                return s + "  ·  " + qsTr("Running %1%").arg(Math.round(modelData.CurrentProgressPercentage || 0))
                                            var lr = modelData.LastExecutionResult
                                            if (lr && lr.Status) {
                                                s += "  ·  " + lr.Status
                                                var when = screen.relTime(lr.EndTimeUtc)
                                                var dur = screen.durationStr(lr.StartTimeUtc, lr.EndTimeUtc)
                                                if (when) s += " " + when
                                                if (dur) s += " (" + dur + ")"
                                            } else {
                                                s += "  ·  " + qsTr("never run")
                                            }
                                            return s
                                        }
                                        color: Theme.textSecondary; font.pixelSize: Theme.fontTiny; elide: Text.ElideRight; Layout.fillWidth: true
                                    }
                                }
                                DashButton { visible: modelData.State !== "Running"; text: qsTr("Run"); onClicked: screen.confirm(qsTr("Run “%1” now?").arg(modelData.Name), function() { screen.client.runScheduledTask(modelData.Id) }) }
                                DashButton { visible: modelData.State === "Running"; text: qsTr("Stop"); danger: true; onClicked: screen.client.stopScheduledTask(modelData.Id) }
                            }
                        }
                    }
                }

                // users — list, then per-user policy detail/edit on selection
                ColumnLayout {
                    visible: screen.selEntry.kind === "users"
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall
                    DashButton { visible: screen.selectedUser === null && !screen.userAddMode; text: qsTr("＋  Add user"); onClicked: { screen.newUserName = ""; screen.newUserPw = ""; screen.userAddMode = true } }
                    Repeater {
                        model: (screen.selectedUser === null && !screen.userAddMode) ? screen.usersData : []
                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; implicitHeight: 56; radius: Theme.radius; color: ma2.containsMouse ? Theme.surfaceHover : Theme.surface
                            MouseArea { id: ma2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: screen.selectUser(modelData) }
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: Theme.spacing; anchors.rightMargin: Theme.spacing; spacing: Theme.spacing
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 2
                                    Text { text: ("" + (modelData.Name || "—")); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal }
                                    Text { text: modelData.LastActivityDate ? qsTr("Last seen %1").arg(screen.relTime(modelData.LastActivityDate)) : qsTr("Never signed in"); color: Theme.textSecondary; font.pixelSize: Theme.fontTiny }
                                }
                                Text { visible: modelData.Policy && modelData.Policy.IsAdministrator === true; text: qsTr("ADMIN"); color: Theme.accent; font.pixelSize: Theme.fontTiny; font.bold: true }
                                Text { visible: modelData.Policy && modelData.Policy.IsDisabled === true; text: qsTr("DISABLED"); color: Theme.error; font.pixelSize: Theme.fontTiny; font.bold: true }
                            }
                        }
                    }
                    // add user
                    ColumnLayout {
                        visible: screen.userAddMode
                        Layout.fillWidth: true; spacing: Theme.spacingSmall
                        RowLayout {
                            Layout.fillWidth: true
                            DashButton { text: qsTr("← Back"); onClicked: screen.userAddMode = false }
                            Text { text: qsTr("Add user"); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true; Layout.fillWidth: true; leftPadding: Theme.spacing; verticalAlignment: Text.AlignVCenter }
                        }
                        RowLayout {
                            Layout.fillWidth: true; Layout.topMargin: Theme.spacingSmall
                            Text { text: qsTr("Name"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
                            TextField { Layout.preferredWidth: 280; text: screen.newUserName; onTextEdited: screen.newUserName = text; placeholderText: qsTr("Username"); color: Theme.textPrimary; placeholderTextColor: Theme.textDisabled; font.pixelSize: Theme.fontSmall
                                background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 } }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("Password (optional)"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
                            TextField { Layout.preferredWidth: 280; text: screen.newUserPw; onTextEdited: screen.newUserPw = text; echoMode: TextInput.Password; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall
                                background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 } }
                        }
                        RowLayout {
                            Layout.topMargin: Theme.spacing
                            DashButton { text: qsTr("Create user"); onClicked: screen.confirm(qsTr("Create the user “%1”?").arg(screen.newUserName || qsTr("(unnamed)")), function() { screen.client.createUser(screen.newUserName, screen.newUserPw); screen.userAddMode = false; screen.usersReloadTimer.restart() }) }
                        }
                    }

                    // per-user detail
                    ColumnLayout {
                        visible: screen.selectedUser !== null
                        Layout.fillWidth: true; spacing: Theme.spacingSmall
                        RowLayout {
                            Layout.fillWidth: true
                            DashButton { text: qsTr("← Back"); onClicked: screen.selectedUser = null }
                            Text { text: screen.selectedUser ? screen.selectedUser.Name : ""; color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true; Layout.fillWidth: true; leftPadding: Theme.spacing; verticalAlignment: Text.AlignVCenter }
                        }
                        RowLayout {
                            Layout.fillWidth: true; Layout.topMargin: Theme.spacingSmall
                            Text { text: qsTr("Name"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
                            TextField { Layout.preferredWidth: 280; text: screen.editUserName; onTextEdited: screen.editUserName = text; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall
                                background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 } }
                        }

                        Text { text: qsTr("Account"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                        PolicyToggle { label: qsTr("Allow this user to manage the server"); flag: "IsAdministrator" }
                        PolicyToggle { label: qsTr("Allow collection management"); flag: "EnableCollectionManagement" }
                        PolicyToggle { label: qsTr("Allow subtitle management"); flag: "EnableSubtitleManagement" }

                        Text { text: qsTr("Feature access"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                        PolicyToggle { label: qsTr("Allow browsing Live TV"); flag: "EnableLiveTvAccess" }
                        PolicyToggle { label: qsTr("Allow Live TV recording management"); flag: "EnableLiveTvManagement" }

                        Text { text: qsTr("Playback"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                        PolicyToggle { label: qsTr("Allow media playback"); flag: "EnableMediaPlayback" }
                        PolicyToggle { label: qsTr("Allow audio playback that requires transcoding"); flag: "EnableAudioPlaybackTranscoding" }
                        PolicyToggle { label: qsTr("Allow video playback that requires transcoding"); flag: "EnableVideoPlaybackTranscoding" }
                        PolicyToggle { label: qsTr("Allow video playback that requires conversion without re-encoding"); flag: "EnablePlaybackRemuxing" }
                        PolicyToggle { label: qsTr("Force remote media to be converted"); flag: "ForceRemoteSourceTranscoding" }
                        PolicyNumber { label: qsTr("Remote client bitrate limit (Mbps, 0 = none)"); flag: "RemoteClientBitrateLimit"; scale: 1000000 }
                        PolicySelect { label: qsTr("SyncPlay access"); flag: "SyncPlayAccess"; options: screen.syncPlayOptions }

                        Text { text: qsTr("Permissions"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                        PolicyToggle { label: qsTr("Allow remote connections to this server"); flag: "EnableRemoteAccess" }
                        PolicyToggle { label: qsTr("Allow content downloading"); flag: "EnableContentDownloading" }
                        PolicyToggle { label: qsTr("Allow media deletion from all libraries"); flag: "EnableContentDeletion" }
                        PolicyToggle { label: qsTr("Allow this user to remote-control other users"); flag: "EnableRemoteControlOfOtherUsers" }
                        PolicyToggle { label: qsTr("Allow remote control of shared devices"); flag: "EnableSharedDeviceControl" }

                        Text { text: qsTr("Library access"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                        PolicyToggle { label: qsTr("Enable access to all libraries"); flag: "EnableAllFolders" }
                        AccessCheckList { visible: screen.editPolicy.EnableAllFolders !== true; items: screen.mediaFoldersData; listKey: "EnabledFolders" }

                        Text { visible: screen.channelsData.length > 0; text: qsTr("Channel access"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                        PolicyToggle { visible: screen.channelsData.length > 0; label: qsTr("Enable access to all channels"); flag: "EnableAllChannels" }
                        AccessCheckList { visible: screen.channelsData.length > 0 && screen.editPolicy.EnableAllChannels !== true; items: screen.channelsData; listKey: "EnabledChannels" }

                        Text { visible: screen.editPolicy.IsAdministrator !== true; text: qsTr("Device access"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                        PolicyToggle { visible: screen.editPolicy.IsAdministrator !== true; label: qsTr("Enable access from all devices"); flag: "EnableAllDevices" }
                        AccessCheckList { visible: screen.editPolicy.IsAdministrator !== true && screen.editPolicy.EnableAllDevices !== true; items: screen.devicesData; listKey: "EnabledDevices" }

                        Text { text: qsTr("Account status"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                        PolicyToggle { label: qsTr("Disable this user"); flag: "IsDisabled" }
                        PolicyToggle { label: qsTr("Hide this user from the login screen"); flag: "IsHidden" }
                        PolicyNumber { label: qsTr("Login attempts before lockout (-1 default, 0 never)"); flag: "LoginAttemptsBeforeLockout" }
                        PolicyNumber { label: qsTr("Maximum active sessions (0 = unlimited)"); flag: "MaxActiveSessions" }

                        Text { text: qsTr("Parental control"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                        PolicySelect { label: qsTr("Maximum allowed parental rating"); options: screen.parentalOptions; currentValue: screen.parentalSelectedIndex(); onChanged: (v) => screen.setMaxParental(v) }
                        Text { text: qsTr("Content with a higher rating will be hidden from this user."); color: Theme.textSecondary; font.pixelSize: Theme.fontTiny; Layout.leftMargin: 4; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        Text { text: qsTr("Block items with no or unrecognized rating"); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; Layout.topMargin: Theme.spacingSmall; Layout.leftMargin: 4 }
                        AccessCheckList { items: screen.unratedTypes; listKey: "BlockUnratedItems" }
                        Text { text: qsTr("Allow items with tags"); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; Layout.topMargin: Theme.spacingSmall; Layout.leftMargin: 4 }
                        TagEditor { flag: "AllowedTags" }
                        Text { text: qsTr("Block items with tags"); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; Layout.topMargin: Theme.spacingSmall; Layout.leftMargin: 4 }
                        TagEditor { flag: "BlockedTags" }

                        Text { visible: screen.editPolicy.IsAdministrator !== true; text: qsTr("Access schedules"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                        ColumnLayout {
                            visible: screen.editPolicy.IsAdministrator !== true
                            Layout.fillWidth: true; spacing: 2
                            Repeater {
                                model: screen.editPolicy.AccessSchedules || []
                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true; implicitHeight: 34; radius: Theme.radius; color: Theme.surface
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: Theme.spacingSmall; anchors.rightMargin: Theme.spacingSmall; spacing: Theme.spacingSmall
                                        Text { text: ("" + modelData.DayOfWeek) + "   " + modelData.StartHour + ":00 – " + modelData.EndHour + ":00"; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true }
                                        DashButton { text: qsTr("Remove"); danger: true; onClicked: screen.removeSchedule(index) }
                                    }
                                }
                            }
                            PolicySelect { label: qsTr("Day"); options: screen.dayOptions; currentValue: screen.schedDay; onChanged: (v) => screen.schedDay = v }
                            RowLayout {
                                Layout.fillWidth: true; spacing: Theme.spacingSmall
                                Text { text: qsTr("From / to (hour)"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
                                TextField { Layout.preferredWidth: 60; text: "" + screen.schedStart; inputMethodHints: Qt.ImhDigitsOnly; onEditingFinished: screen.schedStart = Math.max(0, Math.min(24, parseInt(text) || 0)); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall
                                    background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 } }
                                TextField { Layout.preferredWidth: 60; text: "" + screen.schedEnd; inputMethodHints: Qt.ImhDigitsOnly; onEditingFinished: screen.schedEnd = Math.max(0, Math.min(24, parseInt(text) || 0)); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall
                                    background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 } }
                                DashButton { text: qsTr("Add schedule"); onClicked: screen.addSchedule() }
                            }
                        }

                        Text { text: qsTr("Password"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("New password"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
                            TextField { id: newPwField; Layout.preferredWidth: 220; echoMode: TextInput.Password; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall
                                background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 } }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("Confirm password"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4; verticalAlignment: Text.AlignVCenter }
                            TextField { id: confirmPwField; Layout.preferredWidth: 220; echoMode: TextInput.Password; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall
                                background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 } }
                        }
                        RowLayout {
                            Layout.fillWidth: true; Layout.topMargin: Theme.spacingSmall; spacing: Theme.spacingSmall
                            Text { id: pwMsg; text: ""; color: Theme.error; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; verticalAlignment: Text.AlignVCenter }
                            DashButton { text: qsTr("Set password"); onClicked: { pwMsg.text = ""; if (newPwField.text !== confirmPwField.text) { pwMsg.text = qsTr("Passwords don't match.") } else screen.confirm(qsTr("Set a new password for “%1”?").arg(screen.selectedUser.Name), function() { screen.client.setUserPassword(screen.selectedUser.Id, newPwField.text, false); newPwField.text = ""; confirmPwField.text = "" }) } }
                            DashButton { text: qsTr("Clear password"); danger: true; onClicked: screen.confirm(qsTr("Clear the password for “%1”? They will then sign in with no password.").arg(screen.selectedUser.Name), function() { screen.client.setUserPassword(screen.selectedUser.Id, "", true) }) }
                        }

                        RowLayout {
                            Layout.topMargin: Theme.spacing; spacing: Theme.spacingSmall
                            DashButton { text: qsTr("Save changes"); onClicked: screen.confirm(qsTr("Save changes for “%1”?").arg(screen.selectedUser.Name), function() { screen.saveUser() }) }
                            DashButton { text: qsTr("Delete user"); danger: true; onClicked: screen.confirm(qsTr("Delete the user “%1”? This cannot be undone.").arg(screen.selectedUser.Name), function() { screen.client.deleteUser(screen.selectedUser.Id); screen.selectedUser = null; screen.usersReloadTimer.restart() }) }
                        }
                    }
                }

                // config — data-driven server config editor; edits a deep copy, Save POSTs the whole object to selEntry.ep
                ColumnLayout {
                    visible: screen.selEntry.kind === "config"
                    Layout.fillWidth: true; spacing: Theme.spacingSmall
                    Text { visible: screen.serverConfig === null; text: qsTr("Loading…"); color: Theme.textSecondary; font.pixelSize: Theme.fontNormal }
                    ConfigFieldList { fields: (screen.serverConfig !== null && screen.selEntry.fields) ? screen.selEntry.fields : [] }
                    RowLayout {
                        visible: screen.serverConfig !== null
                        Layout.topMargin: Theme.spacing
                        DashButton { text: qsTr("Save changes"); onClicked: screen.confirm(qsTr("Save these server settings?"), function() { screen.client.postJson(screen.selEntry.ep, screen.editConfig) }) }
                    }
                }

                // libraries — virtual-folder CRUD (list / add / per-library detail)
                ColumnLayout {
                    visible: screen.selEntry.kind === "libraries"
                    Layout.fillWidth: true; spacing: Theme.spacingSmall

                    // list
                    ColumnLayout {
                        visible: screen.selectedLib === null && !screen.addMode
                        Layout.fillWidth: true; spacing: Theme.spacingSmall
                        DashButton { text: qsTr("＋  Add media library"); onClicked: { screen.newLibName = ""; screen.newLibType = "movies"; screen.newLibPath = ""; screen.addMode = true } }
                        Repeater {
                            model: screen.librariesData
                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true; implicitHeight: 56; radius: Theme.radius; color: Theme.surface
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: Theme.spacing; anchors.rightMargin: Theme.spacing; spacing: Theme.spacing
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 2
                                        Text { text: ("" + (modelData.Name || "—")); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal }
                                        Text { text: ("" + (modelData.CollectionType || qsTr("mixed"))) + "  ·  " + qsTr("%1 folder(s)").arg((modelData.Locations || []).length); color: Theme.textSecondary; font.pixelSize: Theme.fontTiny }
                                    }
                                    DashButton { text: qsTr("Manage"); onClicked: screen.selectLib(modelData) }
                                    DashButton { text: qsTr("Delete"); danger: true; onClicked: screen.confirm(qsTr("Delete the library “%1”? (Your media files are not deleted.)").arg(modelData.Name), function () { screen.client.removeVirtualFolder(modelData.Name); screen.libReloadTimer.restart() }) }
                                }
                            }
                        }
                        Text { visible: screen.librariesData.length === 0; text: qsTr("No libraries yet."); color: Theme.textSecondary; font.pixelSize: Theme.fontNormal }
                    }

                    // add library
                    ColumnLayout {
                        visible: screen.addMode
                        Layout.fillWidth: true; spacing: Theme.spacingSmall
                        RowLayout {
                            Layout.fillWidth: true
                            DashButton { text: qsTr("← Back"); onClicked: screen.addMode = false }
                            Text { text: qsTr("Add media library"); color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true; Layout.fillWidth: true; leftPadding: Theme.spacing; verticalAlignment: Text.AlignVCenter }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("Content type"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4 }
                            ComboBox {
                                id: typeCombo
                                Layout.preferredWidth: 340; implicitHeight: 34
                                model: screen.contentTypes; textRole: "text"
                                Component.onCompleted: { for (var i = 0; i < screen.contentTypes.length; i++) if (screen.contentTypes[i].value === screen.newLibType) { currentIndex = i; break } }
                                onActivated: (idx) => screen.newLibType = screen.contentTypes[idx].value
                                background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: typeCombo.activeFocus || typeCombo.hovered ? Theme.accent : Theme.divider; border.width: 1 }
                                contentItem: Text { text: typeCombo.displayText; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; leftPadding: 10; rightPadding: 26; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                indicator: Text { x: typeCombo.width - width - 10; y: (typeCombo.height - height) / 2; text: "▾"; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall }
                                popup: Popup {
                                    y: typeCombo.height + 2; width: typeCombo.width; implicitHeight: Math.min(tcl.contentHeight + 2, 300); padding: 1
                                    background: Rectangle { color: Theme.elevated; radius: Theme.radius; border.color: Theme.divider; border.width: 1 }
                                    contentItem: ListView { id: tcl; clip: true; model: typeCombo.popup.visible ? typeCombo.delegateModel : null; currentIndex: typeCombo.highlightedIndex; ScrollBar.vertical: ScrollBar {} }
                                }
                                delegate: ItemDelegate {
                                    required property var modelData
                                    required property int index
                                    width: typeCombo.width; implicitHeight: 32; hoverEnabled: true
                                    contentItem: Text { text: modelData.text; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; leftPadding: 10; verticalAlignment: Text.AlignVCenter }
                                    background: Rectangle { color: hovered ? Theme.surfaceHover : "transparent" }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("Display name"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4 }
                            TextField { Layout.preferredWidth: 340; text: screen.newLibName; onTextEdited: screen.newLibName = text; placeholderText: qsTr("e.g. Movies"); color: Theme.textPrimary; placeholderTextColor: Theme.textDisabled; font.pixelSize: Theme.fontSmall
                                background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 } }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: qsTr("Folder"); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; Layout.leftMargin: 4 }
                            TextField { Layout.preferredWidth: 340; readOnly: true; text: screen.newLibPath; placeholderText: qsTr("(none selected)"); color: Theme.textPrimary; placeholderTextColor: Theme.textDisabled; font.pixelSize: Theme.fontSmall
                                background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: Theme.divider; border.width: 1; implicitHeight: 34 } }
                            DashButton { text: qsTr("Browse…"); onClicked: screen.pickNewLibFolder() }
                        }
                        RowLayout {
                            Layout.topMargin: Theme.spacing
                            DashButton {
                                text: qsTr("Create library")
                                onClicked: screen.confirm(qsTr("Create the “%1” library?").arg(screen.newLibName || qsTr("(unnamed)")),
                                    function () { screen.client.addVirtualFolder(screen.newLibName, screen.newLibType === "mixed" ? "" : screen.newLibType, screen.newLibPath); screen.addMode = false; screen.libReloadTimer.restart() })
                            }
                        }
                    }

                    // per-library detail
                    ColumnLayout {
                        visible: screen.selectedLib !== null
                        Layout.fillWidth: true; spacing: Theme.spacingSmall
                        RowLayout {
                            Layout.fillWidth: true
                            DashButton { text: qsTr("← Back"); onClicked: screen.selectedLib = null }
                            Text { text: screen.selectedLib ? screen.selectedLib.Name : ""; color: Theme.textPrimary; font.pixelSize: Theme.fontMedium; font.bold: true; Layout.fillWidth: true; leftPadding: Theme.spacing; verticalAlignment: Text.AlignVCenter }
                        }
                        Text { text: qsTr("Rename"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingSmall }
                        RowLayout {
                            Layout.fillWidth: true
                            TextField { Layout.preferredWidth: 340; text: screen.renameValue; onTextEdited: screen.renameValue = text; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall
                                background: Rectangle { color: Theme.surface; radius: Theme.radius; border.color: parent.activeFocus ? Theme.accent : Theme.divider; border.width: 1; implicitHeight: 34 } }
                            DashButton { text: qsTr("Rename"); onClicked: screen.confirm(qsTr("Rename “%1” to “%2”?").arg(screen.selectedLib.Name).arg(screen.renameValue),
                                function () { screen.client.renameVirtualFolder(screen.selectedLib.Name, screen.renameValue); screen.selectedLib = null; screen.libReloadTimer.restart() }) }
                        }
                        Text { text: qsTr("Folders"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacing }
                        Repeater {
                            model: screen.selectedLib ? (screen.selectedLib.Locations || []) : []
                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true; implicitHeight: 40; radius: Theme.radius; color: Theme.surface
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: Theme.spacing; anchors.rightMargin: Theme.spacing; spacing: Theme.spacing
                                    Text { text: ("" + modelData); color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; elide: Text.ElideMiddle }
                                    DashButton { text: qsTr("Remove"); danger: true; onClicked: screen.confirm(qsTr("Remove folder “%1” from “%2”?").arg("" + modelData).arg(screen.selectedLib.Name),
                                        function () { screen.client.removeMediaPath(screen.selectedLib.Name, "" + modelData); screen.libReloadTimer.restart() }) }
                                }
                            }
                        }
                        RowLayout {
                            Layout.topMargin: Theme.spacingSmall; spacing: Theme.spacingSmall
                            DashButton { text: qsTr("Add folder"); onClicked: screen.pickAddPathFolder() }
                            DashButton { text: qsTr("Scan / refresh metadata"); onClicked: screen.confirm(qsTr("Refresh metadata for the “%1” library now?").arg(screen.selectedLib.Name), function () { screen.client.refreshItem(screen.selectedLib.ItemId) }) }
                        }

                        Text { text: qsTr("Library options"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingLarge }
                        ConfigFieldList { fields: screen.libraryOptionsFields }

                        // --- provider tables (from GET /Libraries/AvailableOptions) ---
                        Text {
                            visible: !!screen.availOpts
                            text: qsTr("Metadata & image providers"); color: Theme.accent; font.pixelSize: Theme.fontSmall; font.bold: true; Layout.topMargin: Theme.spacingLarge
                        }
                        PluginTable {
                            title: qsTr("Metadata savers"); showOrder: false
                            help: qsTr("Pick the file formats to use when saving your metadata.")
                            rows: screen.provState.metadataSavers || []
                            onToggled: (i) => screen.provToggle("metadataSavers", -1, i)
                        }
                        PluginTable {
                            title: qsTr("Metadata readers"); showCheck: false
                            help: qsTr("Rank your preferred local metadata sources in order of priority. The first file found will be read.")
                            rows: screen.provState.metadataReaders || []
                            onMovedUp: (i) => screen.provMoveReader(i, -1)
                            onMovedDown: (i) => screen.provMoveReader(i, 1)
                        }
                        Repeater {
                            model: screen.provState.metadataFetchers || []
                            PluginTable {
                                required property var modelData
                                required property int index
                                title: qsTr("Metadata downloaders (%1)").arg(modelData.plural)
                                help: qsTr("Enable and rank your preferred metadata downloaders in order of priority. Lower priority downloaders will only be used to fill in missing information.")
                                rows: modelData.plugins
                                onToggled: (i) => screen.provToggle("metadataFetchers", index, i)
                                onMovedUp: (i) => screen.provMove("metadataFetchers", index, i, -1)
                                onMovedDown: (i) => screen.provMove("metadataFetchers", index, i, 1)
                            }
                        }
                        Repeater {
                            model: screen.provState.imageFetchers || []
                            PluginTable {
                                required property var modelData
                                required property int index
                                title: qsTr("Image fetchers (%1)").arg(modelData.plural)
                                help: qsTr("Enable and rank your preferred image fetchers in order of priority.")
                                rows: modelData.plugins
                                showFetcherSettings: modelData.supportedImageTypes && (modelData.supportedImageTypes.length > 1 || (modelData.supportedImageTypes.length === 1 && modelData.supportedImageTypes[0] !== "Primary"))
                                onToggled: (i) => screen.provToggle("imageFetchers", index, i)
                                onMovedUp: (i) => screen.provMove("imageFetchers", index, i, -1)
                                onMovedDown: (i) => screen.provMove("imageFetchers", index, i, 1)
                                onFetcherSettings: screen.openFetcherSettings(index)
                            }
                        }
                        PluginTable {
                            title: qsTr("Subtitle download languages"); showOrder: false
                            rows: screen.provState.subtitleLanguages || []
                            onToggled: (i) => screen.provToggleLang(i)
                        }
                        PluginTable {
                            title: qsTr("Subtitle downloaders")
                            help: qsTr("Enable and rank your preferred subtitle downloaders in order of priority.")
                            rows: screen.provState.subtitleFetchers || []
                            onToggled: (i) => screen.provToggle("subtitleFetchers", -1, i)
                            onMovedUp: (i) => screen.provMove("subtitleFetchers", -1, i, -1)
                            onMovedDown: (i) => screen.provMove("subtitleFetchers", -1, i, 1)
                        }
                        PluginTable {
                            title: qsTr("Lyric downloaders")
                            help: qsTr("Enable and rank your preferred lyric downloaders in order of priority.")
                            rows: screen.provState.lyricFetchers || []
                            onToggled: (i) => screen.provToggle("lyricFetchers", -1, i)
                            onMovedUp: (i) => screen.provMove("lyricFetchers", -1, i, -1)
                            onMovedDown: (i) => screen.provMove("lyricFetchers", -1, i, 1)
                        }
                        PluginTable {
                            title: qsTr("Media segment providers")
                            help: qsTr("Enable and rank your preferred media segment providers in order of priority.")
                            rows: screen.provState.mediaSegmentProviders || []
                            onToggled: (i) => screen.provToggle("mediaSegmentProviders", -1, i)
                            onMovedUp: (i) => screen.provMove("mediaSegmentProviders", -1, i, -1)
                            onMovedDown: (i) => screen.provMove("mediaSegmentProviders", -1, i, 1)
                        }
                        Repeater {
                            model: screen.provState.similarItemProviders || []
                            PluginTable {
                                required property var modelData
                                required property int index
                                title: qsTr("Similar item providers (%1)").arg(modelData.plural)
                                help: qsTr("Enable and rank your preferred similar item providers in order of priority.")
                                rows: modelData.plugins
                                onToggled: (i) => screen.provToggle("similarItemProviders", index, i)
                                onMovedUp: (i) => screen.provMove("similarItemProviders", index, i, -1)
                                onMovedDown: (i) => screen.provMove("similarItemProviders", index, i, 1)
                            }
                        }

                        RowLayout {
                            Layout.topMargin: Theme.spacing
                            DashButton { text: qsTr("Save library options"); onClicked: screen.confirm(qsTr("Save library options for “%1”?").arg(screen.selectedLib.Name), function () { var opts = JSON.parse(JSON.stringify(screen.editConfig)); screen.serializeProviders(opts); screen.client.updateLibraryOptions(screen.selectedLib.ItemId, opts) }) }
                        }

                        RowLayout {
                            Layout.topMargin: Theme.spacingLarge
                            DashButton { text: qsTr("Delete library"); danger: true; onClicked: screen.confirm(qsTr("Delete the library “%1”? (Your media files are not deleted.)").arg(screen.selectedLib.Name),
                                function () { screen.client.removeVirtualFolder(screen.selectedLib.Name); screen.selectedLib = null; screen.libReloadTimer.restart() }) }
                        }
                    }
                }

                // stub
                Text {
                    visible: screen.selEntry.kind === "stub"
                    text: qsTr("This panel isn't built natively yet — manage it in the web dashboard for now.")
                    color: Theme.textSecondary; font.pixelSize: Theme.fontNormal; wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                // info (key/value)
                Text {
                    visible: screen.selEntry.kind !== "stub" && screen.selEntry.kind !== "dashboard" && screen.selEntry.kind !== "tasks" && screen.selEntry.kind !== "users" && screen.selEntry.kind !== "config" && screen.selEntry.kind !== "libraries" && screen.panelData === null
                    text: qsTr("Loading…")
                    color: Theme.textSecondary; font.pixelSize: Theme.fontNormal
                }
                Repeater {
                    model: screen.selEntry.kind === "info" ? screen.infoRows(screen.panelData) : []
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Text { text: modelData.k; color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; Layout.preferredWidth: 260; elide: Text.ElideRight }
                        Text { text: modelData.v; color: Theme.textPrimary; font.pixelSize: Theme.fontSmall; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    }
                }

                // list (rows) — 2-line, formatted per panel; action-capable panels get row buttons + a toolbar
                RowLayout {
                    visible: screen.selEntry.kind === "list" && screen.selEntry.fmt === "apikeys" && screen.logName === ""
                    Layout.fillWidth: true
                    DashButton { text: qsTr("＋  New API key"); onClicked: screen.promptInput(qsTr("New API key"), qsTr("App name"), "", function (name) { if (name && name.length) { screen.client.createApiKey(name); screen.panelReloadTimer.restart() } }) }
                }
                Repeater {
                    model: (screen.selEntry.kind === "list" && screen.logName === "") ? screen.listRows(screen.panelData) : []
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true; implicitHeight: 52; radius: Theme.radius; color: Theme.surface
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: Theme.spacing; anchors.rightMargin: Theme.spacing; spacing: Theme.spacingSmall
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Text { text: screen.listTitle(screen.selEntry, modelData); color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { text: screen.listSub(screen.selEntry, modelData); visible: text.length > 0; color: Theme.textSecondary; font.pixelSize: Theme.fontTiny; Layout.fillWidth: true; elide: Text.ElideRight }
                            }
                            DashButton { visible: screen.selEntry.fmt === "logs"; text: qsTr("View"); onClicked: { screen.logName = ("" + modelData.Name); screen.logContent = qsTr("Loading…"); screen.client.getText("/System/Logs/Log?name=" + encodeURIComponent(modelData.Name), "admin:logfile") } }
                            DashButton { visible: screen.selEntry.fmt === "devices"; text: qsTr("Rename"); onClicked: screen.promptInput(qsTr("Rename device"), qsTr("Custom name"), ("" + (modelData.CustomName || modelData.Name || "")), function (n) { screen.client.renameDevice(modelData.Id, n); screen.panelReloadTimer.restart() }) }
                            DashButton { visible: screen.selEntry.fmt === "devices"; text: qsTr("Delete"); danger: true; onClicked: screen.confirm(qsTr("Delete the device “%1”?").arg(("" + (modelData.CustomName || modelData.Name))), function () { screen.client.deleteDevice(modelData.Id); screen.panelReloadTimer.restart() }) }
                            DashButton { visible: screen.selEntry.fmt === "apikeys"; text: qsTr("Revoke"); danger: true; onClicked: screen.confirm(qsTr("Revoke this API key (%1)?").arg(("" + (modelData.AppName || ""))), function () { screen.client.revokeApiKey(modelData.AccessToken); screen.panelReloadTimer.restart() }) }
                            DashButton { visible: screen.selEntry.fmt === "plugins"; text: (("" + modelData.Status) === "Disabled") ? qsTr("Enable") : qsTr("Disable"); onClicked: screen.confirm(qsTr("%1 the plugin “%2”?").arg((("" + modelData.Status) === "Disabled") ? qsTr("Enable") : qsTr("Disable")).arg(("" + modelData.Name)), function () { screen.client.setPluginEnabled(modelData.Id, ("" + modelData.Version), (("" + modelData.Status) === "Disabled")); screen.panelReloadTimer.restart() }) }
                            DashButton { visible: screen.selEntry.fmt === "plugins"; text: qsTr("Uninstall"); danger: true; onClicked: screen.confirm(qsTr("Uninstall the plugin “%1”?").arg(("" + modelData.Name)), function () { screen.client.uninstallPlugin(modelData.Id, ("" + modelData.Version)); screen.panelReloadTimer.restart() }) }
                        }
                    }
                }
                Text {
                    visible: screen.selEntry.kind === "list" && screen.logName === "" && screen.panelData !== null && screen.listRows(screen.panelData).length === 0
                    text: qsTr("Nothing here.")
                    color: Theme.textSecondary; font.pixelSize: Theme.fontNormal
                }

                // --- log file viewer (Logs panel → View) ---
                ColumnLayout {
                    visible: screen.logName !== ""
                    Layout.fillWidth: true; spacing: Theme.spacingSmall
                    RowLayout {
                        Layout.fillWidth: true
                        DashButton { text: qsTr("← Back"); onClicked: { screen.logName = ""; screen.logContent = "" } }
                        Text { text: screen.logName; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true; Layout.fillWidth: true; leftPadding: Theme.spacing; verticalAlignment: Text.AlignVCenter; elide: Text.ElideMiddle }
                        DashButton { text: qsTr("Copy"); onClicked: { logView.selectAll(); logView.copy(); logView.deselect() } }
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 520; radius: Theme.radius; color: Theme.background; border.color: Theme.divider; border.width: 1
                        Flickable {
                            anchors.fill: parent; anchors.margins: Theme.spacingSmall; clip: true
                            contentWidth: logView.paintedWidth; contentHeight: logView.paintedHeight
                            ScrollBar.vertical: ScrollBar {}
                            ScrollBar.horizontal: ScrollBar {}
                            TextEdit { id: logView; text: screen.logContent; readOnly: true; selectByMouse: true; color: Theme.textPrimary; font.family: "monospace"; font.pixelSize: Theme.fontTiny; wrapMode: TextEdit.NoWrap }
                        }
                    }
                }
            }
        }
    }
}
