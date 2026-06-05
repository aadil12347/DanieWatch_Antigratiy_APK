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

    if (widget.isOffline || widget.isDirectLink) {
      _isExtracting = false;
      _isLoading = false;
      if (widget.extractedStreams != null && widget.extractedStreams!.isNotEmpty) {
        _selectedServer = widget.extractedStreams!.keys.first;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_selectedServer != null && widget.extractedStreams != null) {
          final stream = widget.extractedStreams![_selectedServer!];
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

  /// Extract the Fade Hindi stream from Videasy using headless WebView,
  /// then play natively in BetterPlayer. Falls back to WebView player
  /// if extraction fails or times out.
  Future<void> _tryDirectExtraction() async {
    String videasyUrl;
    if (widget.mediaType == 'movie') {
      videasyUrl = 'https://player.videasy.net/movie/${widget.tmdbId}';
    } else {
      final s = _currentSeason ?? widget.season ?? 1;
      final e = _currentEpisode ?? widget.episode ?? 1;
      videasyUrl = 'https://player.videasy.net/tv/${widget.tmdbId}/$s/$e';
    }

    debugPrint('[Engine] Starting Fade Hindi extraction from: $videasyUrl');

    try {
      final streams = await VideasyExtractorService().extractAllStreams(videasyUrl);

      if (!mounted) return;

      if (streams != null && streams.isNotEmpty) {
        // Pick Fade Hindi server, or first available
        String? bestServer;
        for (final key in streams.keys) {
          if (key.toLowerCase().contains('fade') || key.toLowerCase().contains('hindi')) {
            bestServer = key;
            break;
          }
        }
        bestServer ??= streams.keys.first;

        final stream = streams[bestServer]!;
        debugPrint('[Engine] ✅ Extracted Fade Hindi: ${stream.url}');
        debugPrint('[Engine]    Server: $bestServer, Sources: ${stream.sources.length}, Tracks: ${stream.tracks.length}');

        setState(() {
          _selectedServer = bestServer;
          _isExtracting = false;
          _discoveryComplete = true;
        });

        // Play in BetterPlayer (native)
        _startPlayback(stream.url, extractedStream: stream);
      } else {
        // Extraction failed — fall back to WebView player
        debugPrint('[Engine] ⚠️ Extraction failed, falling back to WebView player');
        setState(() {
          _extractedLink = videasyUrl;
          _isExtracting = false;
          _discoveryComplete = true;
          _useWebViewEngine = true;
          _isLoading = false;
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('[Engine] ❌ Extraction error: $e — falling back to WebView');
      if (mounted) {
        setState(() {
          _extractedLink = videasyUrl;
          _isExtracting = false;
          _discoveryComplete = true;
          _useWebViewEngine = true;
          _isLoading = false;
          _isInitialized = true;
        });
      }
    }
  }

  void _startPlayback(String link, {bool isOffline = false, ExtractedVideasyStream? extractedStream}) {
    debugPrint('[Playback] Starting for link: $link (isOffline: $isOffline)');
    setState(() {
      _extractedLink = link;
      _isLoading = true;
      _isExtracting = false;
      _isInitialized = false;
      _useWebViewEngine = false; // Reset initially, will switch below
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
      // We now prefer BetterPlayer (Native) for online streams as per analysis recommendations
      _initializeBetterPlayer(link, isOffline: false, extractedStream: extractedStream);
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
    if (mounted) {
      setState(() {
        _useWebViewEngine = true;
        _isLoading = false;
        _isInitialized = true; // WebView is "ready" by itself
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

    return _DiscoveryLoadingView(
      key: key,
      backdropUrl: content?.backdropUrl,
      posterUrl: content?.posterUrl,
      title: widget.title,
      logoUrl: content?.displayLogoUrl,
      seasonEpisode: seasonEpisode,
      genres: content?.genres,
      overview: content?.overview ?? content?.description,
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
    // Unique key based on extracted link ensures WebView reloads for new episodes
    final webKey = _extractedLink != null
        ? ValueKey('web_player_${_extractedLink!.hashCode}')
        : const ValueKey('web_player_default');

    return Container(
      key: key,
      child: InAppWebView(
        key: webKey,
        initialUrlRequest: URLRequest(
          url: WebUri(_extractedLink ?? 'about:blank'),
          headers: {
            'Referer': 'https://player.videasy.net/',
            'Origin': 'https://player.videasy.net',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        ),
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
        ),
        onWebViewCreated: (controller) {
          if (_isClosing) return; // Don't set up handlers if already closing
          _webViewController = controller;
          controller.addJavaScriptHandler(
            handlerName: 'goBack',
            callback: (args) {
              if (_isClosing) return;
              _goBack();
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
        },
        onLoadStart: (controller, url) async {
          // Prevent removeChild errors early
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
          if (navigationAction.isForMainFrame && !url.contains('videasy.net')) {
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
        onLoadStop: (controller, url) async {
          debugPrint('[Engine] Web Player Loaded: $url');
          
          await controller.evaluateJavascript(
            source: """
            (function() {
              // Re-inject safe removeChild just in case
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

              // Hide annoying UI if any
              var style = document.createElement('style');
              style.innerHTML = `
                .header, .footer, .ad-banner { display: none !important; }
              `;
              document.head.appendChild(style);

              // Click interception for debugging
              document.addEventListener('click', function(e) {
                try {
                  var el = e.target;
                  var path = [];
                  var curr = el;
                  while (curr && curr.nodeType === Node.ELEMENT_NODE) {
                    var selector = curr.nodeName.toLowerCase();
                    if (curr.id) {
                      selector += '#' + curr.id;
                    } else if (curr.className && typeof curr.className === 'string') {
                      selector += '.' + curr.className.trim().replace(/\s+/g, '.');
                    }
                    path.unshift(selector);
                    curr = curr.parentNode;
                  }
                  
                  window.flutter_inappwebview.callHandler('logClick', {
                    tagName: el.tagName,
                    className: el.className,
                    id: el.id,
                    text: el.textContent ? el.textContent.trim().substring(0, 100) : '',
                    src: el.src || '',
                    path: path.join(' > ')
                  });
                } catch(err) {}
              }, true);

              // Fetch interception for debugging
              const originalFetch = window.fetch;
              window.fetch = async function(...args) {
                try {
                  window.flutter_inappwebview.callHandler('logNetwork', {
                    type: 'fetch',
                    url: args[0]
                  });
                } catch(err) {}
                return await originalFetch.apply(this, args);
              };

              // XHR interception for debugging
              const originalXHR = window.XMLHttpRequest.prototype.open;
              window.XMLHttpRequest.prototype.open = function(method, url) {
                try {
                  window.flutter_inappwebview.callHandler('logNetwork', {
                    type: 'xhr',
                    method: method,
                    url: url
                  });
                } catch(err) {}
                return originalXHR.apply(this, arguments);
              };
              
              // No auto-clicker for now to let user interact and we observe

              // Seek to saved position for Continue Watching resume using a robust watcher
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

        // 1. Discovery handled by headless service

        // 2. Background Extraction for switching
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
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: _isExtracting
                ? _buildDiscoveryProgress(key: const ValueKey('loader'))
                : _useWebViewEngine
                    ? _buildWebPlayer(key: const ValueKey('web_player'))
                    : (!_isInitialized || _isLoading)
                        ? _buildLoadingState(key: const ValueKey('prep'))
                        : _buildPlayerInterface(),
          ),
        ),

        // 4. Back button during extraction
        if (_isExtracting && !_useWebViewEngine)
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: LiquidTapEffect(
                  onTap: _goBack,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ),
                ),
              ),
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
    // Only show if we have languages or resolutions to switch
    final hasLanguages = widget.extractedStreams != null && widget.extractedStreams!.length > 1;
    final hasResolutions = _explicitResolutions != null && _explicitResolutions!.length > 1;

    if (!hasLanguages && !hasResolutions) return const SizedBox.shrink();

    return Positioned(
      bottom: 80, // Sit above the native BetterPlayer bottom controls
      right: 16,
      child: SafeArea(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasLanguages)
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
                    value: _selectedServer,
                    icon: const Icon(Icons.language, color: Colors.white, size: 18),
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    onChanged: (String? newValue) {
                      if (newValue != null && newValue != _selectedServer) {
                        setState(() {
                          _selectedServer = newValue;
                          // Reset resolution when changing server
                          _selectedResolution = null; 
                        });
                        final newStream = widget.extractedStreams![newValue]!;
                        _startPlayback(newStream.url, extractedStream: newStream);
                      }
                    },
                    items: widget.extractedStreams!.keys.map<DropdownMenuItem<String>>((String value) {
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
                        // BetterPlayer setResolution handles keeping the current position
                        try {
                           _betterPlayerController?.setResolution(resUrl);
                        } catch (e) {
                           debugPrint('[BetterPlayer] Error setting resolution: $e');
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

// ─── Discovery Loading View (animated, self-contained) ───────────────────────
class _DiscoveryLoadingView extends StatefulWidget {
  final String? backdropUrl;
  final String? posterUrl;
  final String title;
  final String? logoUrl;
  final String? seasonEpisode;
  final List<String>? genres;
  final String? overview;

  const _DiscoveryLoadingView({
    super.key,
    this.backdropUrl,
    this.posterUrl,
    required this.title,
    this.logoUrl,
    this.seasonEpisode,
    this.genres,
    this.overview,
  });

  @override
  State<_DiscoveryLoadingView> createState() => _DiscoveryLoadingViewState();
}

class _DiscoveryLoadingViewState extends State<_DiscoveryLoadingView>
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
            ],
          ),
        ),
      ),
    );
  }
}