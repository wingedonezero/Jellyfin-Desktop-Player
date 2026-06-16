# jellyfin-web Parity Checklist

The **jellyfin-web desktop UI is our foundation**: the goal is 1:1 with it as the default
("jf-web dark") skin. This document is the master audit — every user setting, admin page,
and feature surface jellyfin-web exposes, cross-referenced against **Fladder** (a native
Flutter+libmpv Jellyfin client — proof of what's reachable from a non-web client) and
against **what we have today**.

Built by reading the cloned sources directly:
`../jellyfin-reference/jellyfin-web/` and `../jellyfin-reference/Fladder/`.

## Legend

**Ours** — `✅` wired & functional · `🟡` rendered but stub/disabled/partial · `❌` absent
**Fladder** — `✓` implements it · `✗` deliberately omits · `+` does it *beyond* web · `—` n/a

Out of scope (server has only Movies + TV; user uses Navidrome): **(MUSIC)**, **(LIVETV)**.
Genuine engine limits, render disabled not hidden: **Cast**, **SyncPlay**.

---

## 0. Scoreboard

| Surface | Web items | Ours ✅ | Ours 🟡 | Ours ❌ |
|---|---|---|---|---|
| User Settings | ~80 fields across 7 pages | ~12 | ~12 | ~55 |
| Admin Dashboard | ~20 pages, full CRUD | 0 CRUD | 8 read-only panels | rest |
| Item Detail | ~15 actions + ~25 sections | ~14 | 3 | ~10 |
| Context menu | ~25 commands | 4 | ~8 | ~12 |
| Library views | modes + 11 sorts + ~20 filters | 5 sorts + 2 filters | sort-order | rest |
| Home | 10 configurable sections | 4 (fixed) | — | ordering model |
| Search | grouped by ~10 types | — | — | flat, 3 types only |
| Player OSD | ~30 controls | ~22 | chapter-ticks | ~7 |
| Keyboard shortcuts | full player set | 0 | display-only rows | all |

**Biggest gaps:** admin CRUD (whole subsystem), user-settings depth (subtitles/playback/display),
search grouping, player chapter/segment/trickplay, keyboard shortcuts.

---

## 1. User Settings

jellyfin-web stores most of these **client-local** (browser localStorage); a specific subset
is **server-side** (`user.Configuration.*` or DisplayPreferences). We store client-local in
QSettings via `AppConfig`; server-side needs new `JellyfinClient` calls. Marked `[srv]` = server.

### 1.1 Profile / Account
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Profile image upload / delete | ✗ | ❌ | `POST/DELETE /Users/{id}/Images/Primary` |
| Display name (read-only) | ✓ | ✅ | shown |
| Change password (current/new/confirm) | ✓ | ✅ | `POST /Users/{id}/Password` |
| Reset password (clear, non-admin) | ✗ | ❌ | minor |
| Server URL display | — | ✅ | ours-extra |

### 1.2 Display (all client-local in web)
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Display language | ✓ | 🟡 | UI locale; ours stub |
| Date/time locale | ✗ | ❌ | |
| Layout mode (Auto/Desktop/Mobile/TV) | + | ❌ | |
| Theme picker | + | 🟡 | ours hardcoded jf-dark; Light is stub |
| Disable server custom CSS | ✗ | ❌ | |
| Custom CSS (local) | ✗ | ❌ | |
| Dashboard theme (admin) | ✗ | ❌ | |
| Screensaver + delay / intervals | + | ❌ | |
| Faster animations / fast fade | ✗ | ❌ | |
| BlurHash placeholders | ✓ | ❌ | |
| Library page size | ✓ | ❌ | |
| Backdrops | ✓ | 🟡 | stub toggle |
| Theme songs / theme videos | ✗ | ❌ | |
| Display missing episodes `[srv]` | ✓ | ❌ | `Configuration.DisplayMissingEpisodes` |
| Max days for Next Up | ✓ | ❌ | |
| Enable rewatching in Next Up | ✗ | ❌ | |
| Use episode images in Next Up/Resume `[srv]` | ✓ | ❌ | |
| Enable details banner | ✗ | ❌ | |

> Note: our "Enable cinema mode" lives under Display but in web it's a **Playback** setting (§1.4).

### 1.3 Home
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| 10 ordered home-section slots `[srv]` | + | 🟡 | web: per-slot dropdown (MyMedia/Resume/NextUp/Latest/…). Ours: 3 on/off toggles only |
| Continue Watching / Next Up / Latest toggles | ✓ | ✅ | ours = client on/off |
| Hide watched from Latest `[srv]` | ✓ | ❌ | `Configuration.HidePlayedInLatest` |
| Library display order `[srv]` | ✓ | ❌ | `Configuration.OrderedViews` |
| "Display in My Media" excludes `[srv]` | ✗ | ❌ | `Configuration.MyMediaExcludes` |
| "Display in other sections" excludes `[srv]` | ✗ | ❌ | `Configuration.LatestItemsExcludes` |
| Per-library landing/default tab `[srv]` | ✗ | ❌ | DisplayPreferences `landing-{id}` |
| Grouped folders `[srv]` | ✗ | ❌ | `Configuration.GroupedFolders` |
| TV home layout (TV) | + | ❌ | |

### 1.4 Playback
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Default max video quality — home/in-network | + | ✅ | `playback/maxBitrate` |
| Default max video quality — internet (separate) | + | ❌ | web has two; we have one |
| Allowed audio channels | ✗ | ❌ | Auto/Mono/Stereo/5.1/7.1 |
| Audio language preference `[srv]` | ✓ | 🟡 | stub; `Configuration.AudioLanguagePreference` |
| Play default audio track `[srv]` | ✓ | ❌ | `Configuration.PlayDefaultAudioTrack` |
| Max video resolution | ✓ | ❌ | Auto/360p…8K |
| Cinema mode (intros/trailers) | ✗ | 🟡 | stub (mislabeled under Display) |
| Play next episode automatically `[srv]` | ✓ | ✅ | `playback/autoPlayNext` |
| Skip forward / back length `[srv]` | ✓ | ✅ | `playback/skipForward`,`skipBack` |
| Media-segment actions ×5 (Intro/Preview/Recap/Commercial/Outro) | + | ❌ | None/AskToSkip/Skip per type |
| Remember audio selections `[srv]` | ✓ | ❌ | `Configuration.RememberAudioSelections` |
| Remember subtitle selections `[srv]` | ✓ | ❌ | `Configuration.RememberSubtitleSelections` |
| Next-video info overlay `[srv]` | ✓ | ❌ | up-next card toggle |
| Still Watching prompt | ✗ | ❌ | plugin-gated |
| Enable external video players | + | ❌ | |
| Cast receiver id `[srv]` | ✗ | ❌ | Cast (oos) |
| Allow audio passthrough (DTS/TrueHD/Hi10p) | ✗ | 🟡 | stub; web has 3 toggles |
| Prefer fMP4-HLS container | ✗ | ❌ | |
| Preferred transcode video / audio codec | ✗ | ❌ | h264/hevc/av1; aac/ac3/… |
| Audio normalization / remux FLAC / remux MP3 | + | ❌ | (MUSIC-ish) |

### 1.5 Subtitles
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Preferred subtitle language `[srv]` | ✓ | 🟡 | stub; `Configuration.SubtitleLanguagePreference` |
| Subtitle mode (Default/Smart/OnlyForced/Always/None) `[srv]` | ✓ | 🟡 | stub; `Configuration.SubtitleMode` |
| Burn-in mode (Auto/ImageOnly/Complex/All) | ✗ | 🟡 | stub |
| Render PGS | ✗ | ❌ | |
| Always burn in when transcoding | ✗ | ❌ | |
| Subtitle styling mode (Auto/Custom/Native) | + | ❌ | |
| Text size | ✓ | ✅ | `subtitles/scale` → mpv `sub-scale` |
| Text weight (normal/bold) | ✓ | ❌ | mpv `sub-bold` |
| Font family | ✗ | ❌ | mpv `sub-font` |
| Text color | ✓ | ❌ | mpv `sub-color` |
| Text background color | ✓ | ❌ | mpv `sub-back-color` |
| Drop shadow / outline style | ✓ | ❌ | mpv `sub-border-*`,`sub-shadow-*` |
| Vertical position | ✓ | ✅ | `subtitles/pos` → mpv `sub-pos` |

> The whole **Subtitle Appearance** block maps cleanly onto mpv `sub-*` options — we already
> drive two of them. This is high-leverage and fully self-contained.

### 1.6 Controls (keyboard / gamepad)
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Enable gamepad | ✗ | 🟡 | display-only |
| Enable smooth scroll (TV) | ✗ | 🟡 | display-only |
| **Player keyboard shortcuts actually working** | + | ❌ | NONE wired (see §10) |

### 1.7 Quick Connect (user-side authorize)
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Enter code + Authorize | ✓ | 🟡 | stub/disabled; `POST /QuickConnect/Authorize?code=` |

### 1.8 Player — mpv.conf (OURS beyond web)
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Live mpv.conf editor (load/edit/save) | partial | ✅ | web has no mpv; keep this |

---

## 2. Admin Dashboard

Admin entry is gated on `client.isAdmin` (correct — the `Testing` account is **not** admin, so
panels 403; needs the real admin account to runtime-test). Today **AdminScreen** shows 8
read-only GET dumps + 9 bare stubs and **no create/edit/delete anywhere**. jellyfin-web is a
full management app. Fladder proves the whole thing is reachable natively.

Two config endpoints to know: **typed NamedConfiguration** `GET/POST /System/Configuration/{key}`
(keys: `encoding`, `network`, `branding`, `xbmcmetadata`, `metadata`, `livetv`) and the main
**ServerConfiguration** `GET/POST /System/Configuration` (general, resume, streaming, trickplay, logs).

### 2.1 Server → Dashboard  `[/System/Info, /Sessions, /Items/Counts, /System/Storage]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Server info (name/version/web/build) | ✓ | 🟡 | we dump `/System/Info` raw, unformatted |
| Scan all libraries | ✓ | ❌ | start `RefreshLibrary` task |
| Restart / Shutdown | ✓ | ❌ | `POST /System/Restart`,`/System/Shutdown` |
| Item counts widget | ✓ | ❌ | `/Items/Counts` |
| Active devices / sessions (+ playback control) | ✓ | ❌ | `/Sessions` (+playpause/stop/message) |
| Running tasks progress | ✓ | ❌ | websocket `ScheduledTasksInfo` |
| Activity / alerts log | partial | ❌ | |
| Storage paths + usage bars | ✓ | ❌ | `/System/Storage` |

### 2.2 Server → General  `[/System/Configuration]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Server name · UI culture · cache path · metadata path | ✓ | ❌ | whole page STUB |
| Enable Quick Connect | ✓ | ❌ | `QuickConnectAvailable` |
| Library scan fanout concurrency · parallel image encoding limit | ✓ | ❌ | |

### 2.3 Server → Branding  `[/System/Configuration/branding]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Splashscreen enable/upload/delete · login disclaimer · custom CSS | ✗ | ❌ | STUB |

### 2.4 Server → Users  `[/Users, /Users/New, /Users/{id}/Policy]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| User list | ✓ | 🟡 | read-only (Name/Id) |
| Add user (name/pw/library+channel access) | ✓ | ❌ | `POST /Users/New` |
| Delete user | ✓ | ❌ | `DELETE /Users/{id}` |
| **Profile tab** — full UserPolicy matrix | ✓ | ❌ | admin, collection/subtitle mgmt, media playback, audio/video transcoding, remux, force-remote-transcode, remote bitrate limit, SyncPlay access, content deletion, remote control, downloading, disable/hide, login-lockout, max sessions, auth/reset providers |
| **Access tab** — libraries / channels / devices | ✓ | ❌ | `EnabledFolders/Channels/Devices` |
| **Parental tab** — max rating, block unrated types, allowed/blocked tags, access schedules | ✓ | ❌ | |
| **Password tab** — set / reset | ✓ | ❌ | |

### 2.5 Server → Libraries  `[/Library/VirtualFolders, /Library/VirtualFolders/Paths, /LibraryOptions]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Library list | ✓ | ❌ | STUB |
| Add library (content type / name / folders) | ✓ | ❌ | `POST /Library/VirtualFolders` |
| Edit folders (add/edit/remove path) | ✓ | ❌ | |
| Rename / Scan / Remove / Edit images | ✓ | ❌ | |
| **LibraryOptions panel** (huge): enable, preferred language/country, embedded titles, real-time monitor, metadata downloaders+order, savers, image fetchers, refresh interval, similar providers, series grouping, media-segment providers, **trickplay**, **chapter images**, **subtitle downloads** (langs/downloaders/skip rules), photos | ✓ | ❌ | the deepest single page in the app |

### 2.6 Server → Libraries → Display  `[/System/Configuration + /metadata]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Date-added behavior · folder view · specials within seasons · group movies/shows into collections · external content in suggestions | partial | ❌ | STUB |

### 2.7 Server → Libraries → Metadata  `[/System/Configuration]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Preferred language · country · dummy chapter duration · chapter image resolution | ✗ | ❌ | STUB |

### 2.8 Server → Libraries → NFO  `[/System/Configuration/xbmcmetadata]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Kodi user · save image paths · path substitution · extra thumbs dup | ✗ | ❌ | STUB |

### 2.9 Server → Playback → Transcoding  `[/System/Configuration/encoding]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| HW acceleration type (none/amf/nvenc/qsv/vaapi/rkmpp/videotoolbox/v4l2m2m) | ✗ | ❌ | STUB |
| VAAPI/QSV device · HW decoding codecs · color-depth toggles · enhanced NVDEC | ✗ | ❌ | |
| HW encoding + low-power encoders · allow HEVC/AV1 encoding | ✗ | ❌ | |
| Tone-mapping (enable/algorithm/mode/range/desat/peak/param + VPP) | ✗ | ❌ | |
| Thread count · FFmpeg path (RO) · transcode temp path · fallback font | ✗ | ❌ | |
| Audio VBR · downmix boost · stereo downmix algorithm · max muxing queue | ✗ | ❌ | |
| Encoder preset · H264/H265 CRF · deinterlace method + double-rate | ✗ | ❌ | |
| Subtitle extraction · throttling · segment deletion · delays | ✗ | ❌ | |

### 2.10 Server → Playback → Resume  `[/System/Configuration]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Min/max resume % · min/max audiobook resume % · min resume duration | ✗ | ❌ | STUB |

### 2.11 Server → Playback → Streaming  `[/System/Configuration]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Remote client bitrate limit (Mbps) | ✗ | ❌ | STUB |

### 2.12 Server → Playback → Trickplay (server generation)  `[/System/Configuration → TrickplayOptions]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| HW accel/encoding · keyframe-only · scan behavior · priority · interval · width resolutions · tile w/h · jpeg quality · qscale · threads | ✓ | ❌ | STUB |

### 2.13 Devices → Devices  `[/Devices, /Devices/Options]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Device list | ✓ | 🟡 | read-only (Name/LastUserName) |
| Rename (CustomName) · Delete · Delete all | ✓ | ❌ | |

### 2.14 Devices → Activity  `[/System/ActivityLog/Entries]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Activity log table (time/level/user/name/overview/type) + All/User/System filter | partial | 🟡 | read-only flat list (Name/Type), no filters |

### 2.15 Advanced → Networking  `[/System/Configuration/network]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| HTTP/HTTPS ports · enable HTTPS · base URL · bind/LAN addresses · known proxies · require HTTPS · cert path/pw · remote access · IP filter + mode · public ports · IPv4/IPv6 · autodiscovery · published URI | ✗ | ❌ | STUB |

### 2.16 Advanced → API Keys  `[/Auth/Keys]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Key list | ✗ | 🟡 | read-only (AppName/DateCreated) |
| Create (app name) · Revoke | ✗ | ❌ | `POST/DELETE /Auth/Keys` |

### 2.17 Advanced → Backups  `[/Backups]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| List · create (database/metadata/subtitles/trickplay) · restore · info | ✗ | ❌ | STUB |

### 2.18 Advanced → Logs  `[/System/Logs, /System/Logs/Log]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Log file list | ✗ | 🟡 | read-only (Name/Size) |
| Viewer (copy/download/watch) | ✗ | ❌ | `/System/Logs/Log?name=` |
| Log settings (slow-response warning + threshold) | ✗ | ❌ | |

### 2.19 Advanced → Scheduled Tasks  `[/ScheduledTasks]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Task list (grouped by category) | ✓ | 🟡 | read-only (Name/State) |
| Run now / Stop | ✓ | ❌ | `POST/DELETE /ScheduledTasks/Running/{id}` |
| Edit triggers (daily/weekly/interval/startup + time limit) | ✓ | ❌ | `POST /ScheduledTasks/{id}/Triggers` |

### 2.20 Plugins → Plugins  `[/Plugins, /Repositories, /Packages]`
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Installed list | ✗ | 🟡 | read-only (Name/Version) |
| Catalog/available · search · status/category filters | ✗ | ❌ | |
| Detail: revisions/install/enable/disable/uninstall/settings | ✗ | ❌ | |
| Repositories add/remove · per-plugin config pages | ✗ | ❌ | |

### Live TV / DVR — **OUT OF SCOPE** (listed for nav completeness only)
Live TV config, DVR, tuner hosts, guide providers — do not implement.

---

## 3. Item Detail page
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Resume / Play from beginning | ✓ | ✅ | label flips on resume |
| Mark played/unplayed · Favorite | ✓ | ✅ | |
| Add to playlist · Add to collection | ✓ | ✅ | wired here (unlike context menu) |
| External links (IMDb/TMDb) | ✓ | ✅ | |
| Media Info (codecs/res/container/size) | ✓ | ✅ | display |
| Cast & crew · Extras · More-like-this · Seasons/Episodes · Filmography | ✓ | ✅ | |
| Genres · tagline · overview | ✓ | ✅ | |
| Download | + | 🟡 | stub |
| Edit metadata · Refresh metadata | ✓ | 🟡 | stub (refresh has no handler even if flipped) |
| Play Trailer | ✗ | ❌ | |
| Shuffle / Play All | ✓ | ❌ | |
| Split Versions (merge alt versions) | ✗ | ❌ | |
| Track/version SELECT dropdowns (source/video/audio/subtitle pre-play) | ✓ | ❌ | we show info but can't pick |
| Scenes / Chapters thumbnail row | ✓ | ❌ | |
| Tags · details group (director/writer/studio rows) · guest cast · additional parts | partial | ❌ | |

## 4. Item context menu (right-click / "...")
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Play | ✓ | ✅ | |
| Add/remove favorite · Mark played/unplayed | ✓ | ✅ | |
| Copy stream URL | + | ✅ | |
| Add to collection · Add to playlist | ✓ | 🟡 | **BUG: enabled but no handler — dead clicks**; wire to the DetailScreen pickers |
| Download · Delete · Edit metadata/images/subtitles · Identify · Refresh | ✓ | 🟡 | stub |
| Play all from here · Add to queue · Play next | ✓ | ❌ | |
| Shuffle | ✓ | ❌ | |
| Media info | ✓ | ❌ | |
| Remove from playlist/collection · Move to top/bottom | ✓ | ❌ | |
| Select (multi-select mode) · Share | ✓ | ❌ | |
| Instant Mix · View album/artist/lyrics | ✓ | — | (MUSIC) |

## 5. Library views
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| View modes (Primary/Banner/Disc/Logo/Thumb/**List**) + show title/year | + | ❌ | ours poster-only |
| Sort: Name/Community/Date Added/Release/Runtime | ✓ | ✅ | 5 of 11 |
| Sort: Critic/Parental/Play Count/Date Played/Random | + | ❌ | |
| Sort order asc/desc toggle (UI) | ✓ | 🟡 | plumbed, no button (fixed Asc) |
| Filter: Unplayed/Played/Favorite/Resumable | ✓ | ✅ | |
| Filter: Genres · Years · Tags · Studios | ✓ | ❌ | |
| Filter: Video Type (HD/4K/SD/3D/Bluray/DVD) | + | ❌ | |
| Filter: Features (Subtitles/Trailer/Extras/ThemeSong/ThemeVideo) | + | ❌ | |
| Filter: Series Status (Continuing/Ended/Unreleased) | ✓ | ❌ | |
| Alpha picker (A–Z rail) | ✓ | ❌ | |
| Group-by (client-side) + saved filters | + | ❌ | Fladder-only |

## 6. Home screen
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Continue Watching · Next Up · My Media · Latest-per-library | ✓ | ✅ | fixed order |
| Configurable section ordering (10 slots) | + | ❌ | driven by §1.3 |
| Library buttons row · Continue Reading | partial | ❌ | |
| Home banner / hero (Fladder) | + | ❌ | beyond web |

## 7. Search
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| **Grouped by type** (Movies/Shows/Episodes/People/Studios/Collections/Playlists/Books/Videos) | ✓ | ❌ | **ours is a flat grid** |
| Searches People / Collections / Studios | ✓ | ❌ | ours: Movie/Series/Episode only |
| Suggestions view (pre-query) | partial | ❌ | |

## 8. Player OSD
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Title · scrubber · position/duration · ends-at | ✓ | ✅ | |
| Play/pause · prev/next (queue) · rewind/ff (skip) | ✓ | ✅ | |
| Subtitle menu · audio menu · mute+volume · fullscreen | ✓ | ✅ | |
| Favorite · aspect · speed · quality/transcode · repeat · stats overlay | ✓ | ✅ | |
| Subtitle delay · audio delay · subtitle size | ✓ | ✅ | in settings popover |
| Chapter markers on scrubber | ✓ | 🟡 | ticks render, **not clickable to jump** |
| Prev/next **chapter** buttons + chapter menu | ✓ | ❌ | `setChapter` exists, no UI |
| Skip intro/credits (media segments) button | ✓ | ❌ | `/MediaSegments/{id}` |
| Up-next card w/ countdown | ✓ | ❌ | we auto-advance silently |
| Trickplay thumbnail on hover | ✓ | ❌ | `/Trickplay/...` |
| Picture-in-Picture · screenshot | + | ❌ | Fladder-extra |
| Secondary subtitles | ✗ | ❌ | |
| Cast / SyncPlay | ✗ | 🟡 | stub buttons (engine limit) |

## 9. App header / user menu
| Item | Fladder | Ours | Notes |
|---|---|---|---|
| Search · back · home/drawer | ✓ | ✅ | |
| User menu: Profile/Settings/Sign Out | ✓ | ✅ | |
| Dashboard entry (admins) | ✓ | ✅ | gated on isAdmin |
| Quick Connect entry · Select Server | partial | ❌ | single-server for us |
| Cast / SyncPlay header buttons | ✗ | 🟡 | stub (engine limit) |

## 10. Keyboard shortcuts
**None are implemented** — the Controls settings rows are display-only and there is no `Keys`
handler in the player. Web's player set to replicate:
Space/K play-pause · 0–9 seek% · ↑/↓ volume · ←/J rewind · →/L ff · ,/. frame · Shift+,/.
speed · F fullscreen · M mute · Shift+P/N prev/next · PgUp/Dn chapter · Home/End seek 0/100% ·
G/H subtitle offset · Esc hide OSD. (Fladder makes all of these rebindable.)

---

## 11. Fladder extras *beyond* web (optional inspiration, not parity)
Offline sync/downloads · Jellyseerr integration · multi-user switch · player backend choice ·
Material-You theming · PiP · screenshots (normal + clean) · speed-boost hold · per-segment
auto-skip · background new-media notifications · TV/D-pad mode · **local-URL override** (separate
LAN vs remote address) · app lock. Most are out of scope; *local-URL override*, *screenshots*,
and *offline sync* are the plausibly-interesting ones.

---

## 12. Suggested phased build order

Sized so each phase is independently shippable and (where possible) screenshot-verifiable.
Admin (Phase D) needs the real admin account to runtime-test.

- **Phase A — User-settings parity** (self-contained, no admin, mostly mpv/UserConfiguration):
  full Subtitle Appearance (font/size/weight/color/bg/outline/shadow → mpv `sub-*`) + language +
  mode + burn-in; Playback depth (audio language, play-default-audio, max resolution, audio
  channels, cinema mode, remember selections, media-segment actions, transcode codecs, external
  player); Display (real theme picker, language, backdrops, blurhash, page size, details banner);
  Home section-ordering model + library order/excludes/landing; Quick Connect authorize.
  **Also fix the dead MediaCard "add to collection/playlist" handlers.**
- **Phase B — Player OSD completion:** chapter menu + click-to-jump (we already expose
  `setChapter`); skip intro/credits via media segments; up-next countdown card; trickplay hover
  thumbnails; **keyboard shortcuts** (full set) + wire the Controls section.
- **Phase C — Detail / library / search depth:** detail trailer + shuffle + version/audio/sub
  pre-play selectors + scenes row + tags; context-menu queue/play-next/play-all/shuffle/media-
  info/remove-from/share/multi-select; library view modes (List) + full filter dialog + more
  sorts + asc/desc toggle + alpha picker; **group search by type** + add People/Collections.
- **Phase D — Admin CRUD** (the biggest "missed locations"; needs admin account):
  - D1 Dashboard actions: scan/restart/shutdown + counts + sessions + storage.
  - D2 Users CRUD: add/edit (full policy tabs)/delete.
  - D3 Libraries CRUD: add/edit (folders + LibraryOptions) + rename/scan/remove.
  - D4 Server-config editors: General, Networking, Transcoding, Resume, Streaming, Trickplay,
    Branding, Metadata/NFO, Display.
  - D5 Operations: Scheduled Tasks run/stop/triggers; API Keys create/revoke; Logs
    viewer/download + settings; Backups create/restore; Devices rename/delete; Activity filters;
    Plugins catalog/install/manage/repos.

**Out of scope / disabled-not-hidden:** Live TV/DVR, Music-specific rows, Cast, SyncPlay.
