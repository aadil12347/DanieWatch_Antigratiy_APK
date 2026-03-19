import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/download_manager.dart';
import '../../services/video_extractor_service.dart';
import '../../domain/models/content_detail.dart';

class DownloadModal extends StatefulWidget {
  final String initialUrl;
  final ContentDetail content;
  final int season;
  final int episode;
  final String? posterUrl;

  const DownloadModal({
    super.key,
    required this.initialUrl,
    required this.content,
    required this.season,
    required this.episode,
    this.posterUrl,
  });

  static void show(BuildContext context, {
    required String url,
    required ContentDetail content,
    required int season,
    required int episode,
    String? posterUrl,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
  bool _isExtracting = true;
  String? _error;
  List<Map<String, dynamic>> _qualities = [];

  // Extraction Window variables
  Timer? _masterWaitTimer;
  Timer? _autoClickTimer;
  Timer? _bgDiscoveryTimer;
  final Set<String> _discoveredLinks = {};
  bool _discoveryComplete = false;
  InAppWebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _startExtractionProcess();
  }

  @override
  void dispose() {
    _masterWaitTimer?.cancel();
    _autoClickTimer?.cancel();
    _bgDiscoveryTimer?.cancel();
    super.dispose();
  }

  void _startExtractionProcess() {
    _bgDiscoveryTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_discoveryComplete) {
        _completeDiscovery();
      }
    });

    _autoClickTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (_discoveryComplete) {
        timer.cancel();
        return;
      }
      final controller = _webViewController;
      if (controller != null && mounted) {
        try {
          controller.evaluateJavascript(source: """
            (function() {
              var buttons = document.querySelectorAll('.play-btn, .vjs-big-play-button, .jw-display-icon-display, .plyr__control--overlaid');
              for(var i=0; i<buttons.length; i++) {
                buttons[i].click();
              }
              var el = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
              if (el) { el.click(); }
              var v = document.querySelector('video');
              if (v) { v.play().catch(function(e){}); }
            })();
          """);
        } catch (e) {
          debugPrint('Error auto-clicking: $e');
        }
      }
    });
  }

  void _handleExtractedLink(String link) {
    if (_discoveryComplete) return;

    final lowerLink = link.toLowerCase();
    if (!lowerLink.contains('.m3u8') && !lowerLink.contains('.mp4')) return;
    if (lowerLink.contains('ads')) return;

    if (!_discoveredLinks.contains(link)) {
      _discoveredLinks.add(link);
    }

    if (lowerLink.contains('master.m3u8') || lowerLink.contains('.urlset')) {
      _masterWaitTimer?.cancel();
      _masterWaitTimer = Timer(const Duration(milliseconds: 200), () {
        _completeDiscovery();
      });
    } else if (_masterWaitTimer == null) {
      _masterWaitTimer = Timer(const Duration(seconds: 3), () {
        _completeDiscovery();
      });
    }
  }

  void _completeDiscovery() {
    if (_discoveryComplete) return;
    String? bestLink;

    final masterLinks = _discoveredLinks.where((l) => l.contains('master.m3u8') || l.contains('.urlset')).toList();
    if (masterLinks.isNotEmpty) {
      masterLinks.sort((a, b) => b.length.compareTo(a.length));
      bestLink = masterLinks.first;
    } else {
      final highQuality = _discoveredLinks.where((l) => l.contains('_h') || l.contains('1080') || l.contains('720')).toList();
      if (highQuality.isNotEmpty) {
        highQuality.sort((a, b) => b.length.compareTo(a.length));
        bestLink = highQuality.first;
      } else if (_discoveredLinks.isNotEmpty) {
        bestLink = _discoveredLinks.first;
      }
    }

    if (mounted) {
      if (bestLink != null) {
        setState(() {
          _discoveryComplete = true;
          _webViewController = null;
        });
        _autoClickTimer?.cancel();
        _bgDiscoveryTimer?.cancel();
        _masterWaitTimer?.cancel();
        
        // Now parse qualities using Dio like before
        _parseQualities(bestLink);
      } else {
        setState(() {
          _isExtracting = false;
          _error = 'Could not extract streaming link.';
          _discoveryComplete = true;
          _webViewController = null;
        });
        _autoClickTimer?.cancel();
        _bgDiscoveryTimer?.cancel();
        _masterWaitTimer?.cancel();
      }
    }
  }

  Future<void> _parseQualities(String extractedUrl) async {
    try {
      if (!extractedUrl.toLowerCase().contains('.m3u8')) {
        setState(() {
          _isExtracting = false;
          _qualities = [{'name': 'Original format', 'url': extractedUrl}];
        });
        return;
      }

      // 2. Parse m3u8 for qualities
      final startUrl = extractedUrl;
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
      final response = await dio.get(startUrl);
      final content = response.data.toString();
      
      final list = <Map<String, dynamic>>[];
      
      if (!content.contains('#EXT-X-STREAM-INF')) {
        list.add({'name': 'Default Quality', 'url': startUrl, 'isHls': true});
      } else {
        final lines = content.split('\n');
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].startsWith('#EXT-X-STREAM-INF:')) {
            final resMatch = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(lines[i]);
            String resolution = 'Unknown';
            if (resMatch != null) {
              resolution = '${resMatch.group(1)}p';
            }
            if (i + 1 < lines.length && !lines[i+1].startsWith('#')) {
              final urlLine = lines[i+1].trim();
              final uri = Uri.parse(startUrl);
              final fullUrl = uri.resolve(urlLine).toString();
              if (!list.any((e) => e['name'] == resolution)) {
                list.add({'name': resolution, 'url': fullUrl, 'isHls': true});
              }
            }
          }
        }
        
        list.sort((a, b) {
          int valA = int.tryParse(a['name'].replaceAll('p', '')) ?? 0;
          int valB = int.tryParse(b['name'].replaceAll('p', '')) ?? 0;
          return valB.compareTo(valA);
        });
      }

      if (mounted) {
        setState(() {
          _isExtracting = false;
          _qualities = list.isEmpty ? [{'name': 'Default Quality', 'url': startUrl, 'isHls': true}] : list;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExtracting = false;
          _error = e.toString();
        });
      }
    }
  }

  void _startDownload(Map<String, dynamic> quality) {
    final url = quality['url'] as String;
    final isHls = quality['isHls'] == true || url.toLowerCase().contains('.m3u8');
    final title = widget.content.title;

    if (isHls) {
      DownloadManager.instance.startHlsDownload(
        url: url,
        title: title,
        season: widget.season,
        episode: widget.episode,
        posterUrl: widget.posterUrl,
      );
    } else {
      DownloadManager.instance.startDownload(
        url: url,
        title: title,
        season: widget.season,
        episode: widget.episode,
        posterUrl: widget.posterUrl,
      );
    }
    
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloading ${quality['name']}...'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_isExtracting && !_discoveryComplete)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: OverflowBox(
                maxWidth: 1280,
                maxHeight: 720,
                child: SizedBox(
                  width: 1280,
                  height: 720,
                  child: Opacity(
                    opacity: 0.01,
                    child: InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    allowsInlineMediaPlayback: true,
                    mediaPlaybackRequiresUserGesture: false,
                    useShouldOverrideUrlLoading: true,
                    useOnLoadResource: true,
                    javaScriptCanOpenWindowsAutomatically: false,
                    supportMultipleWindows: true,
                  ),
                  onCreateWindow: (controller, createWindowAction) async {
                    debugPrint('[Extraction Download] Ad/Popup blocked: ${createWindowAction.request.url}');
                    return true;
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final url = navigationAction.request.url.toString();
                    final isMainFrame = navigationAction.isForMainFrame;
                    
                    if (!isMainFrame && (url.contains('google-analytics') || url.contains('doubleclick') || url.contains('ads'))) {
                      debugPrint('[Extraction Download] Subframe Ad blocked: $url');
                      return NavigationActionPolicy.CANCEL;
                    }
                    
                    return NavigationActionPolicy.ALLOW;
                  },
                  onWebViewCreated: (controller) => _webViewController = controller,
                  onLoadResource: (controller, resource) {
                    if (resource.url != null) {
                      _handleExtractedLink(resource.url.toString());
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      ),
        Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Download Options',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (_isExtracting) ...[
              const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              const SizedBox(height: 16),
              const Text('Extracting stream and discovering qualities...', style: TextStyle(color: AppColors.textSecondary), textAlign: TextAlign.center),
            ] else if (_error != null) ...[
              const Icon(Icons.error_outline, color: Colors.white54, size: 40),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            ] else ...[
              ..._qualities.map((q) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceElevated,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _startDownload(q),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.download, color: Colors.white),
                      const SizedBox(width: 8),
                      Text('Download ${q['name']}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                    ],
                  ),
                ),
              )).toList(),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
            ),
          ],
        ),
      ),
    ),
    ],
  );
}
}
