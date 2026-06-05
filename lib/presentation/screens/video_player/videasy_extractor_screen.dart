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
              
              // Smart Auto-clicker to mimic user interactions
              await controller.evaluateJavascript(source: '''
                (async function() {
                  console.log('[AutoClicker] Starting...');
                  var state = 0; 
                  // state 0: wait for player/click play
                  // state 1: click settings
                  // state 2: click language/server
                  // state 3: click 1080p resolution
                  
                  var checkAndClick = async function() {
                    // Try to click play if paused to initialize player UI
                    var v = document.querySelector('video');
                    if (!v || v.paused) {
                       var x = window.innerWidth / 2;
                       var y = window.innerHeight / 2;
                       var el = document.elementFromPoint(x, y);
                       if (el && el.tagName !== 'IFRAME') { el.click(); }
                    }

                    if (state === 0) {
                        // Open settings menu
                        var settingsBtns = document.querySelectorAll('button.tabbable.p-2.rounded-full, [aria-label*="setting" i], [class*="setting" i], [class*="icon-settings" i]');
                        var clicked = false;
                        for(var i=0; i<settingsBtns.length; i++) { 
                            try { settingsBtns[i].click(); clicked = true; } catch(e) {} 
                        }
                        if (clicked) {
                            state = 1;
                            console.log('[AutoClicker] Clicked settings');
                        }
                    } else if (state === 1) {
                        // Find specific server by text
                        var items = document.querySelectorAll('span.font-medium.truncate, p.text-xs.text-gray-500.truncate, li, [role="menuitem"]');
                        var clicked = false;
                        for (var i = 0; i < items.length; i++) {
                           var text = items[i].innerText ? items[i].innerText.toLowerCase() : '';
                           if (text.includes('fade') || text.includes('hindi') || text.includes('hdmovie')) {
                               try {
                                   items[i].click();
                                   clicked = true;
                                   console.log('[AutoClicker] Switched to Hindi/Fade server!');
                               } catch(e) {}
                           }
                        }
                        if (clicked) {
                            state = 2;
                        } else {
                            // sometimes we need to click "Servers" first
                            for (var i = 0; i < items.length; i++) {
                               var text = items[i].innerText ? items[i].innerText.toLowerCase() : '';
                               if (text === 'servers' || text === 'languages') {
                                   try { items[i].click(); } catch(e) {}
                               }
                            }
                        }
                    } else if (state === 2) {
                        // Wait a bit, click settings again to set resolution
                        var settingsBtns = document.querySelectorAll('button.tabbable.p-2.rounded-full, [aria-label*="setting" i], [class*="setting" i]');
                        for(var i=0; i<settingsBtns.length; i++) { 
                            try { settingsBtns[i].click(); } catch(e) {} 
                        }
                        state = 3;
                    } else if (state === 3) {
                        var resButtons = document.querySelectorAll('button.w-full.flex.items-center.justify-between.p-3');
                        var clicked = false;
                        for (var i = 0; i < resButtons.length; i++) {
                           var text = resButtons[i].innerText ? resButtons[i].innerText.toLowerCase() : '';
                           if (text.includes('1080p')) {
                               try {
                                   resButtons[i].click();
                                   clicked = true;
                                   console.log('[AutoClicker] Switched to 1080p!');
                               } catch(e) {}
                           }
                        }
                        if (clicked) state = 4; // done
                    }

                    if (state < 4) {
                       setTimeout(checkAndClick, 800);
                    }
                  };
                  
                  setTimeout(checkAndClick, 1000);
                })();
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
