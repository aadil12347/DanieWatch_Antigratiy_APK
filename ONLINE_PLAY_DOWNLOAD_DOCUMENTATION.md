# Online Play & Download Feature Documentation

## Overview
This document describes how the online streaming (play) and download features work in the DanieWatch Android app.

---

## Architecture Overview

### Data Flow Diagram
```
Supabase Database (entries, entry_metadata tables)
        ↓
ContentRepository (fetches & processes links)
        ↓
DetailProvider / EpisodesProvider (Riverpod state management)
        ↓
DetailsScreen (UI with Play/Download buttons)
        ↓
VideoPlayerScreen / DownloadManager (actual playback/download)
```

---

## How Online Play Works

### 1. Link Extraction (ContentRepository)
**File:** `lib/data/repositories/content_repository.dart`

The app fetches streaming links from Supabase in two ways:

#### For Movies:
```dart
// Extracts from content JSON
watchLink = contentJson['watch_link'] ?? contentJson['play_url'] ?? contentJson['stream_url']
```

#### For TV Series:
```dart
// Fetches episode links per season from entry_metadata table
// Or from entries.content JSON (season_X.watch_links array)
seasonLinks = _extractSeasonLinks(entryResponse['content'], seasonNumber)
```

#### Link Validation:
- **Suspicious Link Filter:** Blocks domains containing: 'click', 'clk', 'ads', 'pop', 'banner', 'tracker', 'analytics', 'doubleclick', etc.
- **Iframe Extraction:** Parses `<iframe src="...">` tags to get embedded player URLs

### 2. State Management (Providers)
**File:** `lib/presentation/providers/detail_provider.dart`

Two main providers:
- `detailProvider`: Fetches movie/TV details including watch links
- `episodesProvider`: Fetches episodes for a specific season with play/download links

### 3. UI - Play Button
**File:** `lib/presentation/screens/details/details_screen.dart`

```dart
// Gets first episode's play link for TV, or movie's watchLink for movies
watchLink = content.watchLink ?? content.playUrl;
// OR for TV series:
watchLink = episodes.first.playLink;
```

### 4. Video Player
**File:** `lib/presentation/screens/video_player/video_player_screen.dart`

Uses `flutter_inappwebview` to load streaming URLs in an embedded WebView:
- JavaScript enabled for player functionality
- Supports landscape/portrait orientations
- Shows loading progress and error handling
- **FIXED:** Handles blob URLs properly without breaking playback

---

## How Download Works

### 1. Download Manager
**File:** `lib/data/local/download_manager.dart`

#### Features:
- Uses `flutter_downloader` plugin for native Android downloads
- Stores downloads in `/storage/emulated/0/Download/DanieWatch/`
- Persists download list to SharedPreferences (JSON)
- Supports pause, resume, cancel operations

#### DownloadItem Model:
```dart
class DownloadItem {
  String id, url, title, localPath, taskId;
  int season, episode, totalBytes, downloadedBytes;
  DownloadStatus status; // pending, downloading, paused, completed, failed
  double progress;
  String? posterUrl, fileExtension; // Preserves original format (.mp4, .mkv, etc.)
}
```

#### Key Methods:
- `startDownload()`: Creates download task, saves to storage
- `pauseDownload()` / `resumeDownload()`: Control active downloads
- `cancelDownload()`: Stops and removes download
- `deleteDownload()`: Removes file from device + storage
- `extractExtension()`: Preserves original file format from URL

### 2. Download UI
**File:** `lib/presentation/screens/downloads/downloads_screen.dart`

- Shows downloading items with progress bar
- Shows completed items with play/delete options
- Uses `open_file` package to play downloaded files
- Pull-to-refresh to update list

### 3. Download Trigger
**File:** `lib/presentation/screens/details/details_screen.dart`

```dart
// Movies: Download button directly starts download
_downloadManager.startDownload(
  url: downloadLink,
  title: content.title,
  season: 0,  // 0 = movie
  episode: 0,
  posterUrl: content.posterUrl,
)

// TV Episodes: Download button per episode
_downloadManager.startDownload(
  url: episode.downloadLink,
  title: content.title,
  season: selectedSeason,
  episode: episodeNumber,
  posterUrl: content.posterUrl,
)
```

---

## Data Storage

### Supabase Tables:
1. **entries**: Main content table
   - `id`: TMDB ID
   - `type`: 'movie' or 'series'
   - `content`: JSON with watch_links, download_links
   - `poster_url`, `backdrop_url`, `overview`, etc.

2. **entry_metadata**: Per-season/episode metadata
   - `entry_id`: TMDB ID
   - `season_number`: Season number
   - `episode_number`: Episode number
   - `name`, `overview`, `still_path`, `runtime`, etc.

### Local Storage:
- **SharedPreferences**: Download queue (JSON), watchlist, search history
- **Device Storage**: Downloaded files in `/Download/DanieWatch/`

---

## FIXED: Blob URL Video Player Issue

**Problem:** The previous ad-blocking implementation interfered with blob URLs used by video players (like Vidplay, Streamtape, etc.). When the ad blocker blocked ad content, it caused the blob URL to throw errors after 1-2 seconds of playback.

**Solution Applied:**

