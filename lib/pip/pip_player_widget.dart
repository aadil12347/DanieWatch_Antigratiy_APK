import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:floaty_chatheads/floaty_chatheads.dart';

class PipPlayerWidget extends StatefulWidget {
  final Map<String, dynamic> initialData;
  const PipPlayerWidget({super.key, required this.initialData});

  @override
  State<PipPlayerWidget> createState() => _PipPlayerWidgetState();
}

class _PipPlayerWidgetState extends State<PipPlayerWidget> {
  InAppWebViewController? _webViewController;
  bool _isPlaying = true;
  bool _showOverlay = false;
  String _title = "DanieWatch PIP";
  String? _episodeLabel;

  @override
  void initState() {
    super.initState();
    _title = widget.initialData['title'] ?? "Playing";
    _episodeLabel = widget.initialData['episodeLabel'];
    
    // Listen for events from the host app via FloatyOverlay (e.g. stop)
    FloatyOverlay.receiveDataFromHost((data) {
      if (data == 'stop') {
        FloatyOverlay.closeOverlay();
      }
    });
  }

  void _restoreApp() {
    // We send current position back so app resumes correctly
    _webViewController?.evaluateJavascript(source: "video.currentTime").then((val) {
      final p = (val is num) ? val.toDouble() : 0.0;
      FloatyOverlay.sendDataToHost({
        'action': 'restore',
        'position': p,
      });
      // Delay closing to give host time to open
      Future.delayed(const Duration(milliseconds: 300), () {
        FloatyOverlay.closeOverlay();
      });
    });
  }

  void _closePip() {
    _webViewController?.evaluateJavascript(source: "video.currentTime").then((val) {
      final p = (val is num) ? val.toDouble() : 0.0;
      FloatyOverlay.sendDataToHost({
        'action': 'close',
        'position': p,
      });
      FloatyOverlay.closeOverlay();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showOverlay = !_showOverlay;
          });
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            InAppWebView(
              initialFile: 'assets/html/pip_player.html',
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                transparentBackground: true,
                allowsInlineMediaPlayback: true,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'restoreApp',
                  callback: (args) => _restoreApp(),
                );
                controller.addJavaScriptHandler(
                  handlerName: 'closePip',
                  callback: (args) => _closePip(),
                );
                controller.addJavaScriptHandler(
                  handlerName: 'stateChanged',
                  callback: (args) {
                    if (args.isNotEmpty) {
                      setState(() {
                        _isPlaying = args[0] as bool;
                      });
                    }
                  },
                );
              },
              onLoadStop: (controller, url) async {
                final videoUrl = widget.initialData['videoUrl'] as String?;
                final position = (widget.initialData['startPosition'] as num?)?.toDouble() ?? 0.0;
                
                if (videoUrl != null) {
                  // Play immediately from the given position
                  await controller.evaluateJavascript(
                    source: "playVideo('$videoUrl', $position)",
                  );
                }
              },
            ),
            
            // Touch overlay to quickly intercept touches or show title
            if (_showOverlay)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top Bar
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_episodeLabel != null)
                                  Text(
                                    _episodeLabel!,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 20),
                            onPressed: _closePip,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          )
                        ],
                      ),
                    ),
                    // Bottom Bar
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.fullscreen, color: Colors.white, size: 24),
                            onPressed: _restoreApp,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
