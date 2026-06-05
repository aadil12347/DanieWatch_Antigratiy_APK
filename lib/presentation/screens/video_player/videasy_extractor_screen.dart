import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import 'video_player_screen.dart';

class VideasyExtractorScreen extends StatefulWidget {
  final int tmdbId;
  final String mediaType;
  final int? season;
  final int? episode;
  final String title;
  final List<int>? seasons;

  const VideasyExtractorScreen({
    super.key,
    required this.tmdbId,
    required this.mediaType,
    this.season,
    this.episode,
    required this.title,
    this.seasons,
  });

  @override
  State<VideasyExtractorScreen> createState() => _VideasyExtractorScreenState();
}

class _VideasyExtractorScreenState extends State<VideasyExtractorScreen> {
  InAppWebViewController? webViewController;
  bool _streamFound = false;
  String? _extractedUrl;

  late String _targetUrl;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == 'movie') {
      _targetUrl = 'https://player.videasy.net/movie/${widget.tmdbId}';
    } else {
      _targetUrl = 'https://player.videasy.net/tv/${widget.tmdbId}/${widget.season}/${widget.episode}';
    }
  }

  void _onStreamFound(String url) {
    if (_streamFound) return;
    _streamFound = true;
    _extractedUrl = url;

    // Wait a brief moment, then replace this screen with the native player
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => VideoPlayerScreen(
            url: _extractedUrl!,
            originalUrl: _targetUrl,
            title: widget.title,
            tmdbId: widget.tmdbId,
            mediaType: widget.mediaType,
            seasons: widget.seasons,
            season: widget.season,
            episode: widget.episode,
            isDirectLink: true, // Bypass internal extraction
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          'Resolving Stream...',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // The webview is visible so user can complete Cloudflare or click play
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_targetUrl)),
            initialSettings: InAppWebViewSettings(
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              javaScriptEnabled: true,
              transparentBackground: true,
              useShouldInterceptAjaxRequest: true,
              useShouldInterceptFetchRequest: true,
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;
              
              // Register JS handler
              controller.addJavaScriptHandler(
                handlerName: 'onStreamFound',
                callback: (args) {
                  if (args.isNotEmpty) {
                    _onStreamFound(args[0].toString());
                  }
                },
              );
            },
            onLoadStop: (controller, url) async {
              // Inject fetch and XHR interceptor
              await controller.evaluateJavascript(source: '''
                (function() {
                  if (window.hasInjectedInterceptor) return;
                  window.hasInjectedInterceptor = true;

                  const origOpen = XMLHttpRequest.prototype.open;
                  XMLHttpRequest.prototype.open = function(method, url) {
                      this.addEventListener('load', function() {
                          if (url.includes('.m3u8')) {
                              window.flutter_inappwebview.callHandler('onStreamFound', url);
                          }
                      });
                      origOpen.apply(this, arguments);
                  };

                  const origFetch = window.fetch;
                  window.fetch = async function() {
                      const response = await origFetch.apply(this, arguments);
                      const url = response.url;
                      if (url.includes('.m3u8')) {
                          window.flutter_inappwebview.callHandler('onStreamFound', url);
                      }
                      return response;
                  };
                })();
              ''');
              
              // Optionally inject script to auto-click the play button if present
              await controller.evaluateJavascript(source: '''
                setTimeout(() => {
                  const playBtn = document.querySelector('.vjs-big-play-button') || document.querySelector('.plyr__control--overlaid');
                  if (playBtn) playBtn.click();
                }, 1500);
              ''');
            },
            shouldInterceptAjaxRequest: (controller, ajaxRequest) async {
              final url = ajaxRequest.url?.toString() ?? '';
              if (url.contains('.m3u8')) {
                _onStreamFound(url);
              }
              return ajaxRequest;
            },
            shouldInterceptFetchRequest: (controller, fetchRequest) async {
              final url = fetchRequest.url?.toString() ?? '';
              if (url.contains('.m3u8')) {
                _onStreamFound(url);
              }
              return fetchRequest;
            },
            onConsoleMessage: (controller, consoleMessage) {
              final msg = consoleMessage.message;
              if (msg.contains('.m3u8')) {
                // Sometimes m3u8 URLs are logged
                // We can parse them or just rely on interceptors
              }
            },
          ),
          
          if (_streamFound)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Stream found! Launching player...',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
