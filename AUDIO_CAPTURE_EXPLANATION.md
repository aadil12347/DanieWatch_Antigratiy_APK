# How Different Audio Streams are Captured

This document explains the technical implementation used to capture multiple audio streams and video qualities from online stream links (HLS/M3U8) within the Daniewatch app.

## 1. The Core Technology: HLS (HTTP Live Streaming)

Most modern streaming sites use **HLS**, where the video isn't a single file, but a collection of playlists.

### The Master Playlist (`master.m3u8`)
The key is the "Master Playlist". Unlike a direct video link, a Master Playlist acts as a map. It contains:
- **Video Qualities**: `EXT-X-STREAM-INF` tags defining different resolutions (1080p, 720p, etc.).
- **Audio Tracks**: `EXT-X-MEDIA:TYPE=AUDIO` tags defining different languages (English, Hindi, etc.).
- **Subtitles**: `EXT-X-MEDIA:TYPE=SUBTITLES` tags defining subtitle tracks.

## 2. Extraction Logic: Resource Interception

Because the streaming sites are often protected by ads and complex JavaScript, we don't just "scrape" the HTML. Instead, we use a technique called **Resource Interception**.

### How it works in Daniewatch:
1. **WebView Injection**: The app loads the movie link in a hidden `InAppWebView`.
2. **Monitoring Network Traffic**: While the site loads, the app monitors every single network request the browser makes using the `onLoadResource` listener.
3. **Filtering for M3U8**: The app looks for any URL containing `.m3u8`.
4. **Identifying the Master**: Once a link containing `master.m3u8` is spotted, the app "captures" it. This link is the "Holy Grail" because it contains all the different versions of the video and audio.

## 3. Playback & Selection: BetterPlayer ASMS

Once we have the `master.m3u8` link, we hand it over to the **BetterPlayer** engine with specific configurations:

```dart
useAsmsAudioTracks: true,
useAsmsTracks: true,
useAsmsSubtitles: true,
```

### ASMS (Adaptive Streaming Management System)
When these flags are enabled, BetterPlayer doesn't just play the video; it parses the internal structure of the `master.m3u8` file:
- It automatically creates a list of **Audio Tracks** based on the `LANG` attribute in the playlist.
- It automatically creates a list of **Video Qualities**.
- It allows the user to switch between them seamlessly during playback.

## 4. The "Popup" Trigger Strategy

To make the transition feel smooth, we use a "Popup Interception" strategy:
- Most sites require a user click to start the video. That click usually triggers an ad.
- The app **intercepts and blocks** that ad popup (`onCreateWindow`).
- This block signal tells the app: *"The user just tried to play the video. Switch to the native player now!"*
- The app then transitions from the WebView to the `BetterPlayer` UI immediately using the best captured link.

## Summary of the Flow
1. **User selects a movie** -> WebView opens.
2. **WebView loads site** -> App intercepts headers/resources.
3. **`master.m3u8` found** -> Stored in memory.
4. **User clicks "Play"** -> Ad popup blocked -> App switches to native Player.
5. **Native Player starts** -> BetterPlayer parses `master.m3u8` -> Multi-audio and resolutions appear in Settings.
