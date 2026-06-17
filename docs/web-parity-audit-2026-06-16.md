# Comprehensive Parity Audit vs jellyfin-web — 2026-06-16

**Method.** 9 parallel read-only audits, each diffing our QML/C++ against the exact
jellyfin-web source (`../jellyfin-reference/jellyfin-web`), with Fladder
(`../jellyfin-reference/Fladder`) and haruna/mpc-qt as native-reachability proofs.
Source-based only — **no server mutations** (the live server was not touched).
Every gap below cites our `file:line` (or "absent") and the web reference, classified:
**[MISSING]** not rendered · **[DEAD]** rendered but unwired · **[PARTIAL]** wired but
incomplete · **[NO-HELP]** wired but missing web's description text.

This supersedes the older `docs/web-parity-checklist.md` (which was stale/incomplete).

---

## Surface scorecard

| Surface | State | Headline gap |
|---|---|---|
| Settings · Profile/About/Player(mpv) | ✅ solid | — |
| Settings · Display | 🔴 **cosmetic** | all 8 prefs persist, **0 consumed**; no help text |
| Settings · Home | 🟡 partial | 6 slots vs 10; missing OrderedViews/per-library/folder-grouping/hide-watched |
| Settings · Playback | 🟡 wired-to-QSetting only | transcode/quality prefs never reach the stream request; ~12 missing help; 5 DEAD media-segment rows |
| Settings · Subtitles | 🟢 mostly (mpv-wired) | per-value help missing; burn-in DEAD; color/font set incomplete |
| Settings · Controls | 🔴 fake | 4 stub rows; **no key handler exists anywhere** |
| Settings · Quick Connect | 🟢 | minor: no min-length/whitespace strip |
| Home screen | 🟡 | only resume(video)/nextup/mymedia/latest; no audio/book resume |
| Library (grid/tabs/filters) | 🟡 | no view modes/alpha/paging; filter dialog 2 of 9 groups; no sort-direction |
| Search | 🔴 | flat grid, not grouped; only queries Movie/Series/Episode |
| Detail · Movie/Series/Person | 🟢 mostly | version selector, chapters, critic/tags, trailer missing |
| Detail · **BoxSet** | 🔴 | **never lists the collection's items** (known gap) |
| Detail · Season (opened directly) | 🔴 | no episode list (same class of bug) |
| Player OSD | 🟡 | no keyboard, no media-segment skip, no up-next card, no trickplay, no chapter menu |
| MediaCard context menu | 🟡 | **Add-to-collection/playlist = DEAD clicks** (known bug) |
| Admin · Dashboard | 🟡 | missing storage/alerts/activity/running-tasks cards; counts incomplete |
| Admin · General/Resume/Streaming/Trickplay | ✅ full parity | — |
| Admin · Metadata/NFO/Branding | 🟡 | control-type + help gaps; branding splashscreen + multiline |
| Admin · Transcoding | 🟡 | codec checkbox group → raw CSV; 4 toggles mis-gated; FFmpeg path; thread select |
| Admin · Networking | 🟡 | **Published Server URI section absent**; one dropdown → toggle |
| Admin · **Libraries / LibraryOptions** | 🔴 | **all 9 provider tables absent** (known gap) |
| Admin · Users | 🔴 | policy toggles only — no add/Access/Parental/Password tabs, ~15 policy fields |
| Admin · Devices/API Keys/Logs/Plugins/Backups | 🔴 | read-only/stub — every action missing |
| Admin · Scheduled Tasks | 🟡 | run/stop work; **triggers editor absent** |
| Admin · Display page | 🔴 | **no nav entry at all** (6 fields) |

---

## TIER 0 — User-flagged known gaps (confirmed + scoped)

### 0.1 LibraryOptions provider tables — **ALL ABSENT**
Our editor is a static scalar-field descriptor list; it **never calls
`GET /Libraries/AvailableOptions?libraryContentType=<type>`**, so it can render
**zero** provider tables. The ~30 scalar toggles/selects ARE present+wired
(`AdminScreen.qml:182-218`). Missing tables (each = server plugin list, checkboxes +
up/down reorder, merged back into the existing `TypeOptions[]` by `Type`):

