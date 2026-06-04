import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:developer' as developer;

/// Extracts streaming URLs using an InAppWebView-based approach:
/// intercept all loaded resources via `onLoadResource`, auto-click
/// play buttons, and discover .m3u8 links.
///
/// This is the single, unified extraction approach used by both
/// "Watch Online" and "Download" flows.
class VideoExtractorService {
  static final VideoExtractorService _instance =
      VideoExtractorService._internal();
  factory VideoExtractorService() => _instance;
  VideoExtractorService._internal();

  /// Cache TTL: 30 minutes (CDN tokens typically expire after ~1-2 hours)
  static const Duration _cacheTtl = Duration(minutes: 30);

  /// Extracts the best m3u8/mp4 URL from an embed page using a
  /// HeadlessInAppWebView that auto-clicks and intercepts resources.
  ///
  /// Returns the best discovered link, or null on timeout.
  Future<String?> extractVideoUrl(String embedUrl,
      {bool bypassCache = false}) async {
    // 1. Check cache
    final prefs = await SharedPreferences.getInstance();
    if (!bypassCache) {
      final cachedUrl = prefs.getString('extract_$embedUrl');
      final cachedTime = prefs.getInt('extract_ts_$embedUrl');
      if (cachedUrl != null && cachedTime != null) {
        final age = DateTime.now().millisecondsSinceEpoch - cachedTime;
        if (age < _cacheTtl.inMilliseconds) {
          developer.log('[Extractor] Cache hit (${age ~/ 1000}s old): $cachedUrl',
              name: 'Extractor');
          return cachedUrl;
        } else {
          developer.log('[Extractor] Cache expired, re-extracting...',
              name: 'Extractor');
          await prefs.remove('extract_$embedUrl');
          await prefs.remove('extract_ts_$embedUrl');
        }
      }
    }

    developer.log('[Extractor] Starting WebView extraction for: $embedUrl',
        name: 'Extractor');

    final completer = Completer<String?>();
    final Set<String> discoveredLinks = {};
    Timer? masterWaitTimer;
    Timer? autoClickTimer;
    Timer? absoluteTimer;
    bool discoveryComplete = false;
    HeadlessInAppWebView? headlessWebView;

    void completeDiscovery() {
      if (discoveryComplete) return;
      discoveryComplete = true;
      autoClickTimer?.cancel();
      absoluteTimer?.cancel();
      masterWaitTimer?.cancel();

      developer.log(
        '[Extractor] Analyzing ${discoveredLinks.length} discovered links...',
        name: 'Extractor',
      );

      String? bestLink;

      // 1. Prefer master playlists
      final masterLinks = discoveredLinks
          .where((l) => l.contains('master.m3u8') || l.contains('.urlset'))
          .toList();
      if (masterLinks.isNotEmpty) {
        masterLinks.sort((a, b) => b.length.compareTo(a.length));
        bestLink = masterLinks.first;
        developer.log('[Extractor] Selected MASTER: $bestLink',
            name: 'Extractor');
      }
      // 2. High quality variant
      else {
        final highQuality = discoveredLinks
            .where((l) =>
                l.contains('_h') || l.contains('1080') || l.contains('720'))
            .toList();
        if (highQuality.isNotEmpty) {
          highQuality.sort((a, b) => b.length.compareTo(a.length));
          bestLink = highQuality.first;
          developer.log('[Extractor] Selected HIGH QUALITY: $bestLink',
              name: 'Extractor');
        } else if (discoveredLinks.isNotEmpty) {
          bestLink = discoveredLinks.first;
          developer.log('[Extractor] Selected FALLBACK: $bestLink',
              name: 'Extractor');
        }
      }

      if (!completer.isCompleted) {
        completer.complete(bestLink);
      }
    }

    void handleExtractedLink(String link) {
      if (discoveryComplete) return;

      final lowerLink = link.toLowerCase();

      // Only process .m3u8 or .mp4 files
      if (!lowerLink.contains('.m3u8') && !lowerLink.contains('.mp4')) return;
      if (lowerLink.contains('ads')) return;

      if (!discoveredLinks.contains(link)) {
        developer.log('[Extractor] New link discovered: $link',
            name: 'Extractor');
        discoveredLinks.add(link);
      }

      if (lowerLink.contains('master.m3u8') || lowerLink.contains('.urlset')) {
        developer.log('[Extractor] Master found! Completing soon...',
            name: 'Extractor');
        masterWaitTimer?.cancel();
        masterWaitTimer = Timer(const Duration(milliseconds: 200), () {
          completeDiscovery();
        });
      } else if (masterWaitTimer == null) {
        // Found a fallback; wait 1.5s to see if master appears
        developer.log('[Extractor] Fallback found, waiting for master...',
            name: 'Extractor');
        masterWaitTimer = Timer(const Duration(milliseconds: 1500), () {
          completeDiscovery();
        });
      }
    }

    // Create headless WebView with tapping approach
    headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(embedUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        allowsInlineMediaPlayback: true,
        mediaPlaybackRequiresUserGesture: false,
        useShouldOverrideUrlLoading: true,
        useOnLoadResource: true, // Crucial for discovery
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: true,
        useShouldInterceptRequest: true,
      ),
      onWebViewCreated: (controller) {
        // Controller managed internally by HeadlessInAppWebView
      },
      onLoadStop: (controller, url) async {
        developer.log('[Extractor] Page loaded: $url', name: 'Extractor');

        // Start the 5-click sequence after load
        for (int i = 1; i <= 5; i++) {
          if (discoveryComplete) break;

          developer.log('[Extractor] Click sequence $i/5...',
              name: 'Extractor');

          try {
            await controller.evaluateJavascript(source: """
              (function() {
                // 1. Close any visible overlays/popups
                var overlays = document.querySelectorAll('[class*="popup"], [class*="modal"], [id*="popup"], [id*="modal"], [class*="overlay"], [class*="close"]');
                overlays.forEach(function(el) { 
                  if (el.offsetWidth > 0 || el.offsetHeight > 0) el.remove(); 
                });

                // 2. Click the center (where player usually is)
                var x = window.innerWidth / 2;
                var y = window.innerHeight / 2;
                var el = document.elementFromPoint(x, y);
                if (el) {
                  el.click();
                  console.log('Antigravity: Clicked at center (' + x + ',' + y + ')');
                }

                // 3. Also try clicking common play buttons
                var playBtns = document.querySelectorAll('.play-btn, .vjs-big-play-button, .jw-display-icon-display, .plyr__control--overlaid, [class*="play"], button[aria-label*="play"], button[aria-label*="Play"]');
                playBtns.forEach(function(b) { b.click(); });

                // 4. Try triggering video.play() directly
                var v = document.querySelector('video');
                if (v) { v.play().catch(function(e){}); }
              })();
            """);
          } catch (e) {
            developer.log(
              '[Extractor] Click sequence $i failed: $e',
              name: 'Extractor',
            );
          }

          // Wait between clicks to allow for popups to trigger and be handled
          await Future.delayed(const Duration(milliseconds: 800));
        }
      },
      onCreateWindow: (controller, createWindowAction) async {
        developer.log(
          '[Extractor] Popup blocked: ${createWindowAction.request.url}',
          name: 'Extractor',
        );
        // Returning true without creating a window blocks it
        return true;
      },
      onLoadResource: (controller, resource) {
        if (resource.url != null) {
          handleExtractedLink(resource.url.toString());
        }
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url.toString();
        final isMainFrame = navigationAction.isForMainFrame;

        // Block non-main-frame redirects and common ad domains
        if (!isMainFrame ||
            url.contains('google-analytics') ||
            url.contains('doubleclick') ||
            url.contains('ads') ||
            url.contains('popad') ||
            url.contains('onclick') ||
            url.contains('popunder') ||
            url.contains('tracker')) {
          developer.log('[Extractor] Blocking redirect/resource: $url',
              name: 'Extractor');
          return NavigationActionPolicy.CANCEL;
        }

        // If it's a main frame redirect but looks like an ad or popunder, block it
        if (isMainFrame &&
            url != embedUrl &&
            !url.contains(Uri.parse(embedUrl).host)) {
          developer.log('[Extractor] Blocking potential popup redirect: $url',
              name: 'Extractor');
          return NavigationActionPolicy.CANCEL;
        }

        return NavigationActionPolicy.ALLOW;
      },
      onConsoleMessage: (controller, consoleMessage) {
        developer.log(
          '[Extractor] Console: ${consoleMessage.message}',
          name: 'Extractor',
        );
      },
    );

