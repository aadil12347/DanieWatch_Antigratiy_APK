import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
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
}

class VideasyExtractorService {
  static final VideasyExtractorService _instance = VideasyExtractorService._internal();
  factory VideasyExtractorService() => _instance;
  VideasyExtractorService._internal();

  /// Map of { "Server Name": ExtractedVideasyStream }
  Future<Map<String, ExtractedVideasyStream>?> extractAllStreams(String embedUrl) async {
    developer.log('[VideasyExtractor] Starting extraction for: $embedUrl', name: 'Videasy');
    
    final completer = Completer<Map<String, ExtractedVideasyStream>?>();
    HeadlessInAppWebView? headlessWebView;
    Timer? absoluteTimer;
    bool completed = false;

    // We inject a script that intercepts fetch requests
    final String networkHookJS = """
      (function() {
        console.log('[VideasyHook] Injecting fetch interceptor');
        var originalFetch = window.fetch;
        window.extractedStreams = {};
        
        window.fetch = async function() {
          var url = arguments[0];
          
          if (typeof url === 'string' && url.includes('api.videasy.net') && url.includes('sources-with-title')) {
            console.log('[VideasyHook] Intercepted API call to: ' + url);
            
            // Extract the server name from the URL path, e.g., /mb-flix/
            var serverName = 'Default';
            var match = url.match(/api\\.videasy\\.net\\/([^\\/]+)\\//);
            if (match && match[1]) {
              serverName = match[1];
            }

            try {
              var response = await originalFetch.apply(this, arguments);
              var clone = response.clone();
              var data = await clone.json();
              
              if (data && data.sources && data.sources.length > 0) {
                var m3u8Url = data.sources[0].url;
                if (m3u8Url) {
                  console.log('[VideasyHook] Found stream for ' + serverName + ': ' + m3u8Url);
                  window.extractedStreams[serverName] = m3u8Url;
                  
                  // Notify Flutter
                  window.flutter_inappwebview.callHandler('StreamIntercepted', JSON.stringify({
                    server: serverName,
                    url: m3u8Url,
                    sources: data.sources,
                    tracks: data.tracks || [],
                    allStreams: window.extractedStreams
                  }));
                }
              }
              return response;
            } catch (e) {
              console.error('[VideasyHook] Fetch error:', e);
              return originalFetch.apply(this, arguments);
            }
          }
          return originalFetch.apply(this, arguments);
        };
      })();
    """;

    // Script to find and click all server buttons concurrently
    final String autoClickerJS = """
      (function() {
        console.log('[VideasyHook] Starting auto-clicker...');
        
        // 1. Clear overlays
        var overlays = document.querySelectorAll('[class*="popup"], [class*="modal"], [id*="popup"], [id*="modal"], [class*="overlay"], [class*="close"]');
        overlays.forEach(function(el) { 
          if (el.offsetWidth > 0 || el.offsetHeight > 0) el.remove(); 
        });

        // 2. Click center to trigger initial play
        var x = window.innerWidth / 2;
        var y = window.innerHeight / 2;
        var el = document.elementFromPoint(x, y);
        if (el) {
          el.click();
        }

        // Wait a moment for UI to build, then click all server buttons
        setTimeout(function() {
          // Look for server buttons (typically inside a dropdown or server list)
          // We will click anything that looks like a server or play button
          var buttons = document.querySelectorAll('button, .server, .source');
          buttons.forEach(function(btn) {
             btn.click();
          });
        }, 2000);
      })();
    """;

    final Map<String, ExtractedVideasyStream> finalStreams = {};

    headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(embedUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        allowsInlineMediaPlayback: true,
        mediaPlaybackRequiresUserGesture: false,
        useShouldOverrideUrlLoading: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: true,
      ),
      onWebViewCreated: (controller) async {
        controller.addJavaScriptHandler(
          handlerName: 'StreamIntercepted',
          callback: (args) {
            if (completed) return;
            try {
              final payload = jsonDecode(args[0] as String);
              final server = payload['server'] as String;
              final url = payload['url'] as String;
              final sources = payload['sources'] as List<dynamic>? ?? [];
              final tracks = payload['tracks'] as List<dynamic>? ?? [];
              
              finalStreams[server] = ExtractedVideasyStream(
                server: server,
                url: url,
                sources: sources,
                tracks: tracks,
              );
              
              developer.log('[VideasyExtractor] Captured $server: $url with ${tracks.length} tracks', name: 'Videasy');
              
              // We could complete immediately, or wait a bit to collect more.
              // Let's complete after 1.5 seconds of receiving the first one to allow others to resolve
              if (!completer.isCompleted) {
                 Timer(const Duration(milliseconds: 1500), () {
                    if (!completed) {
                      completed = true;
                      completer.complete(finalStreams);
                    }
                 });
              }
            } catch (e) {
              developer.log('[VideasyExtractor] Error parsing payload: $e', name: 'Videasy');
            }
          },
        );
      },
      onLoadStart: (controller, url) async {
        await controller.evaluateJavascript(source: networkHookJS);
      },
      onLoadStop: (controller, url) async {
        developer.log('[VideasyExtractor] Page loaded: $url', name: 'Videasy');
        await controller.evaluateJavascript(source: networkHookJS);
        await controller.evaluateJavascript(source: autoClickerJS);
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url.toString();
        final isMainFrame = navigationAction.isForMainFrame;

        // Block popups and ads
        if (!isMainFrame || !url.contains(Uri.parse(embedUrl).host)) {
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onCreateWindow: (controller, createWindowAction) async {
        return true; // Block popup windows
      },
      onConsoleMessage: (controller, consoleMessage) {
        developer.log('[VideasyExtractor] Console: ${consoleMessage.message}', name: 'Videasy');
      },
    );

    await headlessWebView.run();

    // Absolute timeout of 15 seconds
    absoluteTimer = Timer(const Duration(seconds: 15), () {
      if (!completed) {
        completed = true;
        developer.log('[VideasyExtractor] Timeout reached. Streams found: \${finalStreams.length}', name: 'Videasy');
        completer.complete(finalStreams.isEmpty ? null : finalStreams);
      }
    });

    try {
      final result = await completer.future;
      return result;
    } finally {
      absoluteTimer?.cancel();
      headlessWebView.dispose();
    }
  }
}