- **[MISSING] Metadata savers** — `LibraryOptions.MetadataSavers` (names). Desc verbatim:
  *"Pick the file formats to use when saving your metadata."* Shows for **every** type incl. boxsets.
- **[MISSING] Metadata readers (order)** — `LocalMetadataReaderOrder`. Desc:
  *"Rank your preferred local metadata sources in order of priority. The first file found will be read."*
- **[MISSING] Per-type Metadata downloaders (ranked)** — one table per `TypeOptions[].Type`;
  `TypeOptions[T].MetadataFetchers` + `MetadataFetcherOrder`. Desc:
  *"Enable and rank your preferred metadata downloaders in order of priority. Lower priority downloaders will only be used to fill in missing information."*
- **[MISSING] Per-type Image fetchers (ranked) + "Fetcher Settings"** — `TypeOptions[T].ImageFetchers` +
  `ImageFetcherOrder` (+ `ImageOptions` via the per-type Fetcher-Settings dialog). Desc:
  *"Enable and rank your preferred image fetchers in order of priority."*
- **[MISSING] Subtitle download languages** — `SubtitleDownloadLanguages` (3-letter codes), multi-checkbox.
- **[MISSING] Subtitle downloaders (ranked)** — `DisabledSubtitleFetchers` + `SubtitleFetcherOrder` (inverse semantics).
- **[MISSING] Lyric downloaders (music)** — `DisabledLyricFetchers` + `LyricFetcherOrder`.
- **[MISSING] Media segment providers** — `DisabledMediaSegmentProviders` + `MediaSegmentProviderOrder`.
- **[MISSING] Per-type Similar item providers** — `TypeOptions[T].SimilarItemProviders` + `SimilarItemProviderOrder`.
- **[MISSING] `DelimiterWhitelist`** scalar field (music) — `template:247`.
- **[PARTIAL] AutomaticRefreshIntervalDays** — ours free-number; web is a Never/30/60/90 select.

