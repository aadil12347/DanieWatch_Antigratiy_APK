import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ExtractedVideasyStream {
  final String server;
  final String url;
  final List<dynamic> sources;
  final List<dynamic> tracks;
  final Map<String, String> headers;

  ExtractedVideasyStream({
    required this.server,
    required this.url,
    required this.sources,
    required this.tracks,
    this.headers = const {
      'Referer': 'https://player.videasy.net/',
      'Origin': 'https://player.videasy.net',
    },
  });

  @override
  String toString() =>
      'ExtractedVideasyStream(server: $server, url: $url, sources: ${sources.length}, tracks: ${tracks.length})';
}

/// Provides hook scripts, URL building, and direct API fetching for Videasy extraction.
///
/// The extraction uses a 1px InAppWebView to load the player page. When the
/// page's JS tries to fetch from mb-flix API, our hook intercepts the URL,
/// redirects it to hdmovie, and sends the final URL to Dart. Dart then makes
/// the actual HTTP request (bypassing SSL cert issues) and parses the m3u8.
class VideasyExtractorService {
  static final VideasyExtractorService _instance =
      VideasyExtractorService._internal();
  factory VideasyExtractorService() => _instance;
  VideasyExtractorService._internal();

  /// Build the Videasy player URL for a given content
  static String buildPlayerUrl({
    required int tmdbId,
    required String mediaType,
    int season = 1,
    int episode = 1,
  }) {
    if (mediaType == 'movie') {
      return 'https://player.videasy.net/movie/$tmdbId';
    } else {
      return 'https://player.videasy.net/tv/$tmdbId/$season/$episode';
    }
  }

  /// The hook script that:
  /// 1. Intercepts JSON.parse to capture decrypted stream payloads
  /// 2. Intercepts fetch() to redirect mb-flix → hdmovie AND sends the URL to Dart
  /// 3. Intercepts XMLHttpRequest similarly
  ///
  /// When the hdmovie API URL is detected, it's sent to Flutter via
  /// 'ApiUrlIntercepted' handler. Dart will make the actual HTTP request
  /// (bypassing SSL issues) and parse the response.
  ///
  /// MUST be injected at DOCUMENT_START (before any page JS runs)
  static const String hookScript = """
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
              console.log('[VideasyHook] CAPTURED stream from JSON.parse: ' + streamUrl);
              
              try {
                window.flutter_inappwebview.callHandler('StreamIntercepted', JSON.stringify({
                  server: 'Fade Hindi',
                  url: streamUrl,
                  sources: result.sources,
                  tracks: result.tracks || []
                }));
              } catch(e) {
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
      
      // 2. Intercept fetch() — redirect mb-flix → hdmovie
      //    Wait for Dart to fetch the encrypted text directly to bypass SSL issues
      var originalFetch = window.fetch;
      window.fetch = async function(input, init) {
        var url = (typeof input === 'string') ? input : (input && input.url ? input.url : '');
        
        if (url.includes('api.videasy.net') && url.includes('/mb-flix/')) {
          var newUrl = url.replace('/mb-flix/', '/hdmovie/');
          console.log('[VideasyHook] REDIRECT fetch: mb-flix -> hdmovie');
          
          try {
            var encryptedText = await window.flutter_inappwebview.callHandler('FetchApi', newUrl);
            if (encryptedText) {
              console.log('[VideasyHook] Got encrypted text from Dart, returning fake Response');
              return new Response(encryptedText, { status: 200, statusText: 'OK' });
            }
          } catch(e) {
            console.log('[VideasyHook] Failed Dart fetch: ' + e);
          }
          
          if (typeof input === 'string') {
            return originalFetch.call(this, newUrl, init);
          } else {
            return originalFetch.call(this, new Request(newUrl, input), init);
          }
        }
        
        return originalFetch.apply(this, arguments);
      };
      
      // 3. Intercept XMLHttpRequest similarly
      var origOpen = XMLHttpRequest.prototype.open;
      var origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url) {
        this._isVideasyApi = (typeof url === 'string' && url.includes('api.videasy.net') && url.includes('/mb-flix/'));
        if (this._isVideasyApi) {
          this._videasyUrl = url.replace('/mb-flix/', '/hdmovie/');
          arguments[1] = this._videasyUrl;
        }
        return origOpen.apply(this, arguments);
      };
      
      XMLHttpRequest.prototype.send = function() {
        if (this._isVideasyApi) {
          var self = this;
          window.flutter_inappwebview.callHandler('FetchApi', this._videasyUrl)
            .then(function(encryptedText) {
              if (encryptedText) {
                console.log('[VideasyHook] Got encrypted text from Dart for XHR');
                Object.defineProperty(self, 'readyState', { value: 4, writable: false });
                Object.defineProperty(self, 'status', { value: 200, writable: false });
                Object.defineProperty(self, 'responseText', { value: encryptedText, writable: false });
                Object.defineProperty(self, 'response', { value: encryptedText, writable: false });
                if (self.onreadystatechange) self.onreadystatechange();
                if (self.onload) self.onload();
              } else {
                origSend.apply(self, arguments);
              }
            })
            .catch(function(e) {
              origSend.apply(self, arguments);
            });
          return;
        }
        return origSend.apply(this, arguments);
      };
      
      console.log('[VideasyHook] All hooks installed at DOCUMENT_START');
    })();
  """;

