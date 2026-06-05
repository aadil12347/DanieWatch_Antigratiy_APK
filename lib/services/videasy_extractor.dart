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

    // We inject a script that hooks JSON.parse to catch the decrypted payload instantly
    final String hookJS = """
      (function() {
        console.log('[VideasyHook] Injecting JSON.parse interceptor');
        var originalParse = JSON.parse;
        window.extractedStreams = {};
        
        JSON.parse = function(text, reviver) {
          var result = originalParse(text, reviver);
          try {
            // The decrypted payload usually contains 'sources' array
            if (result && result.sources && Array.isArray(result.sources) && result.sources.length > 0) {
              var source = result.sources[0];
              var m3u8Url = source.url || source.file;
              
              if (m3u8Url && m3u8Url.includes('.m3u8')) {
                console.log('[VideasyHook] Intercepted decrypted stream: ' + m3u8Url);
                
                // We don't have the exact server name easily here, but we can default it
                var serverName = 'Default';
                window.extractedStreams[serverName] = m3u8Url;
                
                window.flutter_inappwebview.callHandler('StreamIntercepted', JSON.stringify({
                  server: serverName,
                  url: m3u8Url,
                  sources: result.sources,
                  tracks: result.tracks || [],
                  allStreams: window.extractedStreams
                }));
              }
            }
          } catch(e) {
            console.error('[VideasyHook] Parse hook error:', e);
          }
          return result;
        };
        
        // Backup: Intercept network requests to .m3u8 directly just in case JSON.parse hook misses
        var originalFetch = window.fetch;
        window.fetch = async function() {
          var url = arguments[0];
          if (typeof url === 'string' && url.includes('.m3u8')) {
             window.flutter_inappwebview.callHandler('StreamIntercepted', JSON.stringify({
                  server: 'Default (Direct)',
                  url: url,
                  sources: [{url: url, type: 'hls'}],
                  tracks: [],
                  allStreams: window.extractedStreams
             }));
          }
          return originalFetch.apply(this, arguments);
        };
      })();
    """;

    // Auto clicker just in case it needs interaction to start decrypting
    final String autoClickerJS = """
      (function() {
        console.log('[VideasyHook] Starting auto-clicker...');
        var x = window.innerWidth / 2;
        var y = window.innerHeight / 2;
        var el = document.elementFromPoint(x, y);
        if (el) el.click();

        setTimeout(function() {
          var buttons = document.querySelectorAll('button, .server, .source, .play-btn');
          buttons.forEach(function(btn) { btn.click(); });
        }, 1000);
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
              
              developer.log('[VideasyExtractor] Captured $server: $url', name: 'Videasy');
              
              // Resolve extremely fast (500ms) after finding first valid stream
              if (!completer.isCompleted) {
                 Timer(const Duration(milliseconds: 500), () {
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
        await controller.evaluateJavascript(source: hookJS);
      },
      onLoadStop: (controller, url) async {
        await controller.evaluateJavascript(source: hookJS);
        await controller.evaluateJavascript(source: autoClickerJS);
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url.toString();
        if (!navigationAction.isForMainFrame || !url.contains(Uri.parse(embedUrl).host)) {
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onConsoleMessage: (controller, consoleMessage) {
        developer.log('[VideasyExtractor] Console: ${consoleMessage.message}', name: 'Videasy');
      },
    );

    await headlessWebView.run();

    // Reduced timeout to 8 seconds
    absoluteTimer = Timer(const Duration(seconds: 8), () {
      if (!completed) {
        completed = true;
        developer.log('[VideasyExtractor] Timeout reached. Streams found: ${finalStreams.length}', name: 'Videasy');
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