    headlessWebView.run();

    // Absolute timeout: 20 seconds
    absoluteTimer = Timer(const Duration(seconds: 20), () {
      if (!discoveryComplete) {
        developer.log('[Extractor] Absolute timeout reached (20s).',
            name: 'Extractor');
        completeDiscovery();
      }
    });

    // Wait for result
    try {
      final result = await completer.future;
      if (result != null) {
        await prefs.setString('extract_$embedUrl', result);
        await prefs.setInt(
            'extract_ts_$embedUrl', DateTime.now().millisecondsSinceEpoch);
      }
      return result;
    } finally {
      autoClickTimer?.cancel();
      absoluteTimer?.cancel();
      masterWaitTimer?.cancel();
      headlessWebView.dispose();
    }
  }

  /// Fetches the file size of a video URL using an HTTP HEAD request.
  /// Tries the embed page's download API first (for bysebuho-style sites),
  /// then falls back to HEAD request on the m3u8/mp4 URL.
  /// Returns file size in bytes, or null if unavailable.
  static Future<int?> fetchFileSize(String? m3u8Url) async {
    if (m3u8Url == null || m3u8Url.isEmpty) return null;

    try {
      // Try HTTP HEAD to get Content-Length
      final response = await http.head(
        Uri.parse(m3u8Url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13; SM-G981B) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36',
        },
      ).timeout(const Duration(seconds: 5));

      final contentLength = response.headers['content-length'];
      if (contentLength != null) {
        final size = int.tryParse(contentLength);
        if (size != null && size > 0) {
          developer.log('[Extractor] File size from HEAD: $size bytes',
              name: 'Extractor');
          return size;
        }
      }
    } catch (e) {
      developer.log('[Extractor] File size fetch failed: $e',
          name: 'Extractor');
    }
    return null;
  }
}
