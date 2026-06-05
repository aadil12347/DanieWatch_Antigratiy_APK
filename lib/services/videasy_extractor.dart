import 'dart:collection';
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

/// Provides hook scripts and URL building for Videasy extraction.
///
/// The extraction itself happens via a 1px InAppWebView embedded in the
/// VideoPlayerScreen widget tree (not HeadlessInAppWebView, which fails
/// to trigger media playback in many cases).
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
  /// 2. Redirects fetch() from mb-flix → hdmovie for Hindi/Fade server
  /// 3. Redirects XMLHttpRequest from mb-flix → hdmovie
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

  /// Auto-click script that clicks play buttons on the Videasy player.
  /// Run this periodically (every 800ms) after the page loads.
  static const String autoClickScript = """
    (function() {
      try {
        // 1. Try direct video.play()
        var videos = document.querySelectorAll('video');
        for (var i = 0; i < videos.length; i++) {
          try { videos[i].play(); } catch(e) {}
        }
        
        // 2. Try common play button selectors
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
        
        // 3. Click center of viewport (where player buttons usually are)
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

  /// Pending stream recovery script — call after page loads to check
  /// if a stream was captured before the handler was ready
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
  /// These must be injected at DOCUMENT_START to work properly.
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
}
