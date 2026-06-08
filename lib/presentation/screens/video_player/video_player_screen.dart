import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';

import '../../providers/detail_provider.dart';
import '../../providers/watch_history_provider.dart';
import '../../widgets/sticky_dropdown_modal.dart';
import '../../widgets/liquid_tap_effect.dart';
import '../../../pip/pip_controller.dart';
import '../../../services/videasy_extractor.dart';
import '../../../services/peachify_extractor.dart';
import '../../../services/vidnest_extractor.dart';
import '../../../services/vcloud_extractor.dart';
import '../../../services/hls_resolution_parser.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final String url;
  final String? originalUrl;
  final String title;
  final int tmdbId;
  final String mediaType;
  final List<int>? seasons;

  final int? season;
  final int? episode;
  final bool isOffline;
  final bool isDirectLink;
  final String? posterUrl;
  final double? startPosition;
  final Map<String, ExtractedVideasyStream>? extractedStreams;

  const VideoPlayerScreen({
    super.key,
    required this.url,
    this.originalUrl,
    required this.title,
    required this.tmdbId,
    required this.mediaType,
    this.seasons,
    this.season,
    this.episode,
    this.isOffline = false,
    this.isDirectLink = false,
    this.posterUrl,
    this.startPosition,
    this.extractedStreams,
  });

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _isLoading = true;
  bool _hasError = false;
  bool _isInitialized = false;
  bool _isExtracting = true;
  String? _extractionError;
  String? _extractedLink;
  InAppWebViewController? _webViewController;
  Timer? _extractionTimer;

  // Background Discovery State
  bool _discoveryComplete = false;

  // Extraction Window variables
  Timer? _masterWaitTimer;
  Timer? _autoClickTimer;
  Timer? _bgDiscoveryTimer;
  final Set<String> _discoveredLinks = {};

  // Background Extraction for Episode Switching
  bool _isBgExtracting = false;
  int? _extractingEpisodeIndex;
  String? _bgExtractionUrl;
  InAppWebViewController? _bgWebViewController;
  ValueKey _bgWebViewKey = const ValueKey('bg_discovery_webview');
  final Set<String> _bgDiscoveredLinks = {};
  Timer? _bgMasterWaitTimer;
  Timer? _bgAutoClickTimer;
  Timer? _bgTimeoutTimer;

  // Watch progress tracking
  double _lastCurrentTime = 0;
  double _lastDuration = 0;
  Timer? _errorAutoCloseTimer;
  Timer? _progressSaveTimer;  // Periodic Dart-side save
  bool _startPositionApplied = false;  // Track if we've seeked to startPosition

  // PiP mode state
  bool _isInPipMode = false;

  // Episode Info
  int? _currentEpisode;
  int? _currentSeason;
  String? _episodeSearchQuery;
  final TextEditingController _searchController = TextEditingController();

  // Extraction State
  BetterPlayerController? _betterPlayerController;
  bool _useWebViewEngine = false;
  ValueKey? _webViewKey;
  int _retryCount = 0;
  String? _currentExtractionUrl;
  bool _canPop = false;
  bool _isClosing = false; // Prevents double pops/crashes when pressing back
  String? _selectedServer;
  String? _selectedResolution;
  Map<String, String>? _explicitResolutions;
  Map<String, ExtractedVideasyStream>? _currentStreamsMap;
  Map<String, Map<String, String>> _vcloudResMap = {};
  Map<String, Map<String, String>> _vcloudServerMap = {};
  String _activeServer = 'Server 1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentSeason = widget.season;
    _currentEpisode = widget.episode;

    // Set up PiP mode change listener
    PipController.instance.onPipModeChanged = (isInPip) {
      if (mounted) {
        setState(() => _isInPipMode = isInPip);
        if (isInPip) {
          // Hide HTML controls in PiP mode using the existing player.html function
          _webViewController?.evaluateJavascript(source: "enterPipModeUI();");
        } else {
          // Restore HTML controls when exiting PiP
          _webViewController?.evaluateJavascript(source: "exitPipModeUI();");
        }
      }
    };

    // Handle PiP action buttons (play/pause, seek backward/forward)
    PipController.instance.onPipAction = (action) {
      if (!mounted || _webViewController == null) return;
      debugPrint('[PIP] Handling action: $action');
      switch (action) {
        case 'play':
          _webViewController?.evaluateJavascript(
            source: "document.querySelector('video')?.play();",
          );
          break;
        case 'pause':
          _webViewController?.evaluateJavascript(
            source: "document.querySelector('video')?.pause();",
          );
          break;
        case 'seekForward':
          _webViewController?.evaluateJavascript(
            source: "(function(){ var v = document.querySelector('video'); if(v) v.currentTime = Math.min(v.duration, v.currentTime + 10); })();",
          );
          break;
        case 'seekBackward':
          _webViewController?.evaluateJavascript(
            source: "(function(){ var v = document.querySelector('video'); if(v) v.currentTime = Math.max(0, v.currentTime - 10); })();",
          );
          break;
      }
    };

    // Auto-enter PiP when user presses home while video is playing
    PipController.instance.onUserLeaveHint = () {
      if (mounted && _isInitialized && !_isExtracting && !_hasError) {
        PipController.instance.enterPipMode();
      }
    };

    // Force landscape fullscreen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Hide status bar and navigation bar completely
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );

    // Make system bars transparent to ensure drawing behind notch/cutouts if system allows
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    // Start extraction sequence in background
    _webViewKey = const ValueKey('discovery_webview');
    _currentExtractionUrl = widget.url;

    _currentStreamsMap = widget.extractedStreams != null
        ? widget.extractedStreams!
        : null;

    if (widget.isOffline || widget.isDirectLink) {
      _isExtracting = false;
      _isLoading = false;
      if (_currentStreamsMap != null && _currentStreamsMap!.isNotEmpty) {
        _selectedServer = _currentStreamsMap!.keys.first;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_selectedServer != null && _currentStreamsMap != null) {
          final stream = _currentStreamsMap![_selectedServer!];
          if (stream != null) {
            _startPlayback(stream.url, extractedStream: stream);
          } else {
            _startPlayback(widget.url);
          }
        } else {
          _startPlayback(widget.url, isOffline: widget.isOffline);
        }
      });
      return;
    }

    _isExtracting = true;
    _isLoading = false;

    // Try direct Bysebuho API extraction first (much faster ~1-2s)
    _tryDirectExtraction();

    // Start periodic progress save timer (every 15 seconds)
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _saveToWatchHistory();
    });
  }

  // 1px extraction WebView state
  bool _extraction1pxActive = false;
  String? _extraction1pxUrl;
  ValueKey _extraction1pxKey = const ValueKey('extraction_1px_wv');
  InAppWebViewController? _extraction1pxController;
  Timer? _extraction1pxAutoClickTimer;
  Timer? _extraction1pxSettleTimer;
  Timer? _extraction1pxTimeoutTimer;
  int _extraction1pxClickCount = 0;
  ExtractedVideasyStream? _extractedStream;

  /// Start the extraction using Vcloud database service.
  Future<void> _tryDirectExtraction() async {
    final s = _currentSeason ?? widget.season ?? 1;
    final e = _currentEpisode ?? widget.episode ?? 1;

    debugPrint('[Engine] Starting Vcloud database extraction in player screen');
    setState(() {
      _isExtracting = true;
      _isLoading = false;
      _hasError = false;
    });

    try {
      final resolvedResMap = await VcloudExtractorService().fetchStreamLinks(
        tmdbId: widget.tmdbId,
        mediaType: widget.mediaType,
        title: widget.title,
        season: widget.mediaType == 'movie' ? null : s,
        episode: widget.mediaType == 'movie' ? null : e,
      );

      if (!mounted || _isClosing) return;

      if (resolvedResMap.isEmpty) {
        debugPrint('[Engine] No streaming links found in Vcloud database. Falling back.');
        _onExtractionFailed();
        return;
      }

      // Map resolvedResMap (resolution -> { server -> url }) to server -> { resolution -> url }
      final Map<String, Map<String, String>> serverToResUrl = {};
      resolvedResMap.forEach((res, serversMap) {
        serversMap.forEach((serverName, directUrl) {
          serverToResUrl.putIfAbsent(serverName, () => {})[res] = directUrl;
        });
      });

      // Find first available server in order of priority (Server 1 -> Server 2 -> Server 3)
      String? defaultServer;
      final priorityServers = ['Server 1', 'Server 2', 'Server 3'];
      for (final srv in priorityServers) {
        if (serverToResUrl.containsKey(srv) && serverToResUrl[srv]!.isNotEmpty) {
          defaultServer = srv;
          break;
        }
      }

      // Fallback
      if (defaultServer == null && serverToResUrl.isNotEmpty) {
        defaultServer = serverToResUrl.keys.first;
      }

      if (defaultServer == null) {
        setState(() {
          _isExtracting = false;
          _hasError = true;
        });
        return;
      }

      setState(() {
        _vcloudResMap = resolvedResMap;
        _vcloudServerMap = serverToResUrl;
        _activeServer = defaultServer!;
        _selectedServer = defaultServer;
      });

      await _startVcloudPlayback();
    } catch (err) {
      debugPrint('[Engine] Vcloud extraction failed: $err. Falling back.');
      if (mounted && !_isClosing) {
        _onExtractionFailed();
      }
    }
  }

  Future<void> _startVcloudPlayback() async {
    if (_isClosing) return;

    final resolutions = _vcloudServerMap[_activeServer];
    if (resolutions == null || resolutions.isEmpty) {
      debugPrint('[VcloudPlayer] No resolutions available for $_activeServer');
      _handleFailover();
      return;
    }

    // Sort resolutions: best to worst (1080p -> 720p -> 480p -> 360p)
    final sortedResKeys = resolutions.keys.toList();
    sortedResKeys.sort((a, b) {
      final aInt = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final bInt = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
      return bInt.compareTo(aInt);
    });

    // Pick default resolution (closest to 720p or highest if not found)
    String? defaultRes;
    try {
      defaultRes = sortedResKeys.firstWhere((k) => k.contains('720'));
    } catch (_) {
      defaultRes = sortedResKeys.first;
    }

    _selectedResolution = defaultRes;
    final playUrl = resolutions[defaultRes]!;

    // Populate explicit resolutions for dropdown UI
    final Map<String, String> explicitResolutions = {};
    for (var entry in resolutions.entries) {
      explicitResolutions[entry.key] = entry.value;
    }
    _explicitResolutions = explicitResolutions;

    try {
      if (_betterPlayerController != null) {
        _betterPlayerController!.dispose();
        _betterPlayerController = null;
      }
    } catch (e) {
      debugPrint('[VcloudPlayer] Error disposing BetterPlayer: $e');
    }

    debugPrint('[VcloudPlayer] Playing in glassmorphic WebView player: $playUrl');

    setState(() {
      _isExtracting = true;
      _isLoading = false;
      _isInitialized = false;
      _useWebViewEngine = true; // WebView player
      _extractedLink = playUrl;
    });
  }

  void _handleFailover() {
    if (!mounted || _isClosing) return;

    debugPrint('[VcloudPlayer] Failover triggered. Current active server: $_activeServer');

    // Priority: Server 1 -> Server 2 -> Server 3
    String? nextServer;
    if (_activeServer == 'Server 1') {
      if (_vcloudServerMap.containsKey('Server 2') && _vcloudServerMap['Server 2']!.isNotEmpty) {
        nextServer = 'Server 2';
      } else if (_vcloudServerMap.containsKey('Server 3') && _vcloudServerMap['Server 3']!.isNotEmpty) {
        nextServer = 'Server 3';
      }
    } else if (_activeServer == 'Server 2') {
      if (_vcloudServerMap.containsKey('Server 3') && _vcloudServerMap['Server 3']!.isNotEmpty) {
        nextServer = 'Server 3';
      }
    }

    if (nextServer != null) {
      debugPrint('[VcloudPlayer] Failing over from $_activeServer to $nextServer');
      setState(() {
        _activeServer = nextServer!;
        _selectedServer = nextServer;
      });
      // Start playback on next server
      _startVcloudPlayback();
      
      // Notify user
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Server failed, falling back to $nextServer...'),
              backgroundColor: AppColors.primary,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    } else {
      // No more servers to failover to!
      debugPrint('[VcloudPlayer] All servers failed!');
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Map<String, ExtractedVideasyStream> _sortStreamsMap(Map<String, ExtractedVideasyStream> map) {
    if (map.isEmpty) return map;
    final originalKeys = map.keys.toList();
    final sortedKeys = List<String>.from(originalKeys);
    sortedKeys.sort((a, b) {
      final aLower = a.toLowerCase();
      final bLower = b.toLowerCase();

      // 1. 'Iron - Hindi' is absolute top priority
      final aIsIronHindi = aLower == 'iron - hindi';
      final bIsIronHindi = bLower == 'iron - hindi';
      if (aIsIronHindi && !bIsIronHindi) return -1;
      if (!aIsIronHindi && bIsIronHindi) return 1;

      // 2. Any other server containing Hindi
      final aIsHindi = aLower.contains('hindi');
      final bIsHindi = bLower.contains('hindi');
      if (aIsHindi && !bIsHindi) return -1;
      if (!aIsHindi && bIsHindi) return 1;

      // 3. Otherwise preserve original order
      return originalKeys.indexOf(a).compareTo(originalKeys.indexOf(b));
    });

    final Map<String, ExtractedVideasyStream> sortedMap = {};
    for (var key in sortedKeys) {
      sortedMap[key] = map[key]!;
    }
    return sortedMap;
  }

  /// Called when the extraction 1px WebView is created
  void _onExtraction1pxCreated(InAppWebViewController controller) {
    if (_isClosing) return;
    _extraction1pxController = controller;

    // Register stream capture handler
    controller.addJavaScriptHandler(
      handlerName: 'StreamIntercepted',
      callback: (args) {
        if (_isClosing) return;
        try {
          final payload = jsonDecode(args[0] as String);
          final server = payload['server'] as String? ?? 'Fade Hindi';
          final url = payload['url'] as String;
          final sources = payload['sources'] as List<dynamic>? ?? [];
          final tracks = payload['tracks'] as List<dynamic>? ?? [];

          debugPrint('[Engine] ✅ Stream captured: $url');

          // Wait 200ms for settle (in case more data comes)
          _extraction1pxSettleTimer?.cancel();
          _extraction1pxSettleTimer = Timer(const Duration(milliseconds: 200), () {
            _onExtractionSuccess(ExtractedVideasyStream(
              server: server,
              url: url,
              sources: sources,
              tracks: tracks,
            ));
          });
        } catch (err) {
          debugPrint('[Engine] Error parsing stream payload: $err');
        }
      },
    );

    // Register API URL capture handler (for direct Dart HTTP fetch)
    controller.addJavaScriptHandler(
      handlerName: 'FetchApi',
      callback: (args) async {
        if (_isClosing) return null;
        try {
          final apiUrl = args[0] as String;
          debugPrint('[Engine] 🌐 FetchApi called for: $apiUrl');
          
          final rawEncryptedString = await VideasyExtractorService.fetchApiUrl(apiUrl);
          return rawEncryptedString; // Return the raw string back to the WebView's JS
        } catch (e) {
          debugPrint('[Engine] Error handling FetchApi: $e');
        }
        return null;
      },
    );
  }

  /// Called when the extraction 1px WebView finishes loading
  void _onExtraction1pxLoadStop(InAppWebViewController controller, WebUri? url) async {
    debugPrint('[Engine] 1px WebView loaded: $url');

    // Check for pending stream (captured before handler was ready)
    final pending = await controller.evaluateJavascript(
      source: VideasyExtractorService.pendingStreamScript,
    );
    if (pending != null && pending != 'null' && pending is String) {
      try {
        final payload = jsonDecode(pending);
        if (payload != null && payload['url'] != null) {
          debugPrint('[Engine] ✅ Recovered pending stream: ${payload['url']}');
          _onExtractionSuccess(ExtractedVideasyStream(
            server: payload['server'] ?? 'Fade Hindi',
            url: payload['url'],
            sources: (payload['sources'] as List<dynamic>?) ?? [],
            tracks: (payload['tracks'] as List<dynamic>?) ?? [],
          ));
          return;
        }
      } catch (e) {
        debugPrint('[Engine] Error recovering pending: $e');
      }
    }

    // Start auto-clicker: click every 800ms for up to 8 attempts
    _extraction1pxAutoClickTimer?.cancel();
    _extraction1pxAutoClickTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      _extraction1pxClickCount++;
      if (_extraction1pxClickCount > 8 || !_extraction1pxActive) {
        timer.cancel();
        return;
      }
      debugPrint('[Engine] Auto-click attempt #$_extraction1pxClickCount');
      _extraction1pxController?.evaluateJavascript(
        source: VideasyExtractorService.autoClickScript,
      );
    });
  }

  /// Stream extracted successfully — switch to custom player
  void _onExtractionSuccess(ExtractedVideasyStream stream) {
    if (!mounted || _isClosing) return;

    // Cancel timers
    _extraction1pxAutoClickTimer?.cancel();
    _extraction1pxSettleTimer?.cancel();
    _extraction1pxTimeoutTimer?.cancel();

    debugPrint('[Engine] 🎬 Playing in custom glassmorphism player: ${stream.url}');

    setState(() {
      _extractedStream = stream;
      _extractedLink = stream.url;
      _extraction1pxActive = false; // Remove 1px WebView
      _isExtracting = true;
      _discoveryComplete = true;
      _useWebViewEngine = true;
      _isLoading = false;
      _isInitialized = false;
      _selectedServer = stream.server;
    });
  }

  /// Extraction failed — show error with retry
  void _onExtractionFailed() {
    if (!mounted || _isClosing) return;

    // Cancel timers
    _extraction1pxAutoClickTimer?.cancel();
    _extraction1pxSettleTimer?.cancel();
    _extraction1pxTimeoutTimer?.cancel();

    debugPrint('[Engine] ❌ Extraction failed');

    // Fall back to loading videasy player page directly in the WebView
    final s = _currentSeason ?? widget.season ?? 1;
    final e = _currentEpisode ?? widget.episode ?? 1;
    final videasyUrl = VideasyExtractorService.buildPlayerUrl(
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      season: s,
      episode: e,
    );

    setState(() {
      _extractedLink = videasyUrl;
      _extraction1pxActive = false;
      _isExtracting = false;
      _discoveryComplete = true;
      _useWebViewEngine = true;
      _isLoading = false;
      _isInitialized = true;
    });
  }

  void _startPlayback(String link, {bool isOffline = false, ExtractedVideasyStream? extractedStream}) {
    debugPrint('[Playback] Starting for link: $link (isOffline: $isOffline)');
    setState(() {
      _extractedLink = link;
      _isLoading = true;
      _isExtracting = false;
      _isInitialized = false;
      _useWebViewEngine = false; // Reset initially, will switch below
      _extractedStream = extractedStream;
    });

    _masterWaitTimer?.cancel();
    _autoClickTimer?.cancel();
    _extractionTimer?.cancel();

    // Fallback to web engine if we were passed an HTML page due to failed extraction
    final lowerLink = link.toLowerCase();
    if (!lowerLink.contains('.m3u8') && !lowerLink.contains('.mp4') && !lowerLink.contains('.mkv')) {
      debugPrint('[Playback] URL is not a known video format. Falling back to Web Engine.');
      _switchToWebEngine();
      return;
    }

    if (isOffline) {
      _initializeBetterPlayer(link, isOffline: true);
    } else {
      // Direct link online: Use custom glassmorphism webview player
      _switchToWebEngine();
    }
  }

  Future<void> _initializeBetterPlayer(
    String url, {
    bool isOffline = false,
    ExtractedVideasyStream? extractedStream,
  }) async {
    try {
      if (_betterPlayerController != null) {
        _betterPlayerController!.dispose();
      }

      debugPrint(
        '[BetterPlayer] Initializing for: $url (isOffline: $isOffline)',
      );

      List<BetterPlayerSubtitlesSource>? subtitles;
      if (extractedStream != null && extractedStream.tracks.isNotEmpty) {
        subtitles = extractedStream.tracks
            .where((t) => t['kind'] == 'captions' || t['kind'] == 'subtitles')
            .map((t) {
          return BetterPlayerSubtitlesSource(
            type: BetterPlayerSubtitlesSourceType.network,
            name: t['label']?.toString() ?? 'Subtitle',
            urls: [t['file']?.toString() ?? ''],
          );
        }).toList();
      }

      Map<String, String>? explicitResolutions;
      if (extractedStream != null && extractedStream.sources.isNotEmpty) {
        final Map<String, String> resMap = {};
        for (var source in extractedStream.sources) {
           final label = source['label']?.toString();
           final sUrl = source['url']?.toString();
           // Only add valid explicit MP4 resolutions
           if (label != null && sUrl != null && sUrl.isNotEmpty && source['type'] == 'mp4') {
               resMap[label] = sUrl;
           }
        }
        if (resMap.isNotEmpty) {
           explicitResolutions = resMap;
           _explicitResolutions = resMap;
           if (_selectedResolution == null || !resMap.containsKey(_selectedResolution)) {
             _selectedResolution = resMap.keys.first;
           }
           debugPrint('[BetterPlayer] Added explicit resolutions: \${resMap.keys.join(", ")}');
        }
      } else {
        _explicitResolutions = null;
        _selectedResolution = null;
      }

      BetterPlayerDataSource dataSource = BetterPlayerDataSource(
        isOffline ? BetterPlayerDataSourceType.file : BetterPlayerDataSourceType.network,
        url,
        subtitles: subtitles,
        cacheConfiguration: const BetterPlayerCacheConfiguration(
          useCache: true,
          preCacheSize: 10 * 1024 * 1024,
          maxCacheSize: 500 * 1024 * 1024,
          maxCacheFileSize: 100 * 1024 * 1024,
        ),
        useAsmsAudioTracks: true,
        useAsmsTracks: true,
        useAsmsSubtitles: true,
        headers: !isOffline ? {
          'Referer': 'https://player.videasy.net/',
          'Origin': 'https://player.videasy.net',
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': '*/*',
        } : null,
        notificationConfiguration: BetterPlayerNotificationConfiguration(
          showNotification: true,
          title: widget.mediaType != 'movie' &&
                  _currentSeason != null &&
                  _currentEpisode != null
              ? '${widget.title} S${_currentSeason.toString().padLeft(2, '0')} E${_currentEpisode.toString().padLeft(2, '0')}'
              : widget.title,
          author: 'DanieWatch',
        ),
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 5000,
          maxBufferMs: 30000,
          bufferForPlaybackMs: 2500,
          bufferForPlaybackAfterRebufferMs: 5000,
        ),
      );

      _betterPlayerController = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: true,
          allowedScreenSleep: false,
          fit: BoxFit.contain,
          controlsConfiguration: BetterPlayerControlsConfiguration(
            enableFullscreen: true,
            enablePlayPause: true,
            enableProgressBar: true,
            enableSubtitles: true,
            enableAudioTracks: true,
            enableQualities: true,
            progressBarPlayedColor: AppColors.primary,
            progressBarHandleColor: AppColors.primary,
            loadingColor: AppColors.primary,
            controlBarColor: Colors.black.withValues(alpha: 0.6),
          ),
        ),
        betterPlayerDataSource: dataSource,
      );

      // Listen for events
      _betterPlayerController!.addEventsListener((event) {
        if (event.betterPlayerEventType == BetterPlayerEventType.exception) {
          debugPrint('[BetterPlayer] Exception detected: ${event.parameters}');
          _switchToWebEngine();
        }
      });

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
          _isExtracting = false;
        });
      }

      // Parse HLS master playlist for resolution options (async, non-blocking)
      if (!isOffline && url.contains('.m3u8')) {
        _parseHlsResolutions(url);
      }
    } catch (e) {
      debugPrint('[BetterPlayer] Setup error: $e');
      _switchToWebEngine();
    }
  }

  /// Fetches and parses the HLS master playlist to extract resolution variants.
  /// Populates [_explicitResolutions] so the resolution dropdown appears.
  Future<void> _parseHlsResolutions(String masterUrl) async {
    try {
      final resolutions = await HlsResolutionParser.parseResolutions(masterUrl);
      if (resolutions.isNotEmpty && mounted) {
        setState(() {
          _explicitResolutions = resolutions;
          // Default to highest available resolution
          if (_selectedResolution == null || !resolutions.containsKey(_selectedResolution)) {
            _selectedResolution = resolutions.keys.first;
          }
        });
        debugPrint('[BetterPlayer] 🎬 Resolutions available: ${resolutions.keys.join(", ")}');
      }
    } catch (e) {
      debugPrint('[BetterPlayer] Failed to parse HLS resolutions: $e');
    }
  }

  void _switchToWebEngine() {
    debugPrint('[Engine] Switching to hls.js WebView Engine...');
    final bool isExtractedM3u8 = _extractedLink != null &&
        (_extractedLink!.contains('.m3u8') ||
         _extractedLink!.contains('.mp4') ||
         _extractedLink!.contains('.mkv') ||
         _extractedLink!.contains('googleusercontent') ||
         _extractedLink!.contains('hubcloud') ||
         _extractedLink!.contains('r2') ||
         _vcloudServerMap.isNotEmpty);

    if (mounted) {
      setState(() {
        _useWebViewEngine = true;
        _isLoading = false;
        _isInitialized = !isExtractedM3u8;
        if (!isExtractedM3u8) {
          _isExtracting = false;
        }
      });
    }
  }

  // ─── Background Extraction for Episode Switching ───

  void _startBackgroundExtraction(String url, int episodeIndex) {
    if (_isBgExtracting) return;

    setState(() {
      _isBgExtracting = true;
      _extractingEpisodeIndex = episodeIndex;
      _bgExtractionUrl = url;
      _bgDiscoveredLinks.clear();
      // Nuclear Reset: New Key for fresh WebView
      _bgWebViewKey = ValueKey(
        'bg_discovery_${DateTime.now().millisecondsSinceEpoch}',
      );
    });

    _bgTimeoutTimer?.cancel();
    _bgTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _isBgExtracting) {
        _completeBackgroundDiscovery();
      }
    });

    _bgAutoClickTimer?.cancel();
    _bgAutoClickTimer = Timer.periodic(const Duration(milliseconds: 1000), (
      timer,
    ) {
      if (!_isBgExtracting) {
        timer.cancel();
        return;
      }
      final controller = _bgWebViewController;
      if (controller != null && mounted) {
        controller.evaluateJavascript(
          source: """
          (function() {
            var buttons = document.querySelectorAll('.play-btn, .vjs-big-play-button, .jw-display-icon-display, .plyr__control--overlaid');
            for(var i=0; i<buttons.length; i++) { buttons[i].click(); }
            var el = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
            if (el) { el.click(); }
            var v = document.querySelector('video');
            if (v) { v.play().catch(function(e){}); }
          })();
        """,
        );
      }
    });

    debugPrint('[BG Extraction] Started for episode index: $episodeIndex');
  }

  void _handleBgExtractedLink(String link) {
    if (!_isBgExtracting) return;

    final lowerLink = link.toLowerCase();
    if (!lowerLink.contains('.m3u8') && !lowerLink.contains('.mp4')) return;
    if (lowerLink.contains('ads')) return;

    if (!_bgDiscoveredLinks.contains(link)) {
      _bgDiscoveredLinks.add(link);
    }

    if (lowerLink.contains('master.m3u8') || lowerLink.contains('.urlset')) {
      _bgMasterWaitTimer?.cancel();
      _bgMasterWaitTimer = Timer(const Duration(milliseconds: 200), () {
        _completeBackgroundDiscovery();
      });
    } else {
      _bgMasterWaitTimer ??= Timer(const Duration(milliseconds: 1500), () {
        _completeBackgroundDiscovery();
      });
    }
  }

  void _completeBackgroundDiscovery() {
    if (!_isBgExtracting) return;

    debugPrint(
      '[BG Discovery] Analyzing ${_bgDiscoveredLinks.length} links...',
    );

    String? bestLink;
    final masterLinks = _bgDiscoveredLinks
        .where((l) => l.contains('master.m3u8') || l.contains('.urlset'))
        .toList();
    if (masterLinks.isNotEmpty) {
      masterLinks.sort((a, b) => b.length.compareTo(a.length));
      bestLink = masterLinks.first;
    } else {
      final highQuality = _bgDiscoveredLinks
          .where(
            (l) => l.contains('_h') || l.contains('1080') || l.contains('720'),
          )
          .toList();
      if (highQuality.isNotEmpty) {
        highQuality.sort((a, b) => b.length.compareTo(a.length));
        bestLink = highQuality.first;
      } else if (_bgDiscoveredLinks.isNotEmpty) {
        bestLink = _bgDiscoveredLinks.first;
      }
    }

    if (mounted) {
      if (bestLink != null) {
        final contentAsync = ref.read(
          detailProvider(
            DetailParams(tmdbId: widget.tmdbId, mediaType: widget.mediaType),
          ),
        );
        final content = contentAsync.valueOrNull;
        final episodesAsync = ref.read(
          episodesProvider(
            EpisodeParams(
              tmdbId: widget.tmdbId,
              seasonNumber: _currentSeason ?? 1,
            ),
          ),
        );
        final epIndex = _extractingEpisodeIndex;
        final epsList = episodesAsync.valueOrNull;
        final episode = (epsList != null && epIndex != null && epIndex >= 0 && epIndex < epsList.length)
            ? epsList[epIndex]
            : null;

        setState(() {
          _isBgExtracting = false;
          _extractingEpisodeIndex = null;
          _currentEpisode = episode?.episodeNumber ?? _currentEpisode;
        });

        _bgAutoClickTimer?.cancel();
        _bgTimeoutTimer?.cancel();
        _bgMasterWaitTimer?.cancel();

        _startPlayback(bestLink);
      } else {
        setState(() {
          _isBgExtracting = false;
          _extractingEpisodeIndex = null;
        });
        _bgAutoClickTimer?.cancel();
        _bgTimeoutTimer?.cancel();
        _bgMasterWaitTimer?.cancel();
        debugPrint('[BG Discovery] No links found for background extraction.');
      }
    }
  }

  /// Save current watch progress to the Continue Watching provider
  void _saveToWatchHistory() {
    if (_lastCurrentTime < 15 || _lastDuration < 30) return;

    // Get poster URL and backdrop URL from detail provider
    String? posterUrl;
    String? backdropUrl;
    String? episodeTitle;
    try {
      final detailAsync = ref.read(
        detailProvider(
          DetailParams(tmdbId: widget.tmdbId, mediaType: widget.mediaType),
        ),
      );
      final detail = detailAsync.valueOrNull;
      posterUrl = detail?.posterUrl;
      
      // For TV shows, try to use the specific season's poster if available
      if (widget.mediaType != 'movie' && _currentSeason != null) {
        try {
          final tmdbSeasons = detail?.tmdbSeasons;
          if (tmdbSeasons != null && tmdbSeasons.isNotEmpty) {
            final season = tmdbSeasons.firstWhere(
              (s) => s.seasonNumber == _currentSeason,
              orElse: () => tmdbSeasons.first,
            );
            if (season.posterPath != null && season.posterPath!.isNotEmpty) {
              posterUrl = season.posterPath;
            }
          }
        } catch (_) {}
      }

      if (posterUrl != null && !posterUrl.startsWith('http')) {
        posterUrl = 'https://image.tmdb.org/t/p/w500$posterUrl';
      }
      backdropUrl = detail?.backdropUrl;
      if (backdropUrl != null && !backdropUrl.startsWith('http')) {
        backdropUrl = 'https://image.tmdb.org/t/p/w780$backdropUrl';
      }
    } catch (_) {}

    // Get episode title and thumbnail
    String? episodeThumbnailUrl;
    try {
      if (widget.mediaType != 'movie' && _currentSeason != null) {
        final epsAsync = ref.read(
          episodesProvider(
            EpisodeParams(
              tmdbId: widget.tmdbId,
              seasonNumber: _currentSeason!,
            ),
          ),
        );
        final epsList = epsAsync.valueOrNull;
        if (epsList != null && epsList.isNotEmpty) {
          final ep = epsList.firstWhere(
            (e) => e.episodeNumber == _currentEpisode,
            orElse: () => epsList.first,
          );
          episodeTitle = ep.title;
          episodeThumbnailUrl = ep.thumbnailUrl;
          if (episodeThumbnailUrl != null && !episodeThumbnailUrl.startsWith('http')) {
            episodeThumbnailUrl = 'https://image.tmdb.org/t/p/w500$episodeThumbnailUrl';
          }
        }
      }
    } catch (_) {}

    final item = WatchHistoryItem(
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      title: widget.title,
      season: _currentSeason,
      episode: _currentEpisode,
      episodeTitle: episodeTitle,
      currentTime: _lastCurrentTime,
      duration: _lastDuration,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      thumbnailUrl: episodeThumbnailUrl,
      playUrl: widget.originalUrl ?? _currentExtractionUrl ?? widget.url,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    ref.read(watchHistoryProvider.notifier).saveProgress(item);
    debugPrint('[WatchHistory] Saved: ${item.title} @ ${_lastCurrentTime.toStringAsFixed(0)}s / ${_lastDuration.toStringAsFixed(0)}s');
  }

  Widget _buildLoadingState({Key? key}) {
    final epLabel = widget.mediaType != 'movie' && _currentEpisode != null
        ? 'Episode $_currentEpisode'
        : widget.title;
    return Container(
      key: key,
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveryProgress({Key? key}) {
    final contentAsync = ref.read(
      detailProvider(
        DetailParams(tmdbId: widget.tmdbId, mediaType: widget.mediaType),
      ),
    );
    final content = contentAsync.valueOrNull;

    final String? seasonEpisode;
    if (widget.mediaType != 'movie' && _currentEpisode != null) {
      seasonEpisode = 'Season ${_currentSeason ?? 1} · Episode $_currentEpisode';
    } else {
      seasonEpisode = null;
    }

    return DiscoveryLoadingView(
      key: key,
      backdropUrl: content?.backdropUrl,
      posterUrl: content?.posterUrl,
      title: widget.title,
      logoUrl: content?.displayLogoUrl,
      seasonEpisode: seasonEpisode,
      genres: content?.genres,
      overview: content?.overview ?? content?.description,
      onCancel: _goBack,
    );
  }

  void _retry() {
    _retryCount++;
    debugPrint('[Retry] Attempt #$_retryCount - Triggering Nuclear Reset...');

    _betterPlayerController?.dispose();
    _betterPlayerController = null;

    _extractedLink = null;
    _discoveredLinks.clear();
    _discoveryComplete = false;
    _isExtracting = true;
    _isLoading = false;
    _hasError = false;
    _isInitialized = false;
    _useWebViewEngine = false;

    debugPrint('[Retry] Invoking VideasyExtractorService...');
    _tryDirectExtraction();
    setState(() {});
  }

  Future<void> _goBack({String? error}) async {
    // Prevent double execution — once _isClosing is true, nothing else runs
    if (!mounted || _isClosing) return;
    _isClosing = true;

    // Save watch progress (best-effort, no await)
    try { _saveToWatchHistory(); } catch (_) {}

    // 1. Cancel ALL timers immediately to stop any pending callbacks
    _errorAutoCloseTimer?.cancel();
    _progressSaveTimer?.cancel();
    _extractionTimer?.cancel();
    _masterWaitTimer?.cancel();
    _autoClickTimer?.cancel();
    _bgDiscoveryTimer?.cancel();
    _bgAutoClickTimer?.cancel();
    _bgTimeoutTimer?.cancel();
    _bgMasterWaitTimer?.cancel();
    _extraction1pxAutoClickTimer?.cancel();
    _extraction1pxSettleTimer?.cancel();
    _extraction1pxTimeoutTimer?.cancel();

    // 1b. Restore system brightness
    try { ScreenBrightness().resetScreenBrightness(); } catch (_) {}

    // 2. Pause & null ALL controllers to prevent JS handler callbacks
    try { _betterPlayerController?.pause(); } catch (_) {}
    try {
      _webViewController?.evaluateJavascript(
        source: "document.querySelector('video')?.pause();",
      );
    } catch (_) {}
    _betterPlayerController = null;
    _webViewController = null;
    _bgWebViewController = null;

    // 3. Restore orientation & system UI (fire-and-forget, no await)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );

    // 4. Pop WITHOUT setState — directly set field and pop to avoid rebuild crash
    _canPop = true;
    if (mounted) {
      Navigator.of(context).pop(error);
    }
  }

  void _playNextEpisode() {
    if (!mounted) return;
    if (widget.mediaType == 'movie') return;

    final episodesAsync = ref.read(
      episodesProvider(
        EpisodeParams(
          tmdbId: widget.tmdbId,
          seasonNumber: _currentSeason ?? 1,
        ),
      ),
    );
    final episodes = episodesAsync.valueOrNull;
    if (episodes == null || episodes.isEmpty) return;

    // Find current episode index
    final currentIdx = episodes.indexWhere(
      (ep) => ep.episodeNumber == _currentEpisode,
    );

    // Get the next episode
    final nextIdx = currentIdx + 1;
    if (nextIdx >= episodes.length) {
      debugPrint('[NextEp] No more episodes in this season.');
      return;
    }

    final nextEp = episodes[nextIdx];
    if (nextEp.playLink == null || nextEp.playLink!.isEmpty) {
      debugPrint('[NextEp] Next episode has no play link.');
      return;
    }

    debugPrint('[NextEp] Playing Episode ${nextEp.episodeNumber}');

    setState(() {
      _currentEpisode = nextEp.episodeNumber;
      _currentExtractionUrl = nextEp.playLink;
      _isExtracting = true;
      _discoveryComplete = false;
      _isInitialized = false;
      _extractedLink = null;
      _discoveredLinks.clear();
      _lastCurrentTime = 0.0; // Reset progress for new episode
    });

    _webViewKey = ValueKey(
      'discovery_${DateTime.now().millisecondsSinceEpoch}',
    );
    _tryDirectExtraction();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PipController.instance.onPipModeChanged = null;
    PipController.instance.onUserLeaveHint = null;
    PipController.instance.onPipAction = null;

    // Best-effort save (may have been done already in _goBack)
    try { _saveToWatchHistory(); } catch (_) {}

    // Cancel ALL timers to prevent leaks
    _errorAutoCloseTimer?.cancel();
    _progressSaveTimer?.cancel();
    _extractionTimer?.cancel();
    _masterWaitTimer?.cancel();
    _autoClickTimer?.cancel();
    _bgDiscoveryTimer?.cancel();
    _bgAutoClickTimer?.cancel();
    _bgTimeoutTimer?.cancel();
    _bgMasterWaitTimer?.cancel();

    // Dispose controllers (null-safe since _goBack may have already nulled them)
    try { ScreenBrightness().resetScreenBrightness(); } catch (_) {}
    _searchController.dispose();
    _betterPlayerController?.dispose();
    _betterPlayerController = null;
    _webViewController = null;
    _bgWebViewController = null;

    // Restore orientation and system UI (fire-and-forget)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );

    super.dispose();
  }

  Widget _buildWebPlayer({Key? key}) {
    // Check if we have an extracted m3u8 URL (from our 1px extraction)
    final bool isExtractedM3u8 = _extractedLink != null &&
        (_extractedLink!.contains('.m3u8') ||
         _extractedLink!.contains('.mp4') ||
         _extractedLink!.contains('.mkv') ||
         _extractedLink!.contains('googleusercontent') ||
         _extractedLink!.contains('hubcloud') ||
         _extractedLink!.contains('r2') ||
         _vcloudServerMap.isNotEmpty);

    // Unique key based on extracted link ensures WebView reloads for new episodes
    final webKey = _extractedLink != null
        ? ValueKey('web_player_${_extractedLink!.hashCode}')
        : const ValueKey('web_player_default');


    return Container(
      key: key,
      child: InAppWebView(
        key: webKey,
        // Load from file:// for now; we'll override with loadData in onWebViewCreated
        // when we have an extracted m3u8 (to set the correct origin for Referer)
        initialUrlRequest: isExtractedM3u8
            ? null  // We'll use loadData instead
            : URLRequest(
                url: WebUri(_extractedLink ?? 'about:blank'),
                headers: {
                  'Referer': 'https://peachify.top/',
                  'Origin': 'https://peachify.top',
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                },
              ),
        // For extracted m3u8: load player.html from asset with peachify.top base URL
        // This makes ALL hls.js XHR requests carry Referer: https://peachify.top/
        initialData: isExtractedM3u8
            ? InAppWebViewInitialData(
                data: '', // Placeholder — real content loaded in onWebViewCreated
                baseUrl: WebUri('https://peachify.top'),
                mimeType: 'text/html',
                encoding: 'utf-8',
              )
            : null,
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
        },
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          allowsInlineMediaPlayback: true,
          mediaPlaybackRequiresUserGesture: false,
          useShouldOverrideUrlLoading: true,
          disableContextMenu: true,
          disableLongPressContextMenuOnLinks: true,
          supportMultipleWindows: true,
          javaScriptCanOpenWindowsAutomatically: false,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        ),
        onWebViewCreated: (controller) async {
          if (_isClosing) return;
          _webViewController = controller;

          // For extracted m3u8: read player.html from assets and load it with
          // videasy.net as the base URL. This sets document.origin so all
          // hls.js XHR requests carry the correct Referer header.
          if (isExtractedM3u8) {
            try {
              final htmlContent = await rootBundle.loadString('assets/html/player.html');
              // Also need to inline hls.min.js since we can't use relative paths with loadData
              final hlsJs = await rootBundle.loadString('assets/html/hls.min.js');

              // Replace the external hls.min.js script tag with inline script
              final modifiedHtml = htmlContent.replaceFirst(
                '<script src="hls.min.js"></script>',
                '<script>$hlsJs</script>',
              );

              await controller.loadData(
                data: modifiedHtml,
                baseUrl: WebUri('https://peachify.top/'),
                mimeType: 'text/html',
                encoding: 'utf-8',
              );
            } catch (e) {
              debugPrint('[Engine] Failed to load player.html from assets: $e');
            }
          }
          controller.addJavaScriptHandler(
            handlerName: 'goBack',
            callback: (args) {
              if (_isClosing) return;
              _goBack();
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'playerReady',
            callback: (args) {
              if (_isClosing) return;
              debugPrint('[Engine] WebView reported playerReady');
              if (mounted) {
                setState(() {
                  _isExtracting = false;
                  _isLoading = false;
                  _isInitialized = true;
                });
              }
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'showEpisodes',
            callback: (args) {
              if (_isClosing) return;
              _showEpisodeSelector();
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'enterPipMode',
            callback: (args) async {
              if (_isClosing) return;
              _saveToWatchHistory();
              await PipController.instance.enterPipMode();
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'playNextEpisode',
            callback: (args) {
              if (_isClosing) return;
              _saveToWatchHistory();
              _playNextEpisode();
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'saveWatchProgress',
            callback: (args) {
              if (_isClosing) return;
              if (args.isNotEmpty) {
                try {
                  final data = jsonDecode(args[0] as String);
                  _lastCurrentTime = (data['currentTime'] as num?)?.toDouble() ?? 0;
                  _lastDuration = (data['duration'] as num?)?.toDouble() ?? 0;
                } catch (e) {
                  debugPrint('[WatchHistory] Failed to parse progress: $e');
                }
              }
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'haptic',
            callback: (args) {
              if (_isClosing) return;
              HapticFeedback.lightImpact();
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'setSystemVolume',
            callback: (args) {
              if (_isClosing) return;
              if (args.isNotEmpty) {
                final vol = (args[0] as num).toDouble().clamp(0.0, 1.0);
                VolumeController.instance.showSystemUI = false;
                VolumeController.instance.setVolume(vol);
              }
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'setSystemBrightness',
            callback: (args) async {
              if (_isClosing) return;
              if (args.isNotEmpty) {
                try {
                  final brightness = (args[0] as num).toDouble().clamp(0.0, 1.0);
                  await ScreenBrightness().setScreenBrightness(brightness);
                } catch (e) {
                  debugPrint('Failed to set brightness: $e');
                }
              }
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'logClick',
            callback: (args) {
              if (args.isNotEmpty) {
                debugPrint('[WebView Click] ${args[0]}');
              }
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'logNetwork',
            callback: (args) {
              if (args.isNotEmpty) {
                debugPrint('[WebView Network] ${args[0]}');
              }
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'playerError',
            callback: (args) {
              if (_isClosing) return;
              final errorMsg = args.isNotEmpty ? args[0] as String : 'Unknown';
              debugPrint('[Engine] WebView reported player error: $errorMsg');
              if (_vcloudServerMap.isNotEmpty) {
                _handleFailover();
              }
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'changeServer',
            callback: (args) async {
              if (_isClosing) return;
              if (args.isNotEmpty) {
                final serverName = args[0] as String;
                debugPrint('[Engine] WebView changed server to: $serverName');
                if (_vcloudServerMap.containsKey(serverName)) {
                  final resolutions = _vcloudServerMap[serverName]!;
                  if (resolutions.isNotEmpty) {
                    String newRes = _selectedResolution ?? resolutions.keys.first;
                    if (!resolutions.containsKey(newRes)) {
                      newRes = resolutions.keys.first;
                    }
                    final newUrl = resolutions[newRes]!;
                    
                    final dynamic pos = await controller.evaluateJavascript(
                      source: "document.querySelector('video') ? document.querySelector('video').currentTime : 0.0;"
                    );
                    final double resumeTime = (pos is num) ? pos.toDouble() : _lastCurrentTime;
                    
                    setState(() {
                      _activeServer = serverName;
                      _selectedServer = serverName;
                      _selectedResolution = newRes;
                      _extractedLink = newUrl;
                    });
                    
                    final customQualitiesJs = jsonEncode(resolutions);
                    final escapedUrl = newUrl.replaceAll("'", "\\'").replaceAll('"', '\\"');
                    await controller.evaluateJavascript(source: """
                      (function() {
                        window.setupCustomQualityPicker($customQualitiesJs, '$newRes');
                        window.changeVideoSource('$escapedUrl', $resumeTime);
                      })();
                    """);
                  }
                } else if (_currentStreamsMap != null && _currentStreamsMap!.containsKey(serverName)) {
                  setState(() {
                    _selectedServer = serverName;
                  });
                  final stream = _currentStreamsMap![serverName]!;
                  _startPlayback(stream.url, extractedStream: stream);
                }
              }
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'changeQuality',
            callback: (args) async {
              if (_isClosing) return;
              if (args.isNotEmpty) {
                final String qualityName = args[0] as String;
                debugPrint('[Engine] WebView changed quality to: $qualityName');
                
                final serverUrls = _vcloudServerMap[_activeServer];
                if (serverUrls != null && serverUrls.containsKey(qualityName)) {
                  final String newUrl = serverUrls[qualityName]!;
                  
                  final dynamic pos = await controller.evaluateJavascript(
                    source: "document.querySelector('video') ? document.querySelector('video').currentTime : 0.0;"
                  );
                  final double resumeTime = (pos is num) ? pos.toDouble() : _lastCurrentTime;
                  
                  setState(() {
                    _selectedResolution = qualityName;
                    _extractedLink = newUrl;
                  });
                  
                  final escapedUrl = newUrl.replaceAll("'", "\\'").replaceAll('"', '\\"');
                  await controller.evaluateJavascript(
                    source: "window.changeVideoSource('$escapedUrl', $resumeTime);"
                  );
                }
              }
            },
          );
        },
        onLoadStart: (controller, url) async {
          await controller.evaluateJavascript(source: """
            (function() {
              if (window.__safeRemoveChildInjected) return;
              window.__safeRemoveChildInjected = true;
              var originalRemoveChild = Node.prototype.removeChild;
              Node.prototype.removeChild = function(child) {
                if (child && child.parentNode === this) {
                  try {
                    return originalRemoveChild.call(this, child);
                  } catch (e) {
                    console.warn('Safely caught removeChild error', e);
                  }
                }
                return child;
              };
            })();
          """);
        },
        shouldOverrideUrlLoading: (controller, navigationAction) async {
          final url = navigationAction.request.url.toString();
          // Allow file:// URLs (our player.html), videasy.net, and peachify.top
          if (url.startsWith('file://') || url.contains('videasy.net') || url.contains('peachify.top')) {
            return NavigationActionPolicy.ALLOW;
          }
          if (navigationAction.isForMainFrame) {
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
        // Accept SSL certs for m3u8 segment CDNs
        onReceivedServerTrustAuthRequest: (controller, challenge) async {
          return ServerTrustAuthResponse(
            action: ServerTrustAuthResponseAction.PROCEED,
          );
        },
        onLoadStop: (controller, url) async {
          debugPrint('[Engine] Web Player Loaded: $url');

          // If we loaded our custom player via loadData, inject the m3u8 URL
          if (isExtractedM3u8) {
            final m3u8Url = _extractedLink!;
            final escapedUrl = m3u8Url.replaceAll("'", "\\'")
                .replaceAll('"', '\\"');
            final titleEscaped = widget.title.replaceAll("'", "\\'")
                .replaceAll('"', '\\"');

            // Set title and media type
            final s = _currentSeason ?? widget.season;
            final e = _currentEpisode ?? widget.episode;
            String episodeLabel = '';
            if (widget.mediaType != 'movie' && s != null && e != null) {
              episodeLabel = 'S$s E$e';
            }

            // Build subtitle tracks JS array if available
            String tracksJs = '[]';
            if (_extractedStream != null && _extractedStream!.tracks.isNotEmpty) {
              final tracksList = _extractedStream!.tracks
                  .where((t) => t['kind'] == 'captions' || t['kind'] == 'subtitles')
                  .map((t) {
                final file = (t['file'] ?? '').toString().replaceAll("'", "\\'")
                    .replaceAll('"', '\\"');
                final label = (t['label'] ?? 'Subtitle').toString().replaceAll("'", "\\'")
                    .replaceAll('"', '\\"');
                return '{file:"$file",label:"$label",kind:"captions"}';
              }).toList();
              tracksJs = '[${tracksList.join(',')}]';
            }

            final headersMap = _extractedStream?.headers ?? {
              'Referer': 'https://player.videasy.net/',
              'Origin': 'https://player.videasy.net'
            };
            final headersJson = jsonEncode(headersMap);

            String serversJs = '[]';
            if (_vcloudServerMap.isNotEmpty) {
              serversJs = jsonEncode(_vcloudServerMap.keys.toList());
            } else if (_currentStreamsMap != null && _currentStreamsMap!.isNotEmpty) {
              serversJs = jsonEncode(_currentStreamsMap!.keys.toList());
            }

            final double resumeTime = _lastCurrentTime > 1 ? _lastCurrentTime : (widget.startPosition?.toDouble() ?? 0.0);

            // Setup custom quality picker if we have vcloud server map resolutions
            String customQualitiesJs = '{}';
            if (_vcloudServerMap.containsKey(_activeServer)) {
              final Map<String, String> resUrls = _vcloudServerMap[_activeServer]!;
              customQualitiesJs = jsonEncode(resUrls);
            }

            await controller.evaluateJavascript(source: """
              (function() {
                // Set title
                window.videoTitle('$titleEscaped', '$episodeLabel');

                // Set media type (show/hide episodes button)
                window.setMediaType('${widget.mediaType}');

                // Setup server picker
                var servers = $serversJs;
                if (servers.length > 0) {
                  window.setupServerPicker(servers, '${_selectedServer ?? ""}');
                }

                // Setup custom quality picker
                var customQualities = $customQualitiesJs;
                if (Object.keys(customQualities).length > 0) {
                  window.setupCustomQualityPicker(customQualities, '${_selectedResolution ?? ""}');
                }

                // Play video with headers
                window.playVideo('$escapedUrl', $headersJson);

                // Add subtitle tracks if available
                var tracks = $tracksJs;
                if (tracks.length > 0 && typeof hls !== 'undefined') {
                  tracks.forEach(function(t) {
                    try {
                      var track = document.createElement('track');
                      track.kind = 'captions';
                      track.label = t.label;
                      track.src = t.file;
                      document.querySelector('video').appendChild(track);
                    } catch(e) {}
                  });
                }

                // Seek to saved position for Continue Watching
                if ($resumeTime > 1) {
                  window.seekToPosition($resumeTime);
                }

                // Init system volume
                try {
                  window.flutter_inappwebview.callHandler('getSystemVolume').then(function(vol) {
                    if (vol !== undefined && vol !== null) window.initSystemVolume(vol);
                  });
                } catch(e) {}
              })();
            """);
          } else {
            // Fallback: loaded the Videasy player page directly
            await controller.evaluateJavascript(
              source: """
              (function() {
                if (!window.__safeRemoveChildInjected) {
                  window.__safeRemoveChildInjected = true;
                  var originalRemoveChild = Node.prototype.removeChild;
                  Node.prototype.removeChild = function(child) {
                    if (child && child.parentNode === this) {
                      try { return originalRemoveChild.call(this, child); } catch (e) {}
                    }
                    return child;
                  };
                }
                var style = document.createElement('style');
                style.innerHTML = '.header, .footer, .ad-banner { display: none !important; }';
                document.head.appendChild(style);
                if (${widget.startPosition ?? 0} > 1) {
                  var seekHandler = function() {
                    var v = document.querySelector('video');
                    if (v && v.currentTime >= 0.5) {
                      v.currentTime = ${widget.startPosition ?? 0};
                      v.removeEventListener('timeupdate', seekHandler);
                    }
                  };
                  setInterval(function() {
                     var v = document.querySelector('video');
                     if (v && !v.__seekListenerAdded) {
                        v.__seekListenerAdded = true;
                        v.addEventListener('timeupdate', seekHandler);
                     }
                  }, 1000);
                }
              })();
              """,
            );
          }
        },
      ),
    );
  }

  void _showEpisodeSelector() {
    final seriesTitle = widget.title;
    int tempSeason = _currentSeason ?? 1;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Episodes',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        const curve = Curves.easeOutCubic;
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.8,
              end: 1.0,
            ).animate(CurvedAnimation(parent: anim1, curve: curve)),
            child: Align(
              alignment: Alignment.center,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width:
                      MediaQuery.of(context).size.width * 0.75, // Reduced width
                  height: MediaQuery.of(context).size.height * 0.85,
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white10, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      StatefulBuilder(
                        builder: (context, setModalState) {
                          final episodeParams = EpisodeParams(
                            tmdbId: widget.tmdbId,
                            seasonNumber: tempSeason,
                          );

                          return Padding(
                            padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Side Panel: Header & Season Selector
                                SizedBox(
                                  width: 210,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        seriesTitle,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      // Season Selector
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.05,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        clipBehavior: Clip.hardEdge,
                                        child: StickyDropdownModal<int>(
                                            items: widget.seasons ?? [],
                                            value: tempSeason,
                                            onChanged: (result) {
                                              if (result != tempSeason) {
                                                setModalState(() => tempSeason = result);
                                              }
                                            },
                                            itemLabelBuilder: (val) => 'Season $val',
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    'Season $tempSeason',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  const Icon(
                                                    Icons.keyboard_arrow_down_rounded,
                                                    color: Colors.white38,
                                                  ),
                                                ],
                                              ),
                                              ),
                                            ),
                                          ),
                                      const SizedBox(height: 12),
                                      // Search Bar
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.05,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.search_rounded,
                                              color: Colors.white.withValues(
                                                alpha: 0.3,
                                              ),
                                              size: 16,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: TextField(
                                                onChanged: (val) =>
                                                    setModalState(
                                                  () =>
                                                      _episodeSearchQuery = val,
                                                ),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                ),
                                                decoration: InputDecoration(
                                                  hintText: 'Search episode...',
                                                  hintStyle: TextStyle(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.3),
                                                    fontSize: 12,
                                                  ),
                                                  border: InputBorder.none,
                                                  isDense: true,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 24),
                                Container(
                                  width: 1,
                                  color: Colors.white.withValues(alpha: 0.05),
                                  height: double.infinity,
                                ),
                                const SizedBox(width: 24),

                                // Main Panel: Episode List
                                Expanded(
                                  child: Consumer(
                                    builder: (context, ref, _) {
                                      final episodesAsync = ref.watch(
                                        episodesProvider(episodeParams),
                                      );

                                      return episodesAsync.when(
                                        loading: () => const Center(
                                          child: CircularProgressIndicator(
                                            color: AppColors.primary,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        error: (e, _) => const Center(
                                          child: Icon(
                                            Icons.error_outline,
                                            color: Colors.white24,
                                          ),
                                        ),
                                        data: (episodes) {
                                          final filtered =
                                              _episodeSearchQuery == null ||
                                                      _episodeSearchQuery!
                                                          .isEmpty
                                                  ? episodes
                                                  : episodes
                                                      .where(
                                                        (e) =>
                                                            e.episodeNumber
                                                                .toString()
                                                                .contains(
                                                                  _episodeSearchQuery!,
                                                                ) ||
                                                            (e.title
                                                                    ?.toLowerCase()
                                                                    .contains(
                                                                      _episodeSearchQuery!
                                                                          .toLowerCase(),
                                                                    ) ??
                                                                false),
                                                      )
                                                      .toList();

                                          // Find current episode index to auto-scroll
                                          final currentIdx = filtered.indexWhere(
                                            (e) => e.episodeNumber == _currentEpisode,
                                          );
                                          const itemHeight = 92.0; // 68px thumb + 12px margin + 8*2 padding
                                          final initialOffset = currentIdx > 0
                                              ? (currentIdx * itemHeight).clamp(0.0, double.infinity)
                                              : 0.0;
                                          final scrollCtrl = ScrollController(
                                            initialScrollOffset: initialOffset,
                                          );

                                          return ListView.builder(
                                            controller: scrollCtrl,
                                            physics:
                                                const AlwaysScrollableScrollPhysics(),
                                            itemCount: filtered.length,
                                            padding: const EdgeInsets.only(
                                              bottom: 20,
                                            ),
                                            itemBuilder: (context, index) {
                                              final ep = filtered[index];
                                              final isCurrent =
                                                  ep.episodeNumber ==
                                                      _currentEpisode;

                                              return InkWell(
                                                onTap: () {
                                                  if (ep.playLink != null &&
                                                      ep.playLink!.isNotEmpty) {
                                                    Navigator.pop(context);
                                                    setState(() {
                                                       _currentEpisode =
                                                           ep.episodeNumber;
                                                       _currentExtractionUrl =
                                                           ep.playLink;
                                                       _isExtracting = true;
                                                       _discoveryComplete =
                                                           false;
                                                       _isInitialized = false;
                                                       _extractedLink = null;
                                                       _discoveredLinks.clear();
                                                       _lastCurrentTime = 0.0; // Reset progress for new episode
                                                     });
                                                    _webViewController
                                                        ?.evaluateJavascript(
                                                      source:
                                                          "updateEpisodeButton('Episodes')",
                                                    );
                                                    _webViewKey = ValueKey(
                                                      'discovery_${DateTime.now().millisecondsSinceEpoch}',
                                                    );
                                                    _tryDirectExtraction();
                                                  }
                                                },
                                                child: Container(
                                                  margin: const EdgeInsets.only(
                                                    bottom: 12,
                                                  ),
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isCurrent
                                                        ? AppColors.primary
                                                            .withValues(
                                                            alpha: 0.1,
                                                          )
                                                        : Colors.transparent,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      12,
                                                    ),
                                                    border: Border.all(
                                                      color: isCurrent
                                                          ? AppColors.primary
                                                              .withValues(
                                                              alpha: 0.3,
                                                            )
                                                          : Colors.transparent,
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      ClipRRect(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                          8,
                                                        ),
                                                        child: SizedBox(
                                                          width: 120,
                                                          height: 68,
                                                          child: ep.thumbnailUrl !=
                                                                  null
                                                              ? CachedNetworkImage(
                                                                  imageUrl: ep
                                                                      .thumbnailUrl!,
                                                                  fit: BoxFit
                                                                      .cover,
                                                                  placeholder: (
                                                                    _,
                                                                    __,
                                                                  ) =>
                                                                      Container(
                                                                    color: Colors
                                                                        .white10,
                                                                  ),
                                                                  errorWidget: (
                                                                    _,
                                                                    __,
                                                                    ___,
                                                                  ) =>
                                                                      Container(
                                                                    color: Colors
                                                                        .black26,
                                                                  ),
                                                                )
                                                              : Container(
                                                                  color: Colors
                                                                      .black26,
                                                                ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 16),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              'EP ${ep.episodeNumber}: ${ep.title ?? 'Episode ${ep.episodeNumber}'}',
                                                              style: TextStyle(
                                                                color: isCurrent
                                                                    ? AppColors
                                                                        .primary
                                                                    : Colors
                                                                        .white70,
                                                                fontSize: 13,
                                                                fontWeight: isCurrent
                                                                    ? FontWeight
                                                                        .bold
                                                                    : FontWeight
                                                                        .normal,
                                                              ),
                                                              maxLines: 2,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                            const SizedBox(
                                                              height: 4,
                                                            ),
                                                            Text(
                                                              ep.runtime !=
                                                                          null &&
                                                                      ep.runtime! >
                                                                          0
                                                                  ? '${ep.runtime} min'
                                                                  : '',
                                                              style:
                                                                  const TextStyle(
                                                                color: Colors
                                                                    .white38,
                                                                fontSize: 11,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Icon(
                                                        Icons
                                                            .play_circle_fill_rounded,
                                                        color: isCurrent
                                                            ? AppColors.primary
                                                            : Colors.white
                                                                .withValues(
                                                                alpha: 0.2,
                                                              ),
                                                        size: 28,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      // Close Button
                      Positioned(
                        top: 16,
                        right: 16,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white38,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEpisodeShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.1),
      child: ListView.builder(
        itemCount: 5,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 76,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            _buildMainContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Stack(
      children: [
        // 0. Base Layer
        const SizedBox.expand(child: ColoredBox(color: Colors.black)),

        // 1. Silent 1px Extraction WebView (invisible to user)
        if (_extraction1pxActive && _extraction1pxUrl != null)
          Offstage(
            child: SizedBox(
              width: 1,
              height: 1,
              child: InAppWebView(
                key: _extraction1pxKey,
                initialUrlRequest: URLRequest(
                  url: WebUri(_extraction1pxUrl!),
                  headers: {
                    'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                  },
                ),
                initialSettings: VideasyExtractorService.extractionSettings,
                initialUserScripts: VideasyExtractorService.initialUserScripts,
                onWebViewCreated: _onExtraction1pxCreated,
                onLoadStop: _onExtraction1pxLoadStop,
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final url = navigationAction.request.url.toString();
                  if (navigationAction.isForMainFrame && !url.contains('videasy.net')) {
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                onCreateWindow: (controller, createWindowAction) async => false,
                // Accept SSL certificates from api.videasy.net
                // (their cert is untrusted by Android's default CA store)
                onReceivedServerTrustAuthRequest: (controller, challenge) async {
                  debugPrint('[1px WV] SSL bypass for: ${challenge.protectionSpace.host}');
                  return ServerTrustAuthResponse(
                    action: ServerTrustAuthResponseAction.PROCEED,
                  );
                },
                onConsoleMessage: (controller, consoleMessage) {
                  debugPrint('[1px WV] ${consoleMessage.message}');
                },
              ),
            ),
          ),

        // 2. Background Extraction for episode switching
        if (_isBgExtracting && _bgExtractionUrl != null)
          Offstage(
            child: SizedBox(
              width: 1,
              height: 1,
              child: InAppWebView(
                key: _bgWebViewKey,
                initialUrlRequest: URLRequest(url: WebUri(_bgExtractionUrl!)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  allowsInlineMediaPlayback: true,
                  mediaPlaybackRequiresUserGesture: false,
                  useOnLoadResource: true,
                ),
                onWebViewCreated: (controller) =>
                    _bgWebViewController = controller,
                onLoadResource: (controller, resource) {
                  if (resource.url != null) {
                    _handleBgExtractedLink(resource.url.toString());
                  }
                },
              ),
            ),
          ),

        // 3. Main UI Layer
        if (_useWebViewEngine)
          Positioned.fill(
            child: _buildWebPlayer(key: const ValueKey('web_player')),
          )
        else if (_isInitialized && !_isLoading)
          Positioned.fill(
            child: _buildPlayerInterface(),
          )
        else
          Positioned.fill(
            child: _buildLoadingState(key: const ValueKey('prep')),
          ),

        // 4. Discovery Progress Loader Overlay
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: _isExtracting
                ? _buildDiscoveryProgress(key: const ValueKey('loader'))
                : const SizedBox.shrink(key: ValueKey('empty')),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerInterface() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              BetterPlayer(
                key: const ValueKey('native_player'),
                controller: _betterPlayerController!,
              ),
              if (!_isInPipMode) _buildTopBar(),
              if (!_isInPipMode) _buildBottomControlsOverlay(),
              if (!_isInPipMode) _buildEpisodeInfoOverlay(),
              if (!_isInPipMode) _buildControlHints(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomControlsOverlay() {
    final hasServers = _vcloudServerMap.length > 1;
    final hasResolutions = _explicitResolutions != null && _explicitResolutions!.length > 1;

    if (!hasServers && !hasResolutions) return const SizedBox.shrink();

    return Positioned(
      bottom: 80, // Sit above the native BetterPlayer bottom controls
      right: 16,
      child: SafeArea(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasServers)
              Container(
                margin: const EdgeInsets.only(left: 8),
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: Colors.black87,
                    value: _activeServer,
                    icon: const Icon(Icons.language, color: Colors.white, size: 18),
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    onChanged: (String? newValue) {
                      if (newValue != null && newValue != _activeServer) {
                        setState(() {
                          _activeServer = newValue;
                          _selectedServer = newValue;
                        });
                        _startVcloudPlayback();
                      }
                    },
                    items: _vcloudServerMap.keys.map<DropdownMenuItem<String>>((String value) {
                      String label = value;
                      if (value == 'Server 1') label = 'Server 1 (Hub)';
                      if (value == 'Server 2') label = 'Server 2 (G-Drive)';
                      if (value == 'Server 3') label = 'Server 3 (R2)';
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Text(label.toUpperCase()),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

            if (hasResolutions)
              Container(
                margin: const EdgeInsets.only(left: 8),
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: Colors.black87,
                    value: _selectedResolution,
                    icon: const Icon(Icons.high_quality, color: Colors.white, size: 18),
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    onChanged: (String? newValue) {
                      if (newValue != null && newValue != _selectedResolution) {
                        setState(() {
                          _selectedResolution = newValue;
                        });
                        final resUrl = _explicitResolutions![newValue]!;
                        if (_useWebViewEngine) {
                          setState(() {
                            _extractedLink = resUrl;
                          });
                        } else {
                          try {
                            _betterPlayerController?.setResolution(resUrl);
                          } catch (e) {
                            debugPrint('[BetterPlayer] Error setting resolution: $e');
                          }
                        }
                      }
                    },
                    items: _explicitResolutions!.keys.map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Text(value.toUpperCase()),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: _goBack,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.mediaType != 'movie')
                IconButton(
                  icon:
                      const Icon(Icons.grid_view_rounded, color: Colors.white),
                  onPressed: _showEpisodeSelector,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodeInfoOverlay() => const SizedBox.shrink();
  Widget _buildControlHints() => const SizedBox.shrink();

  Widget _buildErrorOverlay() {
    // NOTE: Timer is NOT created here — it's started in _completeDiscovery()
    // Creating timers inside build() causes multiple timer instances on every rebuild

    final epLabel = widget.mediaType != 'movie' && _currentEpisode != null
        ? 'Episode $_currentEpisode'
        : widget.title;

    return Container(
      color: Colors.black.withValues(alpha: 0.95),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                color: AppColors.primary.withValues(alpha: 0.7),
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Failed to load $epLabel',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                _extractionError ?? 'Source unavailable. Try another server.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withAlpha(128),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Closing automatically...',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    _errorAutoCloseTimer?.cancel();
                    _retry();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary),
                ),
                const SizedBox(width: 14),
                TextButton.icon(
                  onPressed: () {
                    _errorAutoCloseTimer?.cancel();
                    _goBack();
                  },
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white60),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CinematicLoader extends StatefulWidget {
  const _CinematicLoader();

  @override
  State<_CinematicLoader> createState() => _CinematicLoaderState();
}

class _CinematicLoaderState extends State<_CinematicLoader>
    with SingleTickerProviderStateMixin {
  late List<String> _shuffledPhrases;
  late AnimationController _scrollController;
  final double _itemHeight = 50.0;
  final Color _netflixRed = const Color(0xFFE50914);

  @override
  void initState() {
    super.initState();
    final List<String> phrases = [
      'Getting the popcorn',
      'Dimming the lights',
      'Buffering your movie',
      'Finding the best part',
      'Skip intro in... wait',
      'Just one more episode',
      'Are you still watching?',
      'Setting up the drama',
      'Queuing cliffhangers',
      'Action incoming',
      'Plot twists ahead',
      'Preparing the comedy',
      'Ready for tears?',
      'Starting the jump scares',
      'Warming up the pixels',
      'Wait for the post-credits',
    ];
    _shuffledPhrases = phrases..shuffle();

    _scrollController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      width: 300,
      child: ShaderMask(
        shaderCallback: (rect) {
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0),
              Colors.black,
              Colors.black,
              Colors.black.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ).createShader(rect);
        },
        blendMode: BlendMode.dstIn,
        child: AnimatedBuilder(
          animation: _scrollController,
          builder: (context, child) {
            final double totalScroll = _shuffledPhrases.length * _itemHeight;
            final double currentOffset = _scrollController.value * totalScroll;

            return Stack(
              children: List.generate(_shuffledPhrases.length, (index) {
                final double itemY = (index * _itemHeight) - currentOffset + 50;

                // Opacity and scale based on position
                double opacity = 1.0;
                if (itemY < 0 || itemY > 100) {
                  opacity = (1.0 - ((itemY - 50).abs() / 50)).clamp(0.0, 1.0);
                }

                final bool isCompleted = itemY < 45;

                return Positioned(
                  top: itemY,
                  left: 0,
                  right: 0,
                  child: Opacity(
                    opacity: opacity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          _buildCheckmark(isCompleted),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Text(
                              '${_shuffledPhrases[index]}...',
                              style: TextStyle(
                                color: isCompleted
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.6),
                                fontSize: 18,
                                fontWeight: isCompleted
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                shadows: isCompleted
                                    ? [
                                        const Shadow(
                                          color: Colors.white,
                                          blurRadius: 8,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCheckmark(bool isCompleted) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _netflixRed, width: 2),
        color: isCompleted
            ? _netflixRed.withValues(alpha: 0.2)
            : Colors.transparent,
      ),
      child: isCompleted
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }
}

class DiscoveryLoadingView extends StatefulWidget {
  final String? backdropUrl;
  final String? posterUrl;
  final String title;
  final String? logoUrl;
  final String? seasonEpisode;
  final List<String>? genres;
  final String? overview;
  final VoidCallback? onCancel;

  const DiscoveryLoadingView({
    super.key,
    this.backdropUrl,
    this.posterUrl,
    required this.title,
    this.logoUrl,
    this.seasonEpisode,
    this.genres,
    this.overview,
    this.onCancel,
  });

  @override
  State<DiscoveryLoadingView> createState() => DiscoveryLoadingViewState();
}

class DiscoveryLoadingViewState extends State<DiscoveryLoadingView>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));

    // Wait for screen rotation to fully settle, then animate everything in
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _animController.forward();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final posterH = screenH * 0.68;
    final posterW = posterH * 0.67;

    return Container(
      color: Colors.black,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Background: Backdrop image (dulled) ──
              if (widget.backdropUrl != null && widget.backdropUrl!.isNotEmpty) ...[
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: widget.backdropUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withValues(alpha: 0.88),
                          Colors.black.withValues(alpha: 0.72),
                          Colors.black.withValues(alpha: 0.80),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              // ── Main Content: Poster LEFT, Info RIGHT ──
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: screenW * 0.06,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── LEFT: Poster only ──
                      if (widget.posterUrl != null && widget.posterUrl!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: CachedNetworkImage(
                            imageUrl: widget.posterUrl!,
                            height: posterH,
                            width: posterW,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              height: posterH,
                              width: posterW,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            errorWidget: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),

                      const SizedBox(width: 28),

                      // ── RIGHT: Title + Season + Genres + Description ──
                      // Constrained so description wraps nicely
                      SizedBox(
                        width: screenW * 0.45,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Logo or Title
                            if (widget.logoUrl != null && widget.logoUrl!.isNotEmpty)
                              CachedNetworkImage(
                                imageUrl: widget.logoUrl!,
                                height: 48,
                                fit: BoxFit.contain,
                                alignment: Alignment.centerLeft,
                                errorWidget: (_, __, ___) => Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              )
                            else
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                              ),

                            // Season / Episode (same white color, series only)
                            if (widget.seasonEpisode != null) ...[
                              const SizedBox(height: 5),
                              Text(
                                widget.seasonEpisode!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],

                            const SizedBox(height: 14),

                            // Genres (smaller)
                            if (widget.genres != null && widget.genres!.isNotEmpty) ...[
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: widget.genres!.take(5).map((g) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.15),
                                    ),
                                  ),
                                  child: Text(
                                    g,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )).toList(),
                              ),
                              const SizedBox(height: 14),
                            ],

                            // Description (constrained, wraps to more lines)
                            if (widget.overview != null && widget.overview!.isNotEmpty)
                              Text(
                                widget.overview!,
                                maxLines: 8,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── CENTER BOTTOM: Spinner ──
              Positioned(
                bottom: screenH * 0.05,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onCancel != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 16,
                  child: Material(
                    color: Colors.transparent,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 24),
                      onPressed: widget.onCancel,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}