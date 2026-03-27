import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/download_manager.dart';
import '../../domain/models/content_detail.dart';

class DownloadModal extends StatefulWidget {
  final String initialUrl;
  final ContentDetail content;
  final int season;
  final int episode;
  final String? posterUrl;

  DownloadModal({
    super.key,
    required String initialUrl,
    required this.content,
    required this.season,
    required this.episode,
    this.posterUrl,
  }) : initialUrl = _toDownloadUrl(initialUrl);

  /// Extract video ID from embed/detail links → bysebuho.com/download/{id}
  static String _toDownloadUrl(String url) {
    final match = RegExp(r'bysebuho\.com\/(e|d)\/([a-z0-9]+)').firstMatch(url);
    if (match != null) {
      return 'https://bysebuho.com/download/${match.group(2)}';
    }
    return url;
  }

  static void show(
    BuildContext context, {
    required String url,
    required ContentDetail content,
    required int season,
    required int episode,
    String? posterUrl,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
        child: DownloadModal(
          initialUrl: url,
          content: content,
          season: season,
          episode: episode,
          posterUrl: posterUrl,
        ),
      ),
    );
  }

  @override
  State<DownloadModal> createState() => _DownloadModalState();
}

class _DownloadModalState extends State<DownloadModal> {
  InAppWebViewController? _controller;
  bool _captured = false;
  String? _capturedUrl;

  // Block ads & gambling popups but NOT captcha/recaptcha
  bool _isAd(String url) {
    // Never block bysebuho.com
    if (url.contains('bysebuho.com')) return false;

    final l = url.toLowerCase();
    // Never block captcha-related URLs
    if (l.contains('recaptcha') ||
        l.contains('gstatic') ||
        l.contains('google.com/recaptcha')) {
      return false;
    }

    const blocked = [
      'doubleclick',
      'googlesyndication',
      'adservice',
      'popads',
      'popunder',
      'juicyads',
      'exoclick',
      'trafficjunky',
      'jomtingi',
      'jnbhi.com',
      'bet365',
      '1xbet',
      'casino',
      'melbet',
      'mostbet',
      'parimatch',
      'spin-bet',
      'ads-rotation',
      'onclick',
      'clickhouse'
    ];
    return blocked.any((b) => l.contains(b));
  }

  bool _isCdnLink(String url) {
    final l = url.toLowerCase();
    return (l.contains('r66nv9ed.com') ||
            l.contains('edge1-waw') ||
            l.contains('sprintcdn')) &&
        (l.contains('.mp4') || l.contains('download/'));
  }

