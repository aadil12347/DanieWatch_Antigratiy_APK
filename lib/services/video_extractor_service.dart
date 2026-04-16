import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;
import 'bysebuho_extractor.dart';

/// Extracts streaming URLs using the same InAppWebView-based approach
/// as the video player screen: intercept all loaded resources via
/// `onLoadResource`, auto-click play buttons, and discover .m3u8 links.
///
/// This replaces the old headless-only approach that looked for <video> src,
/// which failed on many embed pages.
class VideoExtractorService {
  static final VideoExtractorService _instance =
      VideoExtractorService._internal();
  factory VideoExtractorService() => _instance;
  VideoExtractorService._internal();

  /// Uses an off-screen InAppWebView widget approach identical to the player.
  /// Returns the best discovered m3u8/mp4 link, or null on timeout.
  ///
  /// This implements a 4-click sequence to trigger HLS link generation
  /// while handling/blocking pop-ups and redirects.
  Future<String?> extractVideoUrl(String embedUrl,
      {bool bypassCache = false}) async {
    // 1. Check cache
    final prefs = await SharedPreferences.getInstance();
    if (!bypassCache) {
      final cachedUrl = prefs.getString('extract_$embedUrl');
      if (cachedUrl != null) {
        developer.log('[Extractor] Found cached URL: $cachedUrl',
            name: 'Extractor');
        return cachedUrl;
      }
    }

    // 2. Try direct Bysebuho API extraction first (much faster ~1-2s)
    final bysebuho = BysebuhoExtractor.instance;
    if (bysebuho.isBysebuhoUrl(embedUrl)) {
      developer.log('[Extractor] Trying direct Bysebuho API extraction...',
          name: 'Extractor');
      final result = await bysebuho.extract(embedUrl, bypassCache: bypassCache);
      if (result != null) {
        developer.log('[Extractor] ✅ Direct extraction succeeded! Master: ${result.masterUrl}',
            name: 'Extractor');
        // Cache under the embed URL key too for compatibility
        await prefs.setString('extract_$embedUrl', result.masterUrl);
        return result.masterUrl;
      }
      developer.log('[Extractor] Direct extraction failed, falling back to WebView...',
          name: 'Extractor');
    }

    developer.log('[Extractor] Starting WebView extraction for: $embedUrl',
        name: 'Extractor');

    final completer = Completer<String?>();
    final Set<String> discoveredLinks = {};
    Timer? masterWaitTimer;
    Timer? autoClickTimer;
    Timer? absoluteTimer;
    bool discoveryComplete = false;
    InAppWebViewController? webViewController;
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

    // Create headless WebView with same settings as the player
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
        webViewController = controller;
      },
      onLoadStop: (controller, url) async {
        developer.log('[Extractor] Page loaded: $url', name: 'Extractor');

        // Start the 4-click sequence after load
        for (int i = 1; i <= 4; i++) {
          if (discoveryComplete) break;

          developer.log('[Extractor] Click sequence $i/4...',
              name: 'Extractor');

          try {
            await controller.evaluateJavascript(source: """
              (function() {
                // 1. Close any visible overlays/popups if possible
                var overlays = document.querySelectorAll('[class*="popup"], [class*="modal"], [id*="popup"], [id*="modal"]');
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
                var playBtns = document.querySelectorAll('.play-btn, .vjs-big-play-button, .jw-display-icon-display, .plyr__control--overlaid');
                playBtns.forEach(function(b) { b.click(); });
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
            url.contains('onclick')) {
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

    // Absolute timeout: 12 seconds (reduced since direct extraction handles most cases)
    absoluteTimer = Timer(const Duration(seconds: 12), () {
      if (!discoveryComplete) {
        developer.log('[Extractor] Absolute timeout reached.',
            name: 'Extractor');
        completeDiscovery();
      }
    });

    // Wait for result
    try {
      final result = await completer.future;
      if (result != null) {
        await prefs.setString('extract_$embedUrl', result);
      }
      return result;
    } finally {
      autoClickTimer?.cancel();
      absoluteTimer.cancel();
      masterWaitTimer?.cancel();
      headlessWebView.dispose();
    }
  }
}
