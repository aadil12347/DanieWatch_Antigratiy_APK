import 'dart:async';
import 'dart:collection';
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

  /// The hook script that:
  /// 1. Intercepts JSON.parse to capture decrypted stream payloads
  /// 2. Redirects fetch() from mb-flix → hdmovie for Hindi/Fade server
  /// 3. Redirects XMLHttpRequest from mb-flix → hdmovie
  ///
  /// MUST be injected at DOCUMENT_START (before any page JS runs)
  static const String _hookScript = """
    (function() {
      if (window.__videasyHookInjected) return;
      window.__videasyHookInjected = true;
      
      // 1. Hook JSON.parse to capture decrypted stream payloads
      var originalParse = JSON.parse;
      JSON.parse = function(text, reviver) {
        var result = originalParse(text, reviver);
        try {
          if (result && result.sources && Array.isArray(result.sources) && result.sources.length > 0) {
            var source = result.sources[0];
            var streamUrl = source.url || source.file;
            
            if (streamUrl && (streamUrl.includes('.m3u8') || streamUrl.includes('.mp4'))) {
              console.log('[VideasyHook] CAPTURED stream: ' + streamUrl);
              
              try {
                window.flutter_inappwebview.callHandler('StreamIntercepted', JSON.stringify({
                  server: 'Fade Hindi',
                  url: streamUrl,
                  sources: result.sources,
                  tracks: result.tracks || []
                }));
              } catch(e) {
                // Handler may not be ready yet, store for later
                window.__pendingStream = {
                  server: 'Fade Hindi',
                  url: streamUrl,
                  sources: result.sources,
                  tracks: result.tracks || []
                };
              }
            }
          }
        } catch(e) {}
        return result;
      };
      
      // 2. Intercept fetch() to redirect mb-flix -> hdmovie
      var originalFetch = window.fetch;
      window.fetch = function(input, init) {
        var url = (typeof input === 'string') ? input : (input && input.url ? input.url : '');
        
        if (url.includes('api.videasy.net') && url.includes('/mb-flix/')) {
          var newUrl = url.replace('/mb-flix/', '/hdmovie/');
          console.log('[VideasyHook] REDIRECT fetch: mb-flix -> hdmovie');
          console.log('[VideasyHook]   TO: ' + newUrl);
          
          if (typeof input === 'string') {
            return originalFetch.call(this, newUrl, init);
          } else {
            return originalFetch.call(this, new Request(newUrl, input), init);
          }
        }
        
        return originalFetch.apply(this, arguments);
      };
      
      // 3. Intercept XMLHttpRequest for safety
      var origOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        if (typeof url === 'string' && url.includes('api.videasy.net') && url.includes('/mb-flix/')) {
          var newUrl = url.replace('/mb-flix/', '/hdmovie/');
          console.log('[VideasyHook] REDIRECT XHR: mb-flix -> hdmovie');
          arguments[1] = newUrl;
        }
        return origOpen.apply(this, arguments);
      };
      
      console.log('[VideasyHook] All hooks installed at DOCUMENT_START');
    })();
  """;

  /// Extracts the Fade Hindi stream from Videasy by:
  /// 1. Loading the Videasy player page in a headless WebView
  /// 2. Intercepting fetch/XHR at DOCUMENT_START to redirect mb-flix → hdmovie
  /// 3. Capturing the decrypted m3u8 URL via a JSON.parse hook
  Future<Map<String, ExtractedVideasyStream>?> extractFadeHindi({
    required int tmdbId,
    required String title,
    required String mediaType,
    String? imdbId,
    int? year,
    int season = 1,
    int episode = 1,
  }) async {
    developer.log('[VideasyExtractor] Starting Fade Hindi extraction', name: 'Videasy');
    developer.log('[VideasyExtractor]   tmdbId=$tmdbId, title=$title, type=$mediaType', name: 'Videasy');

    final completer = Completer<Map<String, ExtractedVideasyStream>?>();
    HeadlessInAppWebView? headlessWebView;
    Timer? absoluteTimer;
    Timer? settleTimer;
    bool completed = false;

    final Map<String, ExtractedVideasyStream> finalStreams = {};

    // Build the videasy player URL
    String videasyUrl;
    if (mediaType == 'movie') {
      videasyUrl = 'https://player.videasy.net/movie/$tmdbId';
    } else {
      videasyUrl = 'https://player.videasy.net/tv/$tmdbId/$season/$episode';
    }

    developer.log('[VideasyExtractor] Loading: $videasyUrl', name: 'Videasy');

    void _completeWithStreams() {
      if (!completed) {
        completed = true;
        if (!completer.isCompleted) {
          completer.complete(finalStreams.isEmpty ? null : finalStreams);
        }
      }
    }

    headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(videasyUrl),
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
        allowContentAccess: true,
        allowFileAccess: true,
      ),
      // CRITICAL: Inject hooks at DOCUMENT_START so they run BEFORE the page's JS
      initialUserScripts: UnmodifiableListView([
        UserScript(
          source: _hookScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      onWebViewCreated: (controller) async {
        // Register the stream capture handler
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

              // Wait 500ms for settle, then complete
              settleTimer?.cancel();
              settleTimer = Timer(const Duration(milliseconds: 500), () {
                _completeWithStreams();
              });
            } catch (e) {
              developer.log('[VideasyExtractor] Error parsing payload: $e', name: 'Videasy');
            }
          },
        );
      },
      onLoadStop: (controller, url) async {
        // Check if a stream was captured before the handler was ready
        final pending = await controller.evaluateJavascript(source: """
          (function() {
            if (window.__pendingStream) {
              var s = JSON.stringify(window.__pendingStream);
              window.__pendingStream = null;
              return s;
            }
            return null;
          })();
        """);

        if (pending != null && pending != 'null' && pending is String) {
          try {
            final payload = jsonDecode(pending);
            if (payload != null && payload['url'] != null) {
              finalStreams[payload['server'] ?? 'Fade Hindi'] = ExtractedVideasyStream(
                server: payload['server'] ?? 'Fade Hindi',
                url: payload['url'],
                sources: (payload['sources'] as List<dynamic>?) ?? [],
                tracks: (payload['tracks'] as List<dynamic>?) ?? [],
              );
              developer.log('[VideasyExtractor] ✅ Recovered pending stream: ${payload['url']}', name: 'Videasy');
              settleTimer?.cancel();
              settleTimer = Timer(const Duration(milliseconds: 300), () {
                _completeWithStreams();
              });
            }
          } catch (e) {
            developer.log('[VideasyExtractor] Error recovering pending: $e', name: 'Videasy');
          }
        }
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url.toString();
        if (navigationAction.isForMainFrame && !url.contains('videasy.net')) {
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onCreateWindow: (controller, createWindowAction) async {
        return false;
      },
      onConsoleMessage: (controller, consoleMessage) {
        developer.log('[VideasyWV] ${consoleMessage.message}', name: 'Videasy');
      },
    );

    await headlessWebView.run();

    // Absolute timeout: 15 seconds
    absoluteTimer = Timer(const Duration(seconds: 15), () {
      developer.log('[VideasyExtractor] Timeout. Streams found: ${finalStreams.length}', name: 'Videasy');
      _completeWithStreams();
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