### 1. Removed Aggressive URL Blocking (Option 3)
- **Before:** Blocked known ad domains at WebView level, which interfered with blob URLs
- **After:** 
  - Always allow blob: URLs unconditionally (critical for video playback)
  - Allow all URLs from the same origin as the player
  - Added more video player patterns: videojs, jwplayer, clappr, plyru
  - Only block truly suspicious pop-ups/new windows

### 2. Injected JavaScript for In-Page Ad Handling (Option 2)
Instead of blocking at WebView level, we now inject JavaScript that:
- Hides ad elements using CSS without breaking video playback
- Auto-clicks skip buttons for video ads (every 500ms)
- Removes ad overlays
- Explicitly ensures the video element is always visible
- Attempts to auto-play video if prevented

**Code Location:** `lib/presentation/screens/video_player/video_player_screen.dart`

---

## Suggested Improvements & Changes

### 1. **Multiple Stream Sources Support** (High Priority)
**Current:** Only one watch link is used
**Suggested:**
- Store multiple stream URLs per content (e.g., 4-5 sources)
- Add source selector UI (dropdown or swipe)
- Auto-try next source if current fails
- Show source name in player (e.g., "Streamtape", "Vidplay", "Doodstream")

### 2. **Download Queue Management** (High Priority)
**Current:** Downloads start immediately, limited control
**Suggested:**
- Add maximum concurrent downloads setting (default: 2)
- Priority queue (download what you click first)
- Download speed throttling option
- WiFi-only download toggle

### 3. **Better Video Player** (Medium Priority)
**Current:** InAppWebView with basic controls
**Suggested:**
- Integrate native video player (media_kit or video_player)
- Support more formats (MKV, AVI with subtitle support)
- Add subtitle selection (SRT, VTT from URLs)
- Playback speed control
- Picture-in-Picture mode
- Skip intro/outro markers

### 4. **Resume Playback Feature** (Medium Priority)
**Current:** No continue watching
**Suggested:**
- Track playback position in local database
- Show "Continue Watching" section on home screen
- Resume from last position when reopening

### 5. **Offline Detection & Caching** (Medium Priority)
**Current:** App requires internet
**Suggested:**
- Cache metadata for offline browsing
- Show offline indicator in UI
- Graceful error handling when offline

### 6. **Download Quality Selection** (Low Priority)
**Current:** Downloads whatever quality is in the URL
**Suggested:**
- If multiple qualities available (1080p, 720p, 480p), let user choose
- Store quality preference per download

### 7. **Auto-Download New Episodes** (Low Priority)
**Current:** Manual download only
**Suggested:**
- "Auto-download new episodes" toggle in series detail
- Download new episodes automatically when available

### 8. **Chromecast Support** (Low Priority)
- Cast button in video player
- Stream directly to TV

---

## Technical Implementation Notes

### Link Validation Logic
```dart
// Suspicious domains that are blocked
static final List<String> _suspiciousDomains = [
  'click', 'clk', 'ads', 'pop', 'banner', 'tracker', 'analytics',
  'doubleclick', 'googlesyndication', 'googleadservices',
  'adf', 'adb', 'traffic', 'visit'
];

// Allowed if:
// 1. Not containing suspicious domains
// 2. Our own domain (daniewatch)
// 3. Valid iframe src attribute
```

### Download File Naming
```
Format: "{title} S{season:02} E{episode:02}.{extension}"
Example: "Breaking Bad S01 E01.mp4"
         "Inception.mkv"
```

### Permissions Required
- **Android Storage**: For saving downloads
- **Internet**: For streaming and API calls

---

## Package Dependencies

| Package | Purpose |
|---------|---------|
| `supabase_flutter` | Backend database |
| `flutter_inappwebview` | WebView for streaming |
| `flutter_downloader` | Native download manager |
| `open_file` | Open downloaded files |
| `path_provider` | Get app directories |
| `permission_handler` | Request storage permissions |
| `shared_preferences` | Local key-value storage |
| `cached_network_image` | Image caching |
| `flutter_riverpod` | State management |

---

## File Structure Summary

```
lib/
├── data/
│   ├── clients/
│   │   ├── supabase_client.dart    # DB connection
│   │   └── tmdb_client.dart       # TMDB API
│   ├── local/
│   │   ├── database.dart          # Local DB (SQLite)
│   │   └── download_manager.dart  # Download handling ⭐
│   └── repositories/
│       └── content_repository.dart # Link extraction ⭐
├── domain/
│   └── models/
│       ├── content_detail.dart     # Data models
│       └── entry.dart              # Entry/Cast models
├── presentation/
│   ├── providers/
│   │   └── detail_provider.dart   # State management ⭐
│   └── screens/
│       ├── details/
│       │   └── details_screen.dart # Play/Download UI ⭐
│       ├── downloads/
│       │   └── downloads_screen.dart
│       └── video_player/
│           └── video_player_screen.dart  # Streaming ⭐
└── main.dart
```

---

## Conclusion

The app has a solid foundation for streaming and downloading content. The main areas for improvement are:
1. **Better stream source handling** (multiple sources, fallback)
2. **Enhanced download management** (queue, quality selection)
3. **Improved video player** (native player, subtitles)
4. **Resume playback** feature

These changes would significantly improve the user experience and make the app more competitive with other streaming apps.

