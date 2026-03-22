import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;

/// Extracts streaming URLs using the same InAppWebView-based approach
/// as the video player screen: intercept all loaded resources via
/// `onLoadResource`, auto-click play buttons, and discover .m3u8 links.
///
/// This replaces the old headless-only approach that looked for <video> src,
/// which failed on many embed pages.
class VideoExtractorService {
  static final VideoExtractorService _instance = VideoExtractorService._internal();
  factory VideoExtractorService() => _instance;
  VideoExtractorService._internal();

  /// Extract a streaming URL from the given embed/watch URL.
  ///
  /// Uses an off-screen InAppWebView widget approach identical to the player.
  /// Returns the best discovered m3u8/mp4 link, or null on timeout.
  ///
  /// [context] is used to insert an overlay WebView for extraction.
  /// If you cannot provide a context (e.g. background), use
  /// [extractVideoUrlHeadless] below.
  Future<String?> extractVideoUrl(String embedUrl) async {
    // 1. Check cache
    final prefs = await SharedPreferences.getInstance();
    final cachedUrl = prefs.getString('extract_$embedUrl');
    if (cachedUrl != null) {
      developer.log('[Extractor] Found cached URL: $cachedUrl', name: 'Extractor');
      return cachedUrl;
    }

    developer.log('[Extractor] Starting WebView extraction for: $embedUrl', name: 'Extractor');

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
        developer.log('[Extractor] Selected MASTER: $bestLink', name: 'Extractor');
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
          developer.log('[Extractor] Selected HIGH QUALITY: $bestLink', name: 'Extractor');
        } else if (discoveredLinks.isNotEmpty) {
          bestLink = discoveredLinks.first;
          developer.log('[Extractor] Selected FALLBACK: $bestLink', name: 'Extractor');
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
        developer.log('[Extractor] New link discovered: $link', name: 'Extractor');
        discoveredLinks.add(link);
      }

      if (lowerLink.contains('master.m3u8') || lowerLink.contains('.urlset')) {
        developer.log('[Extractor] Master found! Completing soon...', name: 'Extractor');
        masterWaitTimer?.cancel();
        masterWaitTimer = Timer(const Duration(milliseconds: 200), () {
          completeDiscovery();
        });
      } else if (masterWaitTimer == null) {
        // Found a fallback; wait 3s to see if master appears
        developer.log('[Extractor] Fallback found, waiting for master...', name: 'Extractor');
        masterWaitTimer = Timer(const Duration(seconds: 3), () {
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
      ),
      onWebViewCreated: (controller) {
        webViewController = controller;
      },
      onCreateWindow: (controller, createWindowAction) async {
        developer.log(
          '[Extractor] Popup blocked: ${createWindowAction.request.url}',
          name: 'Extractor',
        );
        return true; // Block popups
      },
      onLoadResource: (controller, resource) {
        if (resource.url != null) {
          handleExtractedLink(resource.url.toString());
        }
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url.toString();
        final isMainFrame = navigationAction.isForMainFrame;

        if (!isMainFrame &&
            (url.contains('google-analytics') ||
                url.contains('doubleclick') ||
                url.contains('ads'))) {
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

    // Auto-click play buttons every 1.5 seconds (same as player)
    autoClickTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (discoveryComplete) {
        timer.cancel();
        return;
      }
      final controller = webViewController;
      if (controller != null) {
        try {
          controller.evaluateJavascript(
            source: """
            (function() {
              var buttons = document.querySelectorAll('.play-btn, .vjs-big-play-button, .jw-display-icon-display, .plyr__control--overlaid');
              for(var i=0; i<buttons.length; i++) {
                buttons[i].click();
              }
              var el = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
              if (el) {
                el.click();
                console.log('Antigravity: Auto-clicked element at center.');
              }
              var v = document.querySelector('video');
              if (v) { v.play().catch(function(e){}); }
            })();
          """,
          ).catchError((e) {
            // ignore disposed errors
          });
        } catch (e) {
          // ignore
        }
      }
    });

    // Absolute timeout: 20 seconds (give it enough time)
    absoluteTimer = Timer(const Duration(seconds: 20), () {
      if (!discoveryComplete) {
        developer.log('[Extractor] Absolute timeout reached.', name: 'Extractor');
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
      absoluteTimer?.cancel();
      masterWaitTimer?.cancel();
      headlessWebView?.dispose();
    }
  }
}