Web ref: `components/libraryoptionseditor/libraryoptionseditor.js` (`renderMetadataSavers`
102-120, `renderMetadataReaders` 63-100, `getMetadataFetchersForTypeHtml` 122-184,
`getImageFetchersForTypeHtml` 286-376, `renderSubtitleFetchers` 186-217, etc.).
**Build needs:** client `getAvailableOptions(contentType,isNew)` + a reusable ranked-checkbox-list
QML component (the descriptor `ConfigFieldList` can't express tables). **Per-type set is
server-decided** (loop over `AvailableOptions.TypeOptions`, don't hard-code); honor each plugin's
`DefaultEnabled` when a library has no saved fetcher list, or first save silently disables providers.
**Even boxsets** get savers + downloaders + image fetchers.

### 0.2 BoxSet (Collection) detail never lists the collection's items
`DetailScreen.qml:111-118` forks only on `isPerson`/`isSeries`; a BoxSet falls to `else` →
only `fetchSimilar` + `fetchSpecialFeatures`. **The items inside are never loaded.**
- **[MISSING]** Fix: add a BoxSet branch calling the **existing** `fetchItems(detail.id, ...)`
  (`JellyfinClient.cpp:373`) — web uses `getItems({ParentId:item.Id})` (`itemDetails/index.js:1307`),
  optionally grouped by type (`renderCollectionItems` 1617-1694). Method exists, just unused.
- **[MISSING] Season opened directly shows no episodes** — same class: DetailScreen only fetches
  episodes when `isSeries`. Fix: when `type==="Season"`, call existing `fetchEpisodes(seriesId, id)`.

### 0.3 Missing descriptions / helper text (widespread)
- Display page: **all 8** toggles/steppers lack web's `*Help` text (strings captured in §Tier-1).
- Playback: ~12 fields lack help (DisableVbrAudio, PreferFmp4Hls, RememberAudio/Subtitle, EnableDts/TrueHd/Hi10p,
  LimitSupportedVideoResolution, PreferredTranscodeVideo/AudioCodec, AudioNormalization).
- Subtitles: per-value help for **mode** (5 strings) and **styling** (3 strings) missing.
- Metadata admin: DummyChapterDuration help + ChapterImageResolution help missing; section headers absent.
- Transcoding admin: 5 helper texts are plain where web uses clickable doc `<a>` links (our help Text already
  supports inline `<a href>` — just add them).
- NFO/Metadata: intro paragraphs + section headers missing.

---

## TIER 1 — Looks-done-but-dead (high "feels broken" value)

### 1.1 Display prefs are entirely write-only (Display page is cosmetic)
8 `display/*` prefs persist; **none are consumed.** Fixes split between `JellyfinClient.cpp`
query builders and QML `visible`/image bindings:
- **[PARTIAL] `display/backdrops`** — `EnableBackdropsHelp`="Display the backdrops in the background of some pages while browsing the library." Saved `SettingsScreen.qml:363`; gate the Detail/page backdrop `visible`.
- **[PARTIAL] `display/detailsBanner`** — "Display a banner image at the top of the item details page." Saved :364; DetailScreen.qml:319-338 always renders.
- **[PARTIAL] `display/fastAnimations`** — "Use faster animations and transitions." Saved :365; durations hardcoded.
- **[PARTIAL] `display/libraryPageSize`** — "Set the amount of items to show on a library page. Setting a value of 0 will disable pagination…" Saved :369; `fetchItems` sends no `Limit`/`StartIndex`; no pager.
- **[PARTIAL] `display/maxDaysNextUp`** — "Set the maximum amount of days a show should stay in the 'Next Up' list…" Saved :373; `fetchNextUp` (cpp:358) omits `NextUpDateCutoff`.
- **[PARTIAL] `display/rewatchingNextUp`** — "Enable showing already watched episodes in 'Next Up' sections." Saved :374; `fetchNextUp` sends no `EnableRewatching=true`.
- **[PARTIAL] `display/episodeImagesNextUp`** — "…use episode images as thumbnails instead of the primary thumbnail of the show." Saved :375; image pick fixed in `MediaCard.qml:34-42`.
- **[PARTIAL] `DisplayMissingEpisodes`** (server cfg) — saved :370; `fetchEpisodes` (cpp:407) never opts in to virtual items.

### 1.2 Keyboard shortcuts — NONE exist (player is mouse-only)
No `Keys`/`Shortcut`/`WheelHandler` anywhere in `src/qml/**`. Web binds ~22 keys
(`controllers/playback/video/index.js:1215-1421`). **Every action maps to an mpv invokable we
already expose** (`setPaused/seek/skip/setVolume/setMuted/setChapter/setSpeed/setSubDelay`) — pure
wiring, zero engine work (only `,`/`.` frame-step needs a new `command(["frame-step"])`). Proof:
haruna drives all of these from `src/qml/Actions.qml`.
Keys: Space/K, J/L/←/→, ↑/↓, M, F, 0-9, Home/End, PageUp/Down, ,/., Shift+P/N, G/H, wheel=volume, dbl-click=fullscreen.

### 1.3 MediaCard right-click Add-to-collection / Add-to-playlist = DEAD clicks
`MediaCard.qml:194-195` render `enabled` but have **no `onTriggered`** → silent dead clicks.
Client `addToCollection`/`createCollection`/`addToPlaylist`/`createPlaylist` all exist.
DetailScreen wires them correctly (`DetailScreen.qml:413-414` + AddToPicker) — copy that.

### 1.4 Search not grouped + only 3 types
`SearchScreen.qml` = one flat poster grid; `JellyfinClient::search` (cpp:430) hits only
`IncludeItemTypes=Movie,Series,Episode`. Web returns **type-grouped sections**
(Movies/Shows/Episodes/People/Studios/Collections/Albums/Artists/Songs/…). Also missing the
pre-query **suggestions** panel. Fladder confirms the "fetch-all-types, group-by-type" design.

### 1.5 Player feature gaps (menus mostly exist; behaviors missing)
- **[MISSING] Media-segment skip (intro/credits)** — 5 settings rows DEAD (`SettingsScreen.qml:439-443`,
  `enabled:false`); player has no segment logic; needs new `fetchMediaSegments(itemId)` → `/MediaSegments/{id}`
  + a transient skip button.
- **[MISSING] Up-next countdown card** — auto-advance already fires silently (`PlayerView.qml:151-156`);
  only the overlay card is missing.
- **[MISSING] Trickplay hover thumbnails** — needs a `Videos/{Id}/Trickplay/{W}/{i}.jpg` URL helper +
  `item.Trickplay` map; flip `Features.trickplay`.
- **[MISSING] Chapter menu / prev-next-chapter buttons / click-to-jump** — we render ticks only;
  `setChapter` invokable exists. Proof: haruna chapter popup.
- **[MISSING] Scrubber buffered ranges** — observe mpv `demuxer-cache-state` (mpc-qt does this).
- **[PARTIAL] OSD title** lacks "Series - SxxExx (Year)" composition (`PlayerControls.qml:202`).

---

## TIER 2 — Admin CRUD / actions (read-only → mutating)

- **[MISSING] Users — add user** (`POST /Users/New`), **Access tab** (library/channel/device
  `EnableAll*`/`Enabled*`), **Parental tab** (`MaxParentalRating` from `/Localization/ParentalRatings`,
  `BlockUnratedItems`, `AllowedTags`/`BlockedTags`, `AccessSchedules`), **Password tab**
  (admin reset → `POST /Users/{id}/Password`), **profile name edit** (`POST /Users/{id}` via new
  `updateUser`), and **~15 missing policy fields** (EnableSubtitleManagement, EnableLiveTvAccess/Management,
  EnablePlaybackRemuxing, ForceRemoteSourceTranscoding, EnableRemoteAccess, EnableSharedDeviceControl,
  RemoteClientBitrateLimit, SyncPlayAccess, LoginAttemptsBeforeLockout, MaxActiveSessions,
  EnableContentDeletionFromFolders, AuthenticationProviderId, PasswordResetProviderId). Current page =
  ~10 policy toggles only (`AdminScreen.qml:843-864`).
- **[MISSING] Devices** rename (`POST /Devices/Options?id=`) + delete (`DELETE /Devices?id=`) + delete-all.
- **[MISSING] API Keys** create (`POST /Auth/Keys?app=`) + revoke (`DELETE /Auth/Keys/{token}`); surface `AccessToken`.
- **[MISSING] Logs** file viewer (`GET /System/Logs/Log?name=` → raw text, copy/download) + slow-response config
  (`EnableSlowResponseWarning`/`SlowResponseThresholdMs`).
- **[MISSING] Plugins** catalog (`GET /Packages`), install (`POST /Packages/Installed/{name}`), uninstall
  (`DELETE /Plugins/{id}/{version}`), enable/disable (`…/Enable|Disable`), per-plugin settings page,
  repositories (`GET/POST /Repositories`).
- **[MISSING] Backups** (currently a stub) — list (`GET /Backups`), create (`POST /Backups`), restore
  (`POST /Backups/Restore`). (No delete/upload in this web build.)
- **[MISSING] Scheduled Tasks triggers editor** — per-task view; add/remove Daily/Weekly/Interval/Startup
  + optional MaxRuntime; `POST /ScheduledTasks/{id}/Triggers` (full list). Run/Stop already work.
- **[MISSING] Admin Display page** — no nav entry; 6 fields → `POST /System/Configuration` +
  `…/metadata`: `EnableFolderView`, `DisplaySpecialsWithinSeasons`, `EnableGroupingMoviesIntoCollections`,
  `EnableGroupingShowsIntoCollections`, `EnableExternalContentInSuggestions`, `metadata.UseFileCreationTimeForDateAdded`.
- **[MISSING] Per-library Scan/Refresh** — `POST /Items/{id}/Refresh` (new `refreshItem`); add a button to the manage view.
- **[MISSING/PARTIAL] Dashboard cards** — storage paths (ServerPathWidget), system alerts (AlertsLogWidget),
  recent activity on home, running-tasks-with-progress; item-counts missing Albums/Songs/MusicVideos/Books.
- **[PARTIAL] Activity** — add user/system toggle, severity + date filters, paging, row→item link (currently fixed `?Limit=60`).
- **[PARTIAL] Libraries — add-library** posts empty `{}` options + single folder; web embeds the full options
  editor + multi-folder on create.

---

## TIER 3 — Config editor refinements (mostly control-type / showWhen / help)

- **[PARTIAL] Transcoding — HW-decoding codecs** is a raw CSV box (`AdminScreen.qml:87`); web is a curated
  per-accel checkbox group writing `HardwareDecodingCodecs[]` (`transcoding.tsx:228-297` + `codecs.ts`).
- **[PARTIAL] Transcoding — 4 color-depth toggles over-show** (`:88-91` use `neq:"none"`); web gates 10-bit
  HEVC/VP9 on `[amf,nvenc,qsv,vaapi,rkmpp]` and HEVC-RExt on `[nvenc,qsv,vaapi]`. Fix the `showWhen.oneOf`.
- **[PARTIAL] Transcoding — thread count** should be a select (Auto/-1, 1-16, Max/0), not a number (`:120`).
- **[MISSING] Transcoding — FFmpeg path** read-only field (`EncoderAppPathDisplay`, help `LabelffmpegPathHelp`).
- **[PARTIAL] Transcoding — 5 help texts** plain where web has clickable doc links (HwAccel, IntelLPHevc, TonemappingAlgorithm, FallbackFontPath); add `<a href>` (already supported).
- **[MISSING] Networking — Published Server URI / port-ranges section** — `UseSamePublishedUri` switch +
  `PublishedServerUri` (or split Internal/External), backed by `PublishedServerUriBySubnet` with `all=`/`internal=`/`external=`
  encoding (`networking/index.tsx:353-395` + `utils.ts`) — needs custom encode/decode, not the generic field kinds.
- **[PARTIAL] Networking — IsRemoteIPFilterBlacklist** is a toggle; web is a Whitelist/Blacklist select (+ no help).
- **[PARTIAL] Metadata — ChapterImageResolution** wrong control (`type:"text"` `:60`); web is a select
  (MatchSource/2160p…144p) + help "The resolution of the extracted chapter images. Changing this will have no effect on existing dummy chapters."
- **[NO-HELP] Metadata — DummyChapterDuration** help missing ("The interval between dummy chapters in seconds. Set to 0 to disable…").
- **[PARTIAL] Branding — Login disclaimer & Custom CSS** are single-line (`:53-54`); web is multiline mono
  textareas (single-line CSS editing is unusable). Needs a `multiline` field kind.
- **[MISSING] Branding — splashscreen** image preview + upload (`POST /Branding/Splashscreen`) + delete + 16:9 hint.
- **Good (full parity, no action):** General, Resume, Streaming, Trickplay, NFO (minor intro text), Networking core.

---

## TIER 4 — Browse depth (Home / Library / Search)

- **Library [MISSING]:** view-mode switcher (poster/list/thumb/banner/disc/logo), Show-Title/Year/Group-By-Series
  toggles, alphabet picker (`NameStartsWith`), paging, sort-direction (asc/desc) toggle + 4 sort options
  (Critic Rating, Date Played, Parental Rating, Play Count), Movies **Favorites** tab, TV **Episodes** tab,
  Suggestions-tab Resume row, and **7 of 9 filter-dialog groups** (Series Status, Features, Genres, Parental
  Ratings, Tags, Video Types, Years, Episode filters). `Features.libraryFilters:false` is stale (the popup ships).
- **Home [PARTIAL]:** 6 config slots vs web's 10; section vocab `{resume,nextup,mymedia,latest}` vs web's 9 types
  (tokens differ → not interoperable: `latest` vs `latestmedia`, `mymedia` vs `smalllibrarytiles`); missing
  Continue Listening (audio) / Continue Reading (book), LibraryButtons, Library Order (`OrderedViews`),
  per-library settings (`MyMediaExcludes`/`LatestItemsExcludes`/landing), folder grouping (`GroupedFolders`),
  Hide-watched-from-Latest (`HidePlayedInLatest`); no empty-state ("create a library").
- **Search [MISSING]:** grouping + the extra item types + suggestions panel (see 1.4); "No results" lacks query echo.

---

## TIER 5 — Detail depth (beyond BoxSet/Season in Tier 0)

- **[MISSING] Version/source selector + per-stream audio/subtitle dropdowns** — `parseItem` reads only
  `MediaSources[0]` (`JellyfinClient.cpp:636`); parse the full array + `DefaultAudio/SubtitleStreamIndex`,
  add a source dropdown when >1, feed indices into `requestStream`.
- **[MISSING] Series "Next Up" row** (`fetchNextUp` needs a `&SeriesId=` param), **Episode breadcrumb +
  "More From Season"** prev/next strip, **Chapters/Scenes** section (add `Fields=Chapters`; feeds the player too),
  **critic rating + tags + director/writer rows**, **Trailer** button (`RemoteTrailers`/`LocalTrailerCount`),
  **Play-from-beginning** + **Shuffle**, **Person birth/death/birthplace**, **Logo image**.
- **[DEAD/MISSING] More-menu** — Download/Edit-metadata/Refresh gated dead (`DetailScreen.qml:415-417`);
  Copy-stream-URL is a cheap win (`client.copyStreamUrl` exists, unused); Delete/Identify/Edit-images/Edit-subtitles
  absent (Delete needs a new `deleteItem` → `DELETE /Items/{id}`).
- **[PARTIAL]** Overview not rendered as markdown / no expand-clamp (low priority).

---

## Acceptable omissions (note, don't build)
Cast/AirPlay, SyncPlay, Picture-in-Picture (genuine engine limits — Cast/SyncPlay correctly render disabled;
don't render a dead PiP button). Live TV/DVR (out of scope). Music browsing tabs + music context actions.
Web/host-gated Display items: display-language, layout/display-mode, screensaver, BlurHash, theme songs/videos,
custom CSS (web), dashboard theme, gamepad/smooth-scroll. Light theme / skin picker (skin system deferred by the user).
External video players toggle (we ARE the player — remove the dead row rather than keep it).

---

## Proposed build plan (committable per area)

**Phase Q — quick wins / dead-control fixes — ✅ DONE (2026-06-16)**
1. ✅ `005f503` BoxSet collection members (grouped by type) + directly-opened Season episodes + collection Play-all. Verified live (Sharknado Collection).
2. ✅ `066936a` Dead MediaCard "Add to collection/playlist" wired via one shared picker in Main (signal-bubbling); DetailScreen inline picker removed; Copy-stream-URL added to detail more-menu. Verified live (picker opens + lists collections).
3. ✅ `8ccca7a` display/* prefs consumed: detailsBanner+backdrops→detail backdrop, fastAnimations→Theme tokens, maxDaysNextUp→NextUpDateCutoff, rewatchingNextUp→EnableRewatching, episodeImagesNextUp→card image pick. DisplayMissingEpisodes is server-driven (already works). **Deferred: `display/libraryPageSize` → Phase B** (needs real pagination + TotalRecordCount).
4. ✅ `2711774` Helper text across Display + Playback + Subtitle-mode (reactive). Fixed 2 default mismatches (episodeImages→true, maxDays→365). **Admin config-page helper text folded into Phase C** (with the control-type fixes for the same fields).

USER-VERIFY OWED (agent can't click/toggle): toggle each display/* pref + confirm effect; the add-to-collection/playlist *create*/*add* write path (picker was verified read-only only).

**Phase L — LibraryOptions provider tables (0.1) — ✅ DONE (2026-06-16)**
- ✅ `2cc3fd9` All 9 provider tables via `GET /Libraries/AvailableOptions` + a reusable `PluginTable` (checkbox + ▲▼ reorder), mirroring `libraryoptionseditor.js` field-for-field (DefaultEnabled fallback, getOrderedPlugins, inverse Disabled* logic, per-type merge). Server-driven incl. boxsets. Verified live (Collections → Emby Xml saver + TheMovieDb downloaders/image fetchers; Movies → multi-row tables w/ reorder).
- ✅ `c45cfe3` Per-type "Fetcher settings" (ImageOptions) dialog mirroring `imageOptionsEditor` (Fetch Primary/Logo/Thumb toggles + backdrop count/min-width from DefaultImageOptions). Verified live.
- ✅ `42be069` Last scalar field `DelimiterWhitelist` (music).
Shape verified live by read-only GET; no save fired. **Note:** `CustomTagDelimiters` ours comma-splits, web char-splits (`.split('')`) — minor pre-existing fidelity gap on a niche music field.

**Phase U — Users admin — ✅ DONE (2026-06-16)** — `1720fca` Profile tab (name + ~15 missing policy fields, two-endpoint save), `f92aacc` Access tab (library/channel/device allow-lists) + Parental tab (rating/block-unrated/tags/schedules) + Password (set/clear) + add-user. New client `createUser`/`setUserPassword`; reusable PolicyNumber/PolicySelect/AccessCheckList/TagEditor. Verified live; admin-gated sections (schedules, device access) correctly hidden.

**Phase A — remaining admin actions — ✅ DONE (2026-06-16)** — `1d00678` Devices rename/delete + API Keys create/revoke + Logs viewer + Plugins enable/disable/uninstall · `9b1a156` Display admin page + per-library Scan · `d19a782` config refinements (Metadata resolution dropdown+help, Networking blacklist select, Transcoding color-depth showWhen fix + thread select + FFmpeg path, Phase-C) · `0fb4d70` Scheduled-task triggers editor · `2c5b5a1` Dashboard item-counts (all categories) + Branding multiline · `92d91db` Plugins catalog/install + repositories. New client methods: renameDevice/deleteDevice/createApiKey/revokeApiKey/getText/updateTaskTriggers/refreshItem/setPluginEnabled/uninstallPlugin/installPackage/setRepositories. **Remaining admin polish (lower value):** Activity log filters; Networking Published-Server-URI (custom subnet encode); per-accel HW-decoding codec checkbox group (CSV works); Branding splashscreen upload. **N/A:** Backups (`/Backups` → 404 on this server version).

**Phase C — config-editor refinements (Tier 3)** — Transcoding codec group/showWhen/thread/FFmpeg,
Networking Published-URI, Metadata/Branding control types + multiline.

**Phase P — player features (Tier 1.5 + keyboard) — ✅ DONE except keyboard (2026-06-16)**
Web-parity OSD work, committed per area and screenshot-verified live (Re:Monster S1:E1):
- ✅ `ee4dfc9` OSD title composition ("Series - Sxx:Exx - Name" / "Movie (Year)") + duration↔remaining toggle (persisted).
- ✅ `52f0e6b` Trickplay hover thumbnails — parseItem Trickplay map + `trickplayUrl`; PlayerView fetches the full item on play + picks the resolution like web; PlayerControls clips one tile via `Image.sourceClipRect` with chapter name + time. Features.trickplay flipped (data-gated per item).
- ✅ `4b0cbb3` Chapter nav — prev/next-chapter buttons (⇤ ⇥, shown only with chapters) + a "scenes" jump menu, on the existing mpv chapter list + setChapter.
- ✅ `2ca8e13` Media-segment skip — `fetchMediaSegments` → GET /MediaSegments/{id}; per-type action map (defaults Intro+Outro=AskToSkip); 400ms poll auto-skips or arms a transient "Skip <Type>" button (independent of the OSD); the 5 settings rows un-stubbed.
- ✅ `481d470` Up-next card — web's showComingUpNextIfNeeded thresholds; thumbnail + "Next Episode Playing in N Seconds" + Start Now / Hide; gated on the now-wired next-video-overlay pref.
- ✅ `3e134c7` Buffered ranges — observe mpv demuxer-cache-state → `bufferedRanges`; scrubber draws each span (new Theme.bufferedBar) under the fill.
- ⏸ **Keyboard shortcuts (§1.2) — DEFERRED by the user** ("come back to it later"; matching the web look came first). All ~22 keys still map to existing invokables (zero engine work) when picked up.
**User-verify-owed (agent has no pointer/key input):** the remaining/ends-at toggle click, trickplay hover-follow, chapter prev/next/jump clicks, real media-segment skip+auto-skip (this server has no segment data — verified with an injected segment), up-next Start Now/Hide. Build green, tree clean.

**Phase B — DETAIL/PLAY depth — ✅ DONE (2026-06-17); browse depth still pending.**
Triggered by a user-reported bug (episodes from Next Up didn't auto-advance) → a full 1:1 sweep of the
detail page + play/queue + card menu, committed per area and screenshot-verified live via window-id capture
(`xwininfo -name` → `import -window <id>`, which grabs our app regardless of focus):
- ✅ `a9d4b31` **Play-queue fix** — playing a single episode (Next Up / Continue Watching / search / card)
  now queues the series from that episode (`fetchEpisodes` gains `startItemId`), so auto-advance / up-next /
  prev-next work across seasons, not just from a season's Play. Verified 1/1 → 2/10.
- ✅ `a06d7d3` Series Play → global Next Up (crosses seasons) · Play-from-beginning (↺) · Shuffle (⇄,
  series/season/boxset). (`🔀` emoji is tofu on this box — only that glyph; player emoji render fine.)
- ✅ `1a13c29` Detail Refresh metadata + Delete (new `deleteItem`, `CanDelete`-gated, confirm dialog).
- ✅ `2db46cd` Series "Next Up" row · episode breadcrumb (clickable series + SxxExx) + "More From Season N".
- ✅ `e767965` Chapters/Scenes section (parseItem Chapters + `imageUrl` Chapter index; click → play from start).
- ✅ `1feaf1f` Logo image · tags chips · Director/Writer rows · critic rating · person Born/Died/Birthplace ·
  expandable overview.
- ✅ `8be7a4e` Version/source selector + default audio/subtitle (full MediaSources; `requestStream`/`streamUrl`
  gain optional source/audio/sub — direct-play maps the Jellyfin Index→mpv ff-index, transcode passes to
  PlaybackInfo; **all optional so the 90% direct-play path is unchanged**). ff-index↔Index match verified.
- ✅ `b5d19bc` Card context menu completed — Add to queue / Play next (live `enqueue`/`playNextInsert`) +
  Refresh/Delete via a shared Main confirm; one `cardAction(verb,item)` signal plumbed through all screens.
**Editors deferred by the user:** Edit metadata / images / subtitles / Identify + Download (large dialogs;
stay greyed). **User-verify-owed (no pointer/key input):** every click path (the menus/selectors render +
the backing primitives are verified; mutations confirm-gated and never fired).
**STILL PENDING in B — browse depth (Tier 4):** library view-modes/alpha/paging/sort-direction + the 7
missing filter-dialog groups, grouped search (+ extra item types), Home extra section types,
`display/libraryPageSize`, detail Trailer button. These were not part of this detail/play sweep.
