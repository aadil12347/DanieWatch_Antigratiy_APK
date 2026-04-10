# DanieWatch — Online Player & Download System: Detailed Explanation

> This document provides a comprehensive, step-by-step explanation of how the DanieWatch Android app handles **online video playback** and **content downloading**. It covers the entire pipeline from data sourcing to the final pixel on screen.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Online Player — Complete Flow](#2-online-player--complete-flow)
   - 2.1 [Content Data Sourcing](#21-content-data-sourcing)
   - 2.2 [Watch Link Extraction](#22-watch-link-extraction)
   - 2.3 [Video URL Discovery (The Extraction Process)](#23-video-url-discovery-the-extraction-process)
   - 2.4 [Playback Engine Selection](#24-playback-engine-selection)
   - 2.5 [hls.js WebView Player](#25-hlsjs-webview-player)
   - 2.6 [BetterPlayerPlus Native Player](#26-betterplayerplus-native-player)
   - 2.7 [Episode Switching & Background Extraction](#27-episode-switching--background-extraction)
   - 2.8 [Error Handling & Retry Logic](#28-error-handling--retry-logic)
3. [Download System — Complete Flow](#3-download-system--complete-flow)
   - 3.1 [Download Method Overview](#31-download-method-overview)
   - 3.2 [Method 1: HLS Segment Download (Primary)](#32-method-1-hls-segment-download-primary)
   - 3.3 [Method 2: Legacy Direct Download](#33-method-2-legacy-direct-download)
   - 3.4 [M3U8 Parser — Quality/Audio/Subtitle Selection](#34-m3u8-parser--qualityaudiosubtitle-selection)
   - 3.5 [HLS Downloader Service — Segment Download Engine](#35-hls-downloader-service--segment-download-engine)
   - 3.6 [FFmpeg Muxing — TS Segments to MP4](#36-ffmpeg-muxing--ts-segments-to-mp4)
   - 3.7 [Download Manager — State & Lifecycle](#37-download-manager--state--lifecycle)
   - 3.8 [Notification System](#38-notification-system)
   - 3.9 [Pause / Resume / Cancel](#39-pause--resume--cancel)
4. [Key Files Reference](#4-key-files-reference)
5. [Data Flow Diagrams](#5-data-flow-diagrams)

---

## 1. Architecture Overview

DanieWatch uses a **hybrid architecture** combining:

- **Flutter/Dart** for the UI layer, state management (Riverpod), and business logic
- **InAppWebView** for video extraction from embed pages and for the hls.js-based player
- **BetterPlayerPlus** (ExoPlayer under the hood) as a native fallback player
- **FFmpeg** for post-download video conversion (TS → MP4)
- **GitHub JSON** + **TMDB API** as the data source layer

The app follows a **repository pattern**:
```
UI (Screens/Widgets)
  → Providers (Riverpod)
    → Repository (ContentRepository)
      → Data Sources (TmdbClient, GitHub JSON)
```

---

## 2. Online Player — Complete Flow

### 2.1 Content Data Sourcing

When a user opens a movie or TV show detail page, the app fetches content data from **two sources** and merges them:

#### Source 1: GitHub JSON (Streaming Links)
- URL pattern: `{GITHUB_RAW_BASE}/streaming_links/admin_{type}_{id}.json` (admin path)
- Fallback: `{GITHUB_RAW_BASE}/streaming_links/normal_{type}_{id}.json` (normal path)
- Admin JSON contains: title, watch links, download links, seasons/episodes with embed URLs
- Normal JSON contains: simpler structure with watch/download links per episode

#### Source 2: TMDB API (Metadata & Visuals)
- Movie details: `/movie/{id}` (with `append_to_response=credits,videos,images`)
- TV details: `/tv/{id}` (with same append)
- Provides: poster, backdrop, logo, trailer, cast, genres, overview, ratings, season metadata

**Merging Strategy** (in `ContentRepository.fetchContentDetail`):
- **Admin path**: TMDB for metadata/visuals + GitHub for streaming links and episode data
- **Normal path**: TMDB for everything visual + GitHub only for watch/download links
- Visuals (poster, backdrop, logo, trailer) **always** prefer TMDB

### 2.2 Watch Link Extraction

From the merged data, the app extracts the **embed URL** (watch link):

**For Movies:**
```
watchLink = githubEntry['watch'] ?? githubEntry['watch_link'] ?? githubEntry['play_url']
```
The raw value can be:
- A direct URL: `https://bysebuho.com/e/abc123`
- An iframe string: `<iframe src="https://bysebuho.com/e/abc123">`

The `extractValidEmbedUrl()` method:
1. If the string contains `<iframe`, it extracts the `src` attribute
2. Checks against a **suspicious domains filter** (ads, popups, trackers)
3. Returns the clean embed URL or `null` if suspicious

**For TV Shows:**
- Each season has a `season_N` key containing a list of watch links per episode
- Episodes are built by merging TMDB episode metadata with GitHub watch links
- Each `EpisodeData` object gets a `playLink` field with the embed URL

### 2.3 Video URL Discovery (The Extraction Process)

This is the **core innovation** of DanieWatch. Since embed pages (like bysebuho.com) don't expose direct video URLs, the app uses a **WebView-based resource interception** technique.

#### Step-by-Step Process:

1. **User taps "Play"** → `VideoPlayerScreen` is navigated to with the embed URL

2. **A hidden 1×1 pixel InAppWebView** is created that loads the embed URL:
   ```dart
   InAppWebView(
     key: _webViewKey,
     initialUrlRequest: URLRequest(url: WebUri(embedUrl)),
     initialSettings: InAppWebViewSettings(
       javaScriptEnabled: true,
       mediaPlaybackRequiresUserGesture: false,
       useOnLoadResource: true,  // ← CRUCIAL: intercepts all resource loads
     ),
   )
   ```

3. **Auto-Click Mechanism** starts immediately:
   - A `Timer.periodic` fires every **1.5 seconds**
   - Injects JavaScript that:
     - Clicks common play buttons (`.play-btn`, `.vjs-big-play-button`, `.jw-display-icon-display`, `.plyr__control--overlaid`)
     - Clicks the element at the center of the page
     - Calls `video.play()` on any `<video>` element
   ```javascript
   (function() {
     var buttons = document.querySelectorAll('.play-btn, .vjs-big-play-button, ...');
     for(var i=0; i<buttons.length; i++) { buttons[i].click(); }
     var el = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
     if (el) { el.click(); }
     var v = document.querySelector('video');
     if (v) { v.play().catch(function(e){}); }
   })();
   ```

4. **Resource Interception** via `onLoadResource`:
   - Every HTTP resource the WebView loads is captured
   - The URL is passed to `_handleExtractedLink()`
   - Only `.m3u8` and `.mp4` URLs are kept
   - URLs containing `ads` are filtered out

5. **Link Ranking & Selection**:
   - All discovered links are stored in `_discoveredLinks` (a `Set<String>`)
   - **Priority 1**: `master.m3u8` or `.urlset` links (master playlists with all qualities)
   - **Priority 2**: Links containing `_h`, `1080`, or `720` (high quality variants)
   - **Priority 3**: Any other discovered link (fallback)
   - Among same priority, the **longest URL** is preferred (often has more complete query parameters)

6. **Discovery Completion Logic**:
   - If a `master.m3u8` is found → wait 200ms for nearby variants, then complete
   - If a fallback link is found → wait 3 seconds for a master to appear
   - Absolute timeout: 10 seconds (first attempt), 20 seconds (auto-retry), 30 seconds (manual retry)

7. **Result**: The best discovered link is passed to `_startPlayback()`.

### 2.4 Playback Engine Selection

After extraction, the app chooses between **two playback engines**:

```
┌─────────────────────────────────────────────┐
│  isOffline or isDirectLink?                  │
│  ├── YES → BetterPlayerPlus (native)        │
│  └── NO  → hls.js WebView Engine (primary)  │
│       └── Fallback: BetterPlayerPlus         │
│           (if WebView engine fails)          │
└─────────────────────────────────────────────┘
```

**Primary: hls.js WebView** (`_switchToWebEngine()`)
- Used for all online HLS streams
- More reliable for complex HLS manifests with multiple audio tracks
- Supports adaptive bitrate switching

**Fallback: BetterPlayerPlus** (`_initializeBetterPlayer()`)
- Used for offline playback (local files)
- Used for direct MP4 links
- Auto-switches to WebView if a `BetterPlayerEventType.exception` occurs

### 2.5 hls.js WebView Player

The primary player is an HTML file (`assets/html/player.html`) loaded in an `InAppWebView`. It uses the **hls.js** library for HLS playback.

#### Key Features:
- **Custom UI**: Fully custom controls (no native WebView controls)
  - Back button, episode badge (top bar)
  - Center play/pause button with blur backdrop
  - Seek bar with buffer progress, thumbnail tooltip
  - Volume toggle, zoom toggle, settings gear
  - Double-tap to skip ±15 seconds (with ripple animation)
  - Auto-hiding controls with 3-second timeout

- **HLS.js Integration**:
  ```javascript
  hls = new Hls({ enableWorker: true, lowLatencyMode: true });
  hls.loadSource(url);
  hls.attachMedia(video);
  ```
  - Automatic quality adaptation (ABR)
  - Audio track selection from manifest
  - Error recovery: network errors → `startLoad()`, media errors → `recoverMediaError()`

- **Settings Menu** (glassmorphism design):
  - Quality picker (from HLS manifest levels)
  - Audio track picker (from HLS manifest audio tracks)
  - Multi-level navigation with back button

- **Flutter ↔ JavaScript Bridge**:
  - `playVideo(url)` — called from Flutter to start playback
  - `updateEpisodeButton(text)` — shows/hides episode selector
  - `videoTitle(text)` — sets the episode badge text
  - `setMediaType(type)` — shows episode button for TV shows
  - `goBack` handler — calls Flutter's `_goBack()`
  - `showEpisodes` handler — calls Flutter's `_showEpisodeSelector()`

### 2.6 BetterPlayerPlus Native Player

Used as a fallback and for offline playback:

```dart
BetterPlayerDataSource(
  isOffline ? BetterPlayerDataSourceType.file : BetterPlayerDataSourceType.network,
  url,
  useAsmsAudioTracks: true,
  useAsmsTracks: true,
  useAsmsSubtitles: true,
  notificationConfiguration: BetterPlayerNotificationConfiguration(
    showNotification: true,
    title: widget.title,
    author: 'DanieWatch',
  ),
  bufferingConfiguration: BetterPlayerBufferingConfiguration(
    minBufferMs: 5000,
    maxBufferMs: 30000,
    bufferForPlaybackMs: 2500,
    bufferForPlaybackAfterRebufferMs: 5000,
  ),
);
```

- Supports HLS, DASH, and progressive MP4
- Background audio playback with notification controls
- Subtitle and audio track selection
- Error listener auto-switches to WebView engine on failure

### 2.7 Episode Switching & Background Extraction

For TV shows, the player supports **seamless episode switching** without leaving the player:

1. User taps the "Episodes" button → a dialog appears with season/episode list
2. User selects a new episode → the dialog closes
3. **Background extraction** starts for the new episode's embed URL:
   - A separate `InAppWebView` (offstage, 1×1 pixel) loads the new embed URL
   - Same auto-click + resource interception process
   - `_bgDiscoveredLinks` collects the links
   - `_bgAutoClickTimer` runs the click sequence
   - 30-second absolute timeout
4. When background discovery completes, the current playback seamlessly switches to the new link

This allows the user to keep watching the current episode while the next one loads in the background.

### 2.8 Error Handling & Retry Logic

The player implements a **"Nuclear Reset"** retry strategy:

1. **First failure** (10s timeout): Silent auto-retry
   - All timers cancelled
   - WebView key changed (forces complete WebView recreation)
   - Cookies cleared via `CookieManager.instance().deleteAllCookies()`
   - All state reset: `_discoveredLinks.clear()`, `_discoveryComplete = false`
   - New extraction process started with 20s timeout

2. **Second failure** (20s timeout): Another auto-retry with 30s timeout

3. **Third+ failure**: Error overlay shown with "Retry" and "Back" buttons
   - User can manually trigger another Nuclear Reset
   - Or go back to the detail page

---

## 3. Download System — Complete Flow

### 3.1 Download Method Overview

DanieWatch supports **two download methods**:

| Method | Use Case | Format | Engine |
|--------|----------|--------|--------|
| **HLS Segment Download** | M3U8 streams (primary) | .ts segments → .mp4 | Custom HlsDownloaderService + FFmpeg |
| **Legacy Direct Download** | Direct MP4/CDN links | .mp4 directly | flutter_downloader |

The app automatically selects the appropriate method based on the URL type.

### 3.2 Method 1: HLS Segment Download (Primary)

This is the main download path for HLS streams. The complete flow:

```
User taps "Download"
  → VideoExtractorService extracts m3u8 URL from embed page
  → M3u8Parser parses the master playlist
  → QualitySelectorSheet shows quality/audio/subtitle options
  → User selects quality, audio track, (optional subtitles)
  → DownloadManager.startSegmentDownload()
  → HlsDownloaderService downloads .ts segments in parallel
  → FFmpeg muxes segments into .mp4
  → Cleanup segment files
  → Notification: "Download complete"
```

#### Detailed Steps:

**Step 1: Video URL Extraction**
- `VideoExtractorService.extractVideoUrl(embedUrl)` uses the same WebView-based extraction as the player
- Uses a `HeadlessInAppWebView` (no UI needed)
- Implements a **4-click sequence** after page load:
  1. Close overlays/popups
  2. Click center of page
  3. Click common play buttons
  4. Wait 1.2 seconds between each click
- Blocks popups via `onCreateWindow` returning `true` without creating a window
- Blocks ad redirects via `shouldOverrideUrlLoading`
- Results are **cached** in SharedPreferences (key: `extract_{embedUrl}`)

**Step 2: Master Playlist Parsing**
- `M3u8Parser.parse(m3u8Url)` fetches and parses the master playlist
- Extracts:
  - **Stream Variants** (`#EXT-X-STREAM-INF`): quality levels with bandwidth, resolution, codecs
  - **Audio Tracks** (`#EXT-X-MEDIA:TYPE=AUDIO`): language, name, URL, default flag
  - **Subtitle Tracks** (`#EXT-X-MEDIA:TYPE=SUBTITLES`): language, name, URL
- Variants sorted best → worst by bandwidth
- Audio tracks deduplicated by language+name
- Robust Hindi detection: checks name/URI for "hindi" even if mislabeled

**Step 3: Quality Selection UI**
- `QualitySelectorSheet` shows a bottom sheet with:
  - Quality pills (horizontal scroll): 1080p HD, 720p HD, 480p, 360p
  - Audio track list (vertical): with flag emojis and language names
  - Subtitle toggle switch
  - Estimated file size display
  - "Start Download" button with selected options label

**Step 4: Segment Download**
- `DownloadManager.startSegmentDownload()` creates a `DownloadItem` and starts `HlsDownloaderService`

### 3.3 Method 2: Legacy Direct Download

For direct MP4 links (typically from bysebuho.com/download/ pages):

1. `DownloadModal` opens a WebView loading the download page
2. The URL is transformed: `bysebuho.com/e/{id}` → `bysebuho.com/download/{id}`
3. The WebView intercepts resources looking for CDN links:
   - Pattern: `r66nv9ed.com`, `edge1-waw`, `sprintcdn` + `.mp4` or `download/`
4. XHR/fetch interceptor is injected to catch CDN links from AJAX responses
5. Click event listener catches `<a>` tags pointing to CDN
6. `onDownloadStartRequest` catches browser-initiated downloads
7. Once a CDN link is captured, `FlutterDownloader.enqueue()` starts the download
8. Progress is tracked via isolate-based callback

### 3.4 M3U8 Parser — Quality/Audio/Subtitle Selection

The `M3u8Parser` class (`lib/services/m3u8_parser.dart`) is the backbone of the quality selection system:

#### Data Models:

**`StreamVariant`** — A single quality level:
- `url`: Absolute URL to the variant playlist
- `bandwidth`: Bits per second
- `resolution`: e.g., "1280x720"
- `codecs`: Codec information
- `audioGroupId`: Links to an AudioTrack group
- `qualityLabel`: Human-readable (e.g., "720p")
- `estimatedSize`: Based on bandwidth × 45 minutes
- `badgeLabel`: Display label (e.g., "1080p HD", "4K")

**`AudioTrack`** — An audio stream:
- `groupId`: Links to StreamVariant's audioGroupId
- `language`: ISO code (e.g., "en", "hi")
- `name`: Display name (e.g., "English", "Hindi 5.1")
- `url`: Direct URI (null if muxed into video)
- `isDefault` / `isForced`: Default selection flags

**`SubtitleTrack`** — A subtitle stream:
- `language`, `name`, `url`, `isDefault`

**`PlaylistInfo`** — Parsed result:
- `variants`: Sorted best → worst
- `audioTracks`: All available audio tracks
- `subtitles`: All available subtitle tracks
- `isMasterPlaylist`: Whether this was a master or media playlist
- `defaultVariant`: Prefers 720p, falls back to first
- `defaultAudio`: Prefers Hindi, then DEFAULT=YES, then first

### 3.5 HLS Downloader Service — Segment Download Engine

`HlsDownloaderService` (`lib/services/hls_downloader_service.dart`) handles the actual segment downloading:

#### Configuration:
- **5 parallel workers** (`_maxWorkers = 5`)
- **3 retries per segment** with exponential backoff (0ms, 2s, 5s)
- **HTTP Range resume** for partial segments
- **Connectivity monitoring** via `connectivity_plus`

#### Phase 1: Parse Media Playlists
- Fetches the variant playlist (video), audio playlist, and subtitle playlist
- If a master playlist is accidentally passed, it auto-extracts the first variant
- Parses each playlist line by line:
  - `#EXT-X-KEY:URI="..."` → encryption key segment
  - `#EXT-X-MAP:URI="..."` → initialization segment
  - Non-comment lines → media segment URLs
- Each segment becomes a `_SegmentTask` with URL and local path

#### Phase 2: Download Segments
- 5 worker coroutines run in parallel
- Each worker:
  1. Takes the next segment from the queue
  2. Skips already-downloaded segments (resume support)
  3. Downloads with retry logic
  4. Supports HTTP Range headers for partial downloads
  5. Writes chunks synchronously via `RandomAccessFile` for performance
  6. Reports progress after each segment

#### Phase 3: FFmpeg Mux to MP4
- Creates concat list files for video, audio, and subtitle segments
- Builds FFmpeg command:
  ```
  -f concat -safe 0 -i "video_list.txt"
  [-f concat -safe 0 -i "audio_list.txt"]
  [-f concat -safe 0 -i "sub_list.txt"]
  -map 0:v [-map N:a] [-map N:s]
  -c:v copy -c:a copy [-c:s mov_text]
  -y "output.mp4"
  ```
- Video and audio are **copied** (no re-encoding)
- Subtitles use `mov_text` codec for MP4 compatibility
- On success, segment directory is cleaned up

#### Phase 4: Cleanup
- Deletes the temporary segment directory
- Fires `onComplete` callback with the MP4 path

### 3.6 FFmpeg Muxing — TS Segments to MP4

The conversion process uses `ffmpeg_kit_flutter_new_min`:

1. **Concat demuxer**: All .ts segments are listed in a text file
2. **Stream mapping**: Video from input 0, audio from input 0 or 1, subtitles from input 2
3. **Copy codecs**: No re-encoding (`-c:v copy -c:a copy`)
4. **Subtitle codec**: `-c:s mov_text` for MP4 container compatibility
5. **Overwrite**: `-y` flag to overwrite existing files

Progress mapping:
- 0–96%: Segment downloading
- 97%: FFmpeg conversion
- 100%: Complete

### 3.7 Download Manager — State & Lifecycle

`DownloadManager` (`lib/data/local/download_manager.dart`) is a singleton that manages all downloads:

#### State Model:
```dart
enum DownloadStatus {
  pending, downloading, paused, completed, failed, canceled, converting
}
```

#### DownloadItem Fields:
- `id`: Timestamp-based unique ID
- `url`: Original embed URL
- `videoStreamUrl`, `audioStreamUrl`, `subtitleStreamUrl`: Selected stream URLs
- `qualityLabel`, `audioLabel`, `subtitleLabel`: Display labels
- `progress`: 0.0–1.0
- `totalSegments`, `completedSegments`: Segment tracking
- `downloadSpeed`: Bytes per second
- `localPath`: Final MP4 path
- `segmentDirectory`: Temp directory for .ts files

#### Persistence:
- All download items are serialized to JSON and stored in SharedPreferences
- On app restart, interrupted downloads are reset to `paused` status
- Resume works by re-running `HlsDownloaderService` which auto-skips already-downloaded segments

#### Stream Controllers:
- `updateStream`: Broadcasts `DownloadItem` on every progress update
- `completeStream`: Broadcasts `DownloadItem` on completion
- UI widgets listen to these streams for real-time updates

### 3.8 Notification System

`DownloadNotificationService` (`lib/services/download_notification_service.dart`) provides Android notification bar integration:

- **Progress notifications**: Ongoing notification with percentage, speed
- **Completion notification**: "✅ {title} — Download complete"
- **Failure notification**: "❌ {title} — {error message}"
- **Notification channel**: `download_channel` (low importance, no badge)
- **Action buttons**: Pause/Resume/Cancel (wired via `onNotificationAction` callback)
- **Throttling**: Notification updates limited to 1 per second or on percentage change

### 3.9 Pause / Resume / Cancel

**Pause**:
- HLS downloads: Sets `_isPaused = true` on the `HlsDownloaderService`
  - Workers check `isPaused` before each segment and sleep while paused
- Legacy downloads: `FlutterDownloader.pause(taskId:)`
- Notification updated to show "Paused" state

**Resume**:
- HLS downloads: Sets `_isPaused = false` and `_isNetworkPaused = false`
  - If the service was disposed, re-runs `_runSegmentDownload()`
  - Already-completed segments are auto-skipped
- Legacy downloads: `FlutterDownloader.resume(taskId:)`

**Cancel**:
- HLS downloads: Sets `_isCancelled = true`, removes from active map
- Legacy downloads: `FlutterDownloader.cancel(taskId:)`
- Segment directory is deleted
- Notification is dismissed

**Network Auto-Pause**:
- `connectivity_plus` monitors network changes
- On network loss: auto-pauses all active downloads
- On network restore: waits 2 seconds, then auto-resumes

---

## 4. Key Files Reference

| File | Purpose |
|------|---------|
| `lib/presentation/screens/video_player/video_player_screen.dart` | Main video player screen with extraction, playback, episode switching |
| `lib/services/video_extractor_service.dart` | WebView-based m3u8 URL extraction from embed pages |
| `lib/services/hls_downloader_service.dart` | HLS segment downloader with parallel workers |
| `lib/services/m3u8_parser.dart` | M3U8 master playlist parser (quality, audio, subtitles) |
| `lib/services/download_notification_service.dart` | Android notification bar integration |
| `lib/data/local/download_manager.dart` | Download state management, persistence, lifecycle |
| `lib/data/repositories/content_repository.dart` | Content data fetching (GitHub + TMDB merge) |
| `lib/presentation/providers/detail_provider.dart` | Riverpod providers for content details and episodes |
| `lib/presentation/widgets/download_modal.dart` | Legacy download WebView modal |
| `lib/presentation/widgets/quality_selector_sheet.dart` | Quality/audio/subtitle selection UI |
| `lib/domain/models/content_detail.dart` | Domain models (ContentDetail, EpisodeData, etc.) |
| `assets/html/player.html` | hls.js-based WebView player with custom controls |

---

## 5. Data Flow Diagrams

### Online Playback Flow

```
┌──────────┐     ┌──────────────────┐     ┌──────────────────┐
│  User    │     │ ContentRepo      │     │ GitHub + TMDB    │
│  taps    │────▶│ fetchDetail()    │────▶│ APIs             │
│  Play    │     │                  │◀────│                  │
└──────────┘     │ Returns:         │     └──────────────────┘
                 │ - watchLink      │
                 │ - episodes[]     │
                 │ - poster, etc.   │
                 └────────┬─────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────┐
│              VideoPlayerScreen                           │
│                                                          │
│  ┌─────────────────────────────────────────────────┐     │
│  │  Hidden 1×1 InAppWebView (Extraction)           │     │
│  │  - Loads embed URL                              │     │
│  │  - Auto-clicks play buttons every 1.5s          │     │
│  │  - Intercepts resources via onLoadResource      │     │
│  │  - Collects .m3u8/.mp4 URLs                    │     │
│  │  - Ranks: master.m3u8 > 1080p > 720p > fallback │     │
│  └────────────────────┬────────────────────────────┘     │
│                       │ Best URL                          │
│                       ▼                                   │
│  ┌─────────────────────────────────────────────────┐     │
│  │  Playback Engine Selection                       │     │
│  │  - Online → hls.js WebView (primary)            │     │
│  │  - Offline → BetterPlayerPlus (native)          │     │
│  │  - Error  → Auto-switch to WebView             │     │
│  └─────────────────────────────────────────────────┘     │
│                                                          │
│  ┌─────────────────────────────────────────────────┐     │
│  │  hls.js WebView Player (player.html)            │     │
│  │  - Custom controls with glassmorphism           │     │
│  │  - Quality/audio picker from HLS manifest       │     │
│  │  - Double-tap ±15s skip                         │     │
│  │  - Flutter ↔ JS bridge for navigation           │     │
│  └─────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────┘
```

### Download Flow

```
┌──────────┐     ┌───────────────────┐     ┌──────────────────┐
│  User    │     │ VideoExtractor    │     │ Embed Page       │
│  taps    │────▶│ Service           │────▶│ (Headless WebView│
│  Download│     │ extractVideoUrl() │◀────│  auto-clicks)    │
└──────────┘     │ Returns: m3u8 URL │     └──────────────────┘
                 └────────┬──────────┘
                          │
                          ▼
                 ┌───────────────────┐
                 │ M3u8Parser        │
                 │ parse(m3u8Url)    │
                 │ Returns:          │
                 │ - variants[]      │
                 │ - audioTracks[]   │
                 │ - subtitles[]     │
                 └────────┬──────────┘
                          │
                          ▼
                 ┌───────────────────┐
                 │ QualitySelector   │
                 │ Sheet (UI)        │
                 │ User picks:       │
                 │ - Quality level   │
                 │ - Audio track     │
                 │ - Subtitles?      │
                 └────────┬──────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────┐
│              DownloadManager                             │
│                                                          │
│  startSegmentDownload()                                  │
│  ├── Creates DownloadItem                                │
│  ├── Shows notification (0%)                              │
│  └── _runSegmentDownload()                               │
│       │                                                  │
│       ▼                                                  │
│  ┌─────────────────────────────────────────────────┐     │
│  │  HlsDownloaderService                           │     │
│  │  Phase 1: Parse media playlists                 │     │
│  │  Phase 2: Download segments (5 workers)         │     │
│  │  Phase 3: FFmpeg mux → .mp4                     │     │
│  │  Phase 4: Cleanup .ts segments                  │     │
│  └─────────────────────────────────────────────────┘     │
│       │                                                  │
│       ▼                                                  │
│  Notification: "✅ Download complete"                     │
│  File: /storage/emulated/0/Download/DanieWatch/xxx.mp4   │
└──────────────────────────────────────────────────────────┘
```

---

## Summary

The DanieWatch app implements a sophisticated video streaming and download system:

1. **Online Playback** uses a WebView-based resource interception technique to extract direct HLS/MP4 URLs from embed pages that don't expose them directly. The auto-click mechanism and progressive discovery with intelligent link ranking make it robust against various embed page designs.

2. **The hls.js WebView player** provides a Netflix-like experience with custom controls, quality/audio selection, and seamless episode switching — all within a single screen.

3. **Downloads** use a two-pronged approach: the primary HLS segment downloader with parallel workers, quality selection, and FFmpeg conversion; and a legacy direct-download fallback for simple MP4 links.

4. **Resilience** is built in at every level: auto-retry with "Nuclear Reset", connectivity monitoring, segment-level resume, and automatic engine fallback.