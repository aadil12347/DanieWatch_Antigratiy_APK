import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;

class VideoExtractorService {
  static final VideoExtractorService _instance = VideoExtractorService._internal();
  factory VideoExtractorService() => _instance;
  VideoExtractorService._internal();

  HeadlessInAppWebView? _headlessWebView;
  
  /// Extracts a direct video URL (m3u8/mp4) from an embed/watch URL.
  Future<String?> extractVideoUrl(String embedUrl) async {
    // 1. Check Cache
    final prefs = await SharedPreferences.getInstance();
    final cachedUrl = prefs.getString('extract_$embedUrl');
    if (cachedUrl != null) {
      developer.log('[Extractor] Found cached URL: $cachedUrl', name: 'Extractor');
      return cachedUrl;
    }

    developer.log('[Extractor] Starting extraction for: $embedUrl', name: 'Extractor');
    final completer = Completer<String?>();
    
    // 2. Setup Headless WebView
    _headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(embedUrl)),
      initialSettings: InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        javaScriptEnabled: true,
        allowsInlineMediaPlayback: true,
      ),
      onLoadStop: (controller, url) async {
        developer.log('[Extractor] Page loaded: $url', name: 'Extractor');
        
        // Inject JS to play and extract
        await _attemptExtraction(controller, completer);
      },
      onConsoleMessage: (controller, consoleMessage) {
        developer.log('[Extractor] Console: ${consoleMessage.message}', name: 'Extractor');
        if (consoleMessage.message.contains('EXTRACTED_URL:')) {
          final url = consoleMessage.message.replaceFirst('EXTRACTED_URL:', '').trim();
          if (!completer.isCompleted) completer.complete(url);
        }
      },
    );

    _headlessWebView?.run();

    // 3. Timeout logic (20s)
    try {
      final result = await completer.future.timeout(const Duration(seconds: 20));
      if (result != null) {
        await prefs.setString('extract_$embedUrl', result);
      }
      return result;
    } on TimeoutException {
      developer.log('[Extractor] Timeout reached', name: 'Extractor');
      return null;
    } finally {
      _cleanup();
    }
  }

  Future<void> _attemptExtraction(InAppWebViewController controller, Completer<String?> completer) async {
    // JS to find video source
    const extractionJs = """
      (function() {
        console.log('Extractor: JS Injected');
        
        function lookForVideo() {
          const video = document.querySelector('video');
          if (video) {
            console.log('Extractor: Video element found');
            video.play().catch(e => console.log('Play failed: ' + e));
            
            if (video.src && video.src.startsWith('http')) {
              console.log('EXTRACTED_URL:' + video.src);
              return true;
            }
            
            const source = video.querySelector('source');
            if (source && source.src) {
              console.log('EXTRACTED_URL:' + source.src);
              return true;
            }
          }
          return false;
        }

        // Initial check
        if (lookForVideo()) return;

        // Poll for 10 seconds
        let attempts = 0;
        const interval = setInterval(() => {
          attempts++;
          if (lookForVideo() || attempts > 20) {
            clearInterval(interval);
          }
        }, 500);
      })();
    """;

    await controller.evaluateJavascript(source: extractionJs);
  }

  void _cleanup() {
    _headlessWebView?.dispose();
    _headlessWebView = null;
  }
}