  /// Auto-click script that clicks play buttons on the Videasy player.
  static const String autoClickScript = """
    (function() {
      try {
        var videos = document.querySelectorAll('video');
        for (var i = 0; i < videos.length; i++) {
          try { videos[i].play(); } catch(e) {}
        }
        
        var selectors = [
          '.play-btn', '.vjs-big-play-button', '.jw-icon-display',
          '[aria-label="Play"]', '.plyr__control--overlaid',
          'button[data-plyr="play"]', '.video-js .vjs-play-control',
          '.ytp-large-play-button', '.play-button', '.btn-play',
          'button.play', '[class*="play"]', '.jw-display-icon-container'
        ];
        
        for (var s = 0; s < selectors.length; s++) {
          var btns = document.querySelectorAll(selectors[s]);
          for (var j = 0; j < btns.length; j++) {
            try { btns[j].click(); } catch(e) {}
          }
        }
        
        var centerX = window.innerWidth / 2;
        var centerY = window.innerHeight / 2;
        var el = document.elementFromPoint(centerX, centerY);
        if (el) {
          try { el.click(); } catch(e) {}
          try { el.dispatchEvent(new MouseEvent('click', {bubbles: true, clientX: centerX, clientY: centerY})); } catch(e) {}
        }
        
        console.log('[AutoClick] Click attempt completed');
      } catch(e) {
        console.log('[AutoClick] Error: ' + e);
      }
    })();
  """;

  /// Pending stream recovery script
  static const String pendingStreamScript = """
    (function() {
      if (window.__pendingStream) {
        var s = JSON.stringify(window.__pendingStream);
        window.__pendingStream = null;
        return s;
      }
      return null;
    })();
  """;

  /// Returns the initial user scripts list for the extraction WebView.
  static UnmodifiableListView<UserScript> get initialUserScripts =>
      UnmodifiableListView([
        UserScript(
          source: hookScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]);

  /// Returns InAppWebViewSettings for the extraction WebView
  static InAppWebViewSettings get extractionSettings => InAppWebViewSettings(
        javaScriptEnabled: true,
        allowsInlineMediaPlayback: true,
        mediaPlaybackRequiresUserGesture: false,
        useShouldOverrideUrlLoading: true,
        domStorageEnabled: true,
        allowContentAccess: true,
        allowFileAccess: true,
        disableContextMenu: true,
        transparentBackground: true,
      );

  /// Make an HTTP request to the Videasy API, bypassing SSL certificate issues.
  /// Returns the raw encrypted string response, or null on failure.
  static Future<String?> fetchApiUrl(String apiUrl) async {
    debugPrint('[VideasyAPI] Fetching: $apiUrl');
    try {
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true; // Bypass SSL

      final request = await httpClient.getUrl(Uri.parse(apiUrl));
      request.headers.set('Referer', 'https://player.videasy.net/');
      request.headers.set('Origin', 'https://player.videasy.net');
      request.headers.set('User-Agent',
          'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36');

      final response = await request.close().timeout(const Duration(seconds: 15));
      final body = await response.transform(utf8.decoder).join();

      debugPrint('[VideasyAPI] Response status: ${response.statusCode}');
      debugPrint('[VideasyAPI] Body length: ${body.length}');

      if (response.statusCode == 200 && body.isNotEmpty) {
        return body; // Return the raw encrypted hex string
      }

      httpClient.close();
    } catch (e) {
      debugPrint('[VideasyAPI] Error: $e');
    }
    return null;
  }
}
