import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:floaty_chatheads/floaty_chatheads.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// PIP overlay entry point — runs in its own Flutter engine.
///
/// This is launched by [PipController.enterPipMode] and runs independently
/// of the main app. It receives video data via [FloatyOverlay.onData] and
/// renders a compact player widget.
@pragma('vm:entry-point')
void pipOverlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  FloatyOverlay.setUp();

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const PipOverlayWidget(),
    ),
  );
}

class PipOverlayWidget extends StatefulWidget {
  const PipOverlayWidget({super.key});

  @override
  State<PipOverlayWidget> createState() => _PipOverlayWidgetState();
}

class _PipOverlayWidgetState extends State<PipOverlayWidget> {
  String? _videoUrl;
  double _startPosition = 0;
  String _title = 'PIP Player';
  Map<String, dynamic>? _fullData;
  InAppWebViewController? _webViewController;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[PIP Overlay] Initialized, waiting for data...');

    // Listen for video data from the main app
    FloatyOverlay.onData.listen((data) {
      debugPrint('[PIP Overlay] Received data: $data');
      if (data is Map && data.containsKey('url')) {
        setState(() {
          _videoUrl = data['url'] as String?;
          _startPosition = (data['position'] as num?)?.toDouble() ?? 0;
          _title = data['title'] as String? ?? 'PIP Player';
          _fullData = Map<String, dynamic>.from(data);
        });

        // Once WebView is ready, start playback
        if (_isReady && _videoUrl != null) {
          _startPlayback();
        }
      }
    });
  }

  void _startPlayback() async {
    if (_webViewController == null || _videoUrl == null) return;

    debugPrint('[PIP Overlay] Starting playback: $_videoUrl @ ${_startPosition}s');

    // Set title
    final escapedTitle = _title.replaceAll("'", "\\'");
    await _webViewController!.evaluateJavascript(
      source: "setTitle('$escapedTitle')",
    );

    // Start video
    await _webViewController!.evaluateJavascript(
      source: "playVideo('$_videoUrl')",
    );

    // Seek to position after a brief delay
    if (_startPosition > 2) {
      await Future.delayed(const Duration(milliseconds: 1500));
      await _webViewController!.evaluateJavascript(
        source: "seekTo(${_startPosition - 2})",
      );
    }
  }

  void _closePip() {
    debugPrint('[PIP Overlay] Close requested');
    FloatyOverlay.shareData({'action': 'close'});
    // The main app's PipController will handle closing the overlay
  }

  void _restoreInApp(double position) {
    debugPrint('[PIP Overlay] Restore requested at position: $position');
    final restoreData = <String, dynamic>{
      'action': 'restore',
      'position': position,
    };

    // Include full data if available
    if (_fullData != null) {
      restoreData['url'] = _fullData!['url'];
      restoreData['title'] = _fullData!['title'];
      restoreData['tmdbId'] = _fullData!['tmdbId'];
      restoreData['mediaType'] = _fullData!['mediaType'];
      restoreData['originalUrl'] = _fullData!['originalUrl'];
      restoreData['season'] = _fullData!['season'];
      restoreData['episode'] = _fullData!['episode'];
    }

    FloatyOverlay.shareData(restoreData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: Colors.black,
          child: _videoUrl == null
              ? const Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: Color(0xFFE11D48),
                      strokeWidth: 2,
                    ),
                  ),
                )
              : InAppWebView(
                  initialFile: 'assets/html/pip_player.html',
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    allowsInlineMediaPlayback: true,
                    mediaPlaybackRequiresUserGesture: false,
                    transparentBackground: true,
                  ),
                  onWebViewCreated: (controller) {
                    _webViewController = controller;

                    controller.addJavaScriptHandler(
                      handlerName: 'closePip',
                      callback: (args) {
                        _closePip();
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'restoreInApp',
                      callback: (args) {
                        double position = 0;
                        if (args.isNotEmpty) {
                          try {
                            final data = jsonDecode(args[0] as String);
                            position = (data['position'] as num?)?.toDouble() ?? 0;
                          } catch (e) {
                            debugPrint('[PIP Overlay] Error parsing restore data: $e');
                          }
                        }
                        _restoreInApp(position);
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'haptic',
                      callback: (args) {
                        HapticFeedback.lightImpact();
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'saveProgress',
                      callback: (args) {
                        // Progress tracking in PIP — can be used later
                      },
                    );
                  },
                  onLoadStop: (controller, url) async {
                    debugPrint('[PIP Overlay] WebView loaded');
                    _isReady = true;
                    if (_videoUrl != null) {
                      _startPlayback();
                    }
                  },
                ),
        ),
      ),
    );
  }
}