  void _onLinkCaptured(String url) {
    if (_captured) return;
    if (!_isCdnLink(url) && !url.endsWith('.mp4')) return;

    debugPrint('[Download] CDN link captured: $url');
    setState(() {
      _captured = true;
      _capturedUrl = url;
    });

    DownloadManager.instance.startDownload(
      url: url,
      title: widget.content.title,
      season: widget.season,
      episode: widget.episode,
      posterUrl: widget.posterUrl,
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: h * 0.85,
        decoration: BoxDecoration(
          color: AppColors.background, // Solid dark background
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.download_rounded,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _captured ? 'Download Started!' : 'Download',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh,
                            color: Colors.white54, size: 20),
                        onPressed: () => _controller?.reload(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white54, size: 20),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  if (!_captured)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        widget.initialUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white24, fontSize: 10),
                      ),
                    ),
                ],
              ),
            ),

            // ── WebView or Captured State ──
            Expanded(
              child: _captured ? _buildCaptured() : _buildWebView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    debugPrint('[DownloadModal] Loading: ${widget.initialUrl}');
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        useShouldOverrideUrlLoading: true,
        useOnLoadResource: true,
        javaScriptCanOpenWindowsAutomatically: true,
        supportMultipleWindows: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        safeBrowsingEnabled: false,
        userAgent:
            'Mozilla/5.0 (Linux; Android 13; SM-G981B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36',
      ),
      onWebViewCreated: (c) {
        _controller = c;
        c.addJavaScriptHandler(
            handlerName: 'onDownloadUrl',
            callback: (args) {
              if (args.isNotEmpty) _onLinkCaptured(args[0].toString());
            });
      },
      onLoadStart: (controller, url) {
        debugPrint('[DownloadModal] LoadStart: $url');
      },
      onProgressChanged: (controller, progress) {
        if (progress % 20 == 0) {
          debugPrint('[DownloadModal] Progress: $progress%');
        }
      },
      onReceivedError: (controller, request, error) {
        debugPrint('[DownloadModal] Error: ${error.description}');
      },
      onReceivedHttpError: (controller, request, errorResponse) {
        debugPrint('[DownloadModal] HTTP Error: ${errorResponse.statusCode}');
      },
      onConsoleMessage: (controller, consoleMessage) {
        debugPrint('[DownloadModal] Console: ${consoleMessage.message}');
      },
      onLoadResource: (controller, resource) {
        final url = resource.url?.toString() ?? '';
        if (url.contains('bysebuho.com/api')) {
          debugPrint('[DownloadModal] API Request: $url');
        }
        if (_isCdnLink(url)) _onLinkCaptured(url);
      },
      shouldOverrideUrlLoading: (c, nav) async {
        final url = nav.request.url?.toString() ?? '';

        // Always allow the main site
        if (url.contains('bysebuho.com')) return NavigationActionPolicy.ALLOW;

        // Try to capture CDN links even from navigation
        if (_isCdnLink(url)) {
          _onLinkCaptured(url);
          return NavigationActionPolicy.CANCEL;
        }

        // TEMPORARILY DISABLED: Block obvious ads/popups
        /*
        if (_isAd(url)) {
          debugPrint('[DownloadModal] Blocked Ad Nav: $url');
          return NavigationActionPolicy.CANCEL;
        }
        */

        return NavigationActionPolicy.ALLOW;
      },
      onCreateWindow: (c, req) async {
        final url = req.request.url?.toString() ?? '';
        debugPrint('[DownloadModal] Popup blocked: $url');
        // If a popup somehow contains the CDN link, catch it
        if (_isCdnLink(url)) _onLinkCaptured(url);
        return false; // Always block popup window creation
      },
      onLoadStop: (c, url) async {
        // Inject XHR/fetch interceptor to catch CDN links from AJAX
        await c.evaluateJavascript(source: '''
(function() {
  var origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(m, url) {
    this._url = url;
    return origOpen.apply(this, arguments);
  };
  var origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function() {
    var x = this;
    var orig = x.onreadystatechange;
    x.onreadystatechange = function() {
      if (x.readyState === 4 && x.status === 200) {
        var t = x.responseText || '';
        var m = t.match(/https?:\\/\\/[^"'\\s]*r66nv9ed\\.com\\/download\\/[^"'\\s]*/);
        if (m) window.flutter_inappwebview.callHandler('onDownloadUrl', m[0]);
      }
      if (orig) orig.apply(this, arguments);
    };
    return origSend.apply(this, arguments);
  };
  document.addEventListener('click', function(e) {
    var a = e.target.closest('a');
    if (a && a.href) {
      var h = a.href.toLowerCase();
      if (h.indexOf('r66nv9ed.com') >= 0 || h.indexOf('.mp4') >= 0) {
        window.flutter_inappwebview.callHandler('onDownloadUrl', a.href);
      }
    }
  }, true);
})();
''');
      },
      onDownloadStartRequest: (c, req) {
        debugPrint('[DownloadModal] Download request: ${req.url}');
        _onLinkCaptured(req.url.toString());
      },
    );
  }

  Widget _buildCaptured() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 64),
          SizedBox(height: 16),
          Text('Download Started!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Check downloads page for progress',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      ),
    );
  }
}
