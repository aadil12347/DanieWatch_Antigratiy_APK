import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ExtractedVideasyStream {
  final String server;
  final String url;
  final List<dynamic> sources;
  final List<dynamic> tracks;

  ExtractedVideasyStream({
    required this.server,
    required this.url,
    required this.sources,
    required this.tracks,
  });

  @override
  String toString() => 'ExtractedVideasyStream(server: $server, url: $url, sources: ${sources.length}, tracks: ${tracks.length})';
}

class VideasyExtractorService {
  static final VideasyExtractorService _instance = VideasyExtractorService._internal();
  factory VideasyExtractorService() => _instance;
  VideasyExtractorService._internal();

  /// Extracts the Fade Hindi stream from Videasy player.
  /// Returns a map with a single entry: { "Fade Hindi": ExtractedVideasyStream }
  /// or the first available server if Fade Hindi is not found.
  Future<Map<String, ExtractedVideasyStream>?> extractAllStreams(String embedUrl) async {
    developer.log('[VideasyExtractor] Starting Fade Hindi extraction for: $embedUrl', name: 'Videasy');
    
    final completer = Completer<Map<String, ExtractedVideasyStream>?>();
    HeadlessInAppWebView? headlessWebView;
    Timer? absoluteTimer;
    Timer? settleTimer;
    bool completed = false;

    final Map<String, ExtractedVideasyStream> finalStreams = {};

    // ── JavaScript: Hook JSON.parse to intercept decrypted stream payloads ──
    // The Videasy player decrypts an encrypted blob into a JSON object containing
    // { sources: [{url: "https://...master.m3u8", type: "hls"}], tracks: [...] }
    // We intercept this at the JSON.parse level to capture it instantly.
    final String hookJS = """
      (function() {
        if (window.__videasyHookInjected) return;
        window.__videasyHookInjected = true;
        
        console.log('[VideasyHook] Injecting JSON.parse interceptor for Fade Hindi');
        
        var originalParse = JSON.parse;
        window.__capturedStreams = [];
        window.__currentServerName = 'Default';
        
        JSON.parse = function(text, reviver) {
          var result = originalParse(text, reviver);
          try {
            // The decrypted payload has a 'sources' array with m3u8/mp4 URLs
            if (result && result.sources && Array.isArray(result.sources) && result.sources.length > 0) {
              var source = result.sources[0];
              var streamUrl = source.url || source.file;
              
              if (streamUrl && (streamUrl.includes('.m3u8') || streamUrl.includes('.mp4'))) {
                console.log('[VideasyHook] ✅ Intercepted stream: ' + streamUrl);
                console.log('[VideasyHook] Server context: ' + window.__currentServerName);
                
                window.__capturedStreams.push({
                  server: window.__currentServerName,
                  url: streamUrl,
                  sources: result.sources,
                  tracks: result.tracks || []
                });
                
                window.flutter_inappwebview.callHandler('StreamIntercepted', JSON.stringify({
                  server: window.__currentServerName,
                  url: streamUrl,
                  sources: result.sources,
                  tracks: result.tracks || []
                }));
              }
            }
          } catch(e) {
            console.error('[VideasyHook] Parse hook error:', e);
          }
          return result;
        };
        
        // Backup: Intercept fetch calls to .m3u8 URLs
        var originalFetch = window.fetch;
        window.fetch = async function() {
          var url = arguments[0];
          if (typeof url === 'string' && url.includes('.m3u8')) {
            console.log('[VideasyHook] 🔗 Fetch intercepted m3u8: ' + url);
            window.flutter_inappwebview.callHandler('StreamIntercepted', JSON.stringify({
              server: window.__currentServerName || 'Direct',
              url: url,
              sources: [{url: url, type: 'hls'}],
              tracks: []
            }));
          }
          return originalFetch.apply(this, arguments);
        };
      })();
    """;

    // ── JavaScript: Auto-click sequence to navigate to Fade Hindi server ──
    // The Videasy player UI structure (from HAR/click analysis):
    //   1. Settings gear button: button.tabbable.p-2.rounded-full
    //   2. Server list items: span.font-medium.truncate (contains server name text)
    //   3. Resolution buttons: button.w-full.flex.items-center.justify-between.p-3
    final String fadeClickerJS = """
      (function() {
        if (window.__fadeClickerStarted) return;
        window.__fadeClickerStarted = true;
        
        console.log('[FadeClicker] Starting Fade Hindi auto-click sequence...');
        
        var clickAttempt = 0;
        var maxAttempts = 20;
        var state = 0;
        
        var doClick = function() {
          clickAttempt++;
          if (clickAttempt > maxAttempts || state >= 4) return;
          
          try {
            if (state === 0) {
              // 1. Click the big initial play overlay button
              var playOverlay = document.querySelector('button.w-10.h-10.sm\\\\:w-12, button.rounded-full.bg-white\\\\/95');
              if (playOverlay) {
                  playOverlay.click();
                  console.log('[FadeClicker] Clicked Play Overlay');
              }
              // Move to settings step regardless (sometimes it auto-plays)
              state = 1;
            }
            
            if (state === 1) {
              // 2. Click the settings gear icon (the one containing SVG paths)
              var settingsBtn = document.querySelector('button.tabbable.p-2.rounded-full');
              if (settingsBtn) {
                  settingsBtn.click();
                  console.log('[FadeClicker] Clicked Settings Gear');
                  state = 2;
              } else {
                  // Fallback to clicking center if video hasn't appeared
                  var v = document.querySelector('video');
                  if (!v) {
                      var el = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
                      if (el) el.click();
                  }
              }
            } else if (state === 2) {
              // 3. Click the Server/Language item
              var serverItems = document.querySelectorAll('span.font-medium.truncate, p.text-xs.text-gray-500.truncate, li, [role="menuitem"], button.w-full');
              
              var foundFade = false;
              for (var i = 0; i < serverItems.length; i++) {
                var text = serverItems[i].innerText ? serverItems[i].innerText.toLowerCase().trim() : '';
                
                if (text.includes('fade') || text.includes('hindi') || text.includes('hdmovie')) {
                  window.__currentServerName = serverItems[i].innerText.trim();
                  
                  try {
                    serverItems[i].click();
                    foundFade = true;
                    state = 4; // We just need the server change, the fetch interceptor will catch the m3u8!
                    console.log('[FadeClicker] ✅ Clicked Fade Hindi server: ' + text);
                  } catch(e) {}
                  break;
                }
              }
              
              if (!foundFade) {
                // We might be in the main settings menu and need to click "Servers" to open the sub-menu
                for (var i = 0; i < serverItems.length; i++) {
                  var text = serverItems[i].innerText ? serverItems[i].innerText.toLowerCase().trim() : '';
                  if (text === 'servers' || text === 'languages' || text === 'server') {
                    try { serverItems[i].click(); } catch(e) {}
                    console.log('[FadeClicker] Clicked "' + text + '" category');
                    break; // Wait for next tick to click the actual server
                  }
                }
              }
            }
          } catch(e) {
            console.error('[FadeClicker] Error:', e);
          }
          
          if (state < 4) {
            setTimeout(doClick, 800);
          }
        };
        
        // Start after a short delay
        setTimeout(doClick, 1000);
      })();
    """;

    headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(embedUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        },
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        allowsInlineMediaPlayback: true,
        mediaPlaybackRequiresUserGesture: false,
        useShouldOverrideUrlLoading: true,
        domStorageEnabled: true,
      ),
      onWebViewCreated: (controller) async {
        controller.addJavaScriptHandler(
          handlerName: 'StreamIntercepted',
          callback: (args) {
            if (completed) return;
            try {
              final payload = jsonDecode(args[0] as String);
              final server = payload['server'] as String? ?? 'Fade Hindi';
              final url = payload['url'] as String;
              final sources = payload['sources'] as List<dynamic>? ?? [];
              final tracks = payload['tracks'] as List<dynamic>? ?? [];
              
              finalStreams[server] = ExtractedVideasyStream(
                server: server,
                url: url,
                sources: sources,
                tracks: tracks,
              );
              
              developer.log('[VideasyExtractor] ✅ Captured $server: $url', name: 'Videasy');
              developer.log('[VideasyExtractor]    Sources: ${sources.length}, Tracks: ${tracks.length}', name: 'Videasy');
              
              // Wait 500ms for any additional data, then complete
              settleTimer?.cancel();
              settleTimer = Timer(const Duration(milliseconds: 500), () {
                if (!completed) {
                  completed = true;
                  if (!completer.isCompleted) {
                    completer.complete(finalStreams);
                  }
                }
              });
            } catch (e) {
              developer.log('[VideasyExtractor] Error parsing payload: $e', name: 'Videasy');
            }
          },
        );
      },
      onLoadStart: (controller, url) async {
        // Inject hooks as early as possible
        await controller.evaluateJavascript(source: hookJS);
      },
      onLoadStop: (controller, url) async {
        // Re-inject hooks and start the Fade Hindi auto-clicker
        await controller.evaluateJavascript(source: hookJS);
        await controller.evaluateJavascript(source: fadeClickerJS);
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url.toString();
        // Block navigation away from videasy
        if (navigationAction.isForMainFrame && !url.contains('videasy.net')) {
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onCreateWindow: (controller, createWindowAction) async {
        // Block popups
        return false;
      },
      onConsoleMessage: (controller, consoleMessage) {
        if (kDebugMode) {
          developer.log('[VideasyExtractor] Console: ${consoleMessage.message}', name: 'Videasy');
        }
      },
    );

    await headlessWebView.run();

    // Absolute timeout: 12 seconds
    absoluteTimer = Timer(const Duration(seconds: 12), () {
      if (!completed) {
        completed = true;
        developer.log(
          '[VideasyExtractor] Timeout reached. Streams found: ${finalStreams.length}',
          name: 'Videasy',
        );
        if (!completer.isCompleted) {
          completer.complete(finalStreams.isEmpty ? null : finalStreams);
        }
      }
    });

    try {
      final result = await completer.future;
      return result;
    } finally {
      absoluteTimer?.cancel();
      settleTimer?.cancel();
      headlessWebView.dispose();
    }
  }
}
