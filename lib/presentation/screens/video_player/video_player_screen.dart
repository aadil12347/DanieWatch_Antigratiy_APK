import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import 'package:daniewatch_app/services/bysebuho_extractor.dart';
import '../../providers/detail_provider.dart';
import '../../providers/watch_history_provider.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final String url;
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

  const VideoPlayerScreen({
    super.key,
    required this.url,
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
  });

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen>
    with TickerProviderStateMixin {
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

  @override
  void initState() {
    super.initState();
    _currentSeason = widget.season;
    _currentEpisode = widget.episode;

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startPlayback(widget.url, isOffline: widget.isOffline);
      });
      return;
    }

    _isExtracting = true;
    _isLoading = false;

    // Try direct Bysebuho API extraction first (much faster ~1-2s)
    _tryDirectExtraction(widget.url);

    // Start periodic progress save timer (every 15 seconds)
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _saveToWatchHistory();
    });
  }

  /// Try direct Bysebuho API extraction first (much faster ~1-2s vs 10-20s WebView)
  Future<void> _tryDirectExtraction(String url) async {
    final bysebuho = BysebuhoExtractor.instance;
    if (!bysebuho.isBysebuhoUrl(url)) {
      // Not a bysebuho URL, fall back to WebView extraction
      _startExtractionProcess(timeout: const Duration(seconds: 7));
      return;
    }

    debugPrint('[DirectExtraction] Trying direct Bysebuho API for: $url');
    final result = await bysebuho.extract(url);
    if (result != null && mounted) {
      debugPrint('[DirectExtraction] ✅ Success! Master: ${result.masterUrl}');
      setState(() {
        _isExtracting = false;
        _discoveryComplete = true;
      });
      _startPlayback(result.masterUrl);
      return;
    }

    // Direct extraction failed, fall back to WebView
    debugPrint('[DirectExtraction] Failed, falling back to WebView...');
    if (mounted) {
      _startExtractionProcess(timeout: const Duration(seconds: 7));
    }
  }

  void _startExtractionProcess({required Duration timeout}) {
    // Progressive timeout logic
    _bgDiscoveryTimer?.cancel();
    _bgDiscoveryTimer = Timer(timeout, () {
      if (mounted && !_discoveryComplete) {
        debugPrint(
          '[Discovery] 30s absolute limit reached. Finalizing discovery.',
        );
        _completeDiscovery();
      }
    });

    // Start background auto-clicker running every 1.5 seconds
    _autoClickTimer = Timer.periodic(const Duration(milliseconds: 1000), (
      timer,
    ) {
      if (_discoveryComplete) {
        timer.cancel();
        return;
      }
      debugPrint('[Extraction] Auto-clicking in background wrapper...');
      final controller = _webViewController;
      if (controller != null && mounted && !_discoveryComplete) {
        try {
          controller.evaluateJavascript(
            source: """
            (function() {
              var buttons = document.querySelectorAll('.play-btn, .vjs-big-play-button, .jw-display-icon-display, .plyr__control--overlaid');
              for(var i=0; i<buttons.length; i++) {
                buttons[i].click();
              }
              var el = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
              if (el) {
                el.click();
                console.log('Antigravity: Auto-clicked element at center.');
              }
              var v = document.querySelector('video');
              if (v) { v.play().catch(function(e){}); }
            })();
          """,
          ).catchError((e) {
            if (!e.toString().contains('disposed')) {
              debugPrint('[Extraction] Auto-click failed: $e');
            }
          });
        } catch (e) {
          if (!e.toString().contains('disposed')) {
            debugPrint('[Extraction] Auto-click Error: $e');
          }
        }
      }
    });
  }

  void _handleExtractedLink(String link) {
    if (_discoveryComplete) return;

    final lowerLink = link.toLowerCase();

    // Only process .m3u8 or video files
    if (!lowerLink.contains('.m3u8') && !lowerLink.contains('.mp4')) return;
    if (lowerLink.contains('ads')) return;

    if (!_discoveredLinks.contains(link)) {
      debugPrint('[Discovery] New link added to pool: $link');
      _discoveredLinks.add(link);
    }

    if (lowerLink.contains('master.m3u8') || lowerLink.contains('.urlset')) {
      debugPrint(
        '[Discovery] Master found via Auto-Extraction! Stopping early.',
      );
      _masterWaitTimer?.cancel();
      // Add a tiny delay to grab any other nearby variants just in case
      _masterWaitTimer = Timer(const Duration(milliseconds: 200), () {
        _completeDiscovery();
      });
    } else if (_masterWaitTimer == null) {
      // Found a fallback link. Wait 3 seconds to give master time to appear
      debugPrint(
        '[Discovery] Fallback found. Waiting to see if master appears...',
      );
      _masterWaitTimer = Timer(const Duration(milliseconds: 1500), () {
        _completeDiscovery();
      });
    }
  }

  void _completeDiscovery() {
    if (_isInitialized || _discoveryComplete) return;

    debugPrint('[Discovery] Analyzing ${_discoveredLinks.length} links...');

    String? bestLink;

    // 1. Search for Master Playlists (contains 'master.m3u8' or '.urlset')
    final masterLinks = _discoveredLinks
        .where((l) => l.contains('master.m3u8') || l.contains('.urlset'))
        .toList();
    if (masterLinks.isNotEmpty) {
      // Prioritize master links with longest length or most query parameters (often more complete)
      masterLinks.sort((a, b) => b.length.compareTo(a.length));
      bestLink = masterLinks.first;
      debugPrint('[Discovery] Selected BEST MASTER Link: $bestLink');
    }
    // 2. Fallback to high quality variant
    else {
      final highQuality = _discoveredLinks
          .where(
            (l) => l.contains('_h') || l.contains('1080') || l.contains('720'),
          )
          .toList();
      if (highQuality.isNotEmpty) {
        highQuality.sort((a, b) => b.length.compareTo(a.length));
        bestLink = highQuality.first;
        debugPrint('[Discovery] Selected HIGH QUALITY Link: $bestLink');
      } else if (_discoveredLinks.isNotEmpty) {
        bestLink = _discoveredLinks.first;
        debugPrint('[Discovery] Selected FALLBACK Link: $bestLink');
      }
    }

    if (mounted) {
      if (bestLink != null) {
        setState(() {
          _isExtracting = false;
          _discoveryComplete = true;
          _webViewController = null;
        });
        _autoClickTimer?.cancel();
        _bgDiscoveryTimer?.cancel();
        _masterWaitTimer?.cancel();
        _extractionTimer?.cancel();

        _startPlayback(bestLink);
      } else {
        // Double-Pass Auto-Recovery: First failure is silent
        if (_retryCount == 0) {
          debugPrint(
            '[Discovery] Initial failure (10s). Triggering SILENT Nuclear Reset...',
          );
          _retry();
          return;
        }

        debugPrint('[Discovery] No valid links found. Showing error.');
        setState(() {
          _isExtracting = false;
          _hasError = true;
          _discoveryComplete = true;
          _webViewController = null;
          _extractionError = 'Please close and open again';
        });
        _autoClickTimer?.cancel();
        _bgDiscoveryTimer?.cancel();
        _masterWaitTimer?.cancel();
        _extractionTimer?.cancel();
        
        // Auto-close after 5 seconds on error
        _errorAutoCloseTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    }
  }

  void _startPlayback(String link, {bool isOffline = false}) {
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

    if (isOffline) {
      _initializeBetterPlayer(link, isOffline: true);
    } else {
      // Custom Player Restoration: Favor Web Engine (hls.js) as per commit 133b287
      _switchToWebEngine();
    }
  }

  Future<void> _initializeBetterPlayer(
    String url, {
    bool isOffline = false,
  }) async {
    try {
      if (_betterPlayerController != null) {
        _betterPlayerController!.dispose();
      }

      debugPrint(
        '[BetterPlayer] Initializing for: $url (isOffline: $isOffline)',
      );

      BetterPlayerDataSource dataSource = BetterPlayerDataSource(
        isOffline
            ? BetterPlayerDataSourceType.file
            : BetterPlayerDataSourceType.network,
        url,
        useAsmsAudioTracks: true,
        useAsmsTracks: true,
        useAsmsSubtitles: true,
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

      // Listen for errors to auto-switch to WebView if needed
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
    } catch (e) {
      debugPrint('[BetterPlayer] Setup error: $e');
      _switchToWebEngine();
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
        final episode = episodesAsync.valueOrNull?[_extractingEpisodeIndex!];

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
      if (posterUrl != null && !posterUrl.startsWith('http')) {
        posterUrl = 'https://image.tmdb.org/t/p/w500$posterUrl';
      }
      backdropUrl = detail?.backdropUrl;
      if (backdropUrl != null && !backdropUrl.startsWith('http')) {
        backdropUrl = 'https://image.tmdb.org/t/p/w780$backdropUrl';
      }
    } catch (_) {}

    // Get episode title
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
        final ep = epsAsync.valueOrNull?.firstWhere(
          (e) => e.episodeNumber == _currentEpisode,
          orElse: () => epsAsync.valueOrNull!.first,
        );
        episodeTitle = ep?.title;
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
      playUrl: _currentExtractionUrl ?? widget.url,
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
            const SizedBox(height: 20),
            Text(
              'Please wait',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Loading $epLabel',
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveryProgress({Key? key}) {
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
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Please wait',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Loading $epLabel',
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _retry() {
    _retryCount++;
    debugPrint('[Retry] Attempt #$_retryCount - Triggering Nuclear Reset...');

    _bgDiscoveryTimer?.cancel();
    _masterWaitTimer?.cancel();
    _autoClickTimer?.cancel();

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

    // Nuclear Reset: Clear Cookies and Caches
    CookieManager.instance().deleteAllCookies();

    // Nuclear Reset: Change Key to force WebView to be destroyed and recreated
    _webViewKey = ValueKey(
      'discovery_webview_${DateTime.now().millisecondsSinceEpoch}',
    );

    // Determine next timeout:
    // Attempt 1 (Auto-Retry after 10s fail): 20s
    // Attempt 2+ (Manual Retries): 30s
    Duration nextTimeout = (_retryCount == 1)
        ? const Duration(seconds: 12)
        : const Duration(seconds: 15);

    debugPrint('[Retry] Next timeout set to: ${nextTimeout.inSeconds}s');
    _startExtractionProcess(timeout: nextTimeout);
    setState(() {});
  }

  Future<void> _goBack() async {
    if (!mounted) return;

    // Save watch progress before leaving
    _saveToWatchHistory();

    // If we're extracting an episode, stop that first
    if (_isBgExtracting) {
      setState(() {
        _isBgExtracting = false;
        _extractingEpisodeIndex = null;
      });
      _bgAutoClickTimer?.cancel();
      _bgTimeoutTimer?.cancel();
      _bgMasterWaitTimer?.cancel();
    }

    // Force portrait orientation before popping to prevent being stuck in landscape
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    setState(() {
      _canPop = true;
    });

    if (mounted) {
      Navigator.of(context).pop();
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
    _tryDirectExtraction(nextEp.playLink!);
  }

  @override
  void dispose() {
    _saveToWatchHistory();
    _errorAutoCloseTimer?.cancel();
    _progressSaveTimer?.cancel();
    _betterPlayerController?.dispose();
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
        initialFile: 'assets/html/player.html',
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          allowsInlineMediaPlayback: true,
          mediaPlaybackRequiresUserGesture: false,
          useShouldOverrideUrlLoading: true,
        ),
        onWebViewCreated: (controller) {
          _webViewController = controller;
          controller.addJavaScriptHandler(
            handlerName: 'goBack',
            callback: (args) {
              _saveToWatchHistory();
              _goBack();
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'showEpisodes',
            callback: (args) => _showEpisodeSelector(),
          );
          controller.addJavaScriptHandler(
            handlerName: 'playNextEpisode',
            callback: (args) {
              _saveToWatchHistory();
              _playNextEpisode();
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'saveWatchProgress',
            callback: (args) {
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
              HapticFeedback.lightImpact();
            },
          );
        },
        onLoadStop: (controller, url) async {
          debugPrint('[Engine] Web Player Loaded: $url');
          if (_extractedLink != null) {
            await controller.evaluateJavascript(
              source: "playVideo('$_extractedLink')",
            );

            // Seek to saved position for Continue Watching resume
            if (!_startPositionApplied && widget.startPosition != null && widget.startPosition! > 5) {
              _startPositionApplied = true;
              await controller.evaluateJavascript(
                source: "seekToPosition(${widget.startPosition})",
              );
              debugPrint('[Resume] Seeking to ${widget.startPosition}s');
            }

            const epText = 'Episodes';
            await controller.evaluateJavascript(
              source: "updateEpisodeButton('$epText')",
            );

            final displayTitle = widget.mediaType != 'movie' &&
                    _currentSeason != null &&
                    _currentEpisode != null
                ? 'S${_currentSeason.toString().padLeft(2, '0')} E${_currentEpisode.toString().padLeft(2, '0')}'
                : widget.title;

            await controller.evaluateJavascript(
              source: "videoTitle('$displayTitle')",
            );
            await controller.evaluateJavascript(
              source: "setMediaType('${widget.mediaType}')",
            );

            // Send next episode title for auto-play overlay
            if (widget.mediaType != 'movie') {
              final episodesAsync = ref.read(
                episodesProvider(
                  EpisodeParams(
                    tmdbId: widget.tmdbId,
                    seasonNumber: _currentSeason ?? 1,
                  ),
                ),
              );
              final epsList = episodesAsync.valueOrNull;
              if (epsList != null) {
                final curIdx = epsList.indexWhere(
                  (e) => e.episodeNumber == _currentEpisode,
                );
                if (curIdx >= 0 && curIdx + 1 < epsList.length) {
                  final nextEp = epsList[curIdx + 1];
                  final nextTitle = 'EP ${nextEp.episodeNumber}: ${nextEp.title ?? 'Episode ${nextEp.episodeNumber}'}';
                  final escaped = nextTitle.replaceAll("'", "\\'");
                  await controller.evaluateJavascript(
                    source: "setNextEpisodeInfo('$escaped')",
                  );
                }
              }
            }
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
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.05,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: DropdownButton<int>(
                                          value: tempSeason,
                                          dropdownColor: const Color(
                                            0xFF1A1A1A,
                                          ),
                                          underline: const SizedBox(),
                                          isExpanded: true,
                                          icon: const Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            color: Colors.white38,
                                          ),
                                          items: List.generate(
                                            widget.seasons?.length ?? 0,
                                            (i) => DropdownMenuItem(
                                              value: widget.seasons![i],
                                              child: Text(
                                                'Season ${widget.seasons![i]}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setModalState(
                                                () => tempSeason = val,
                                              );
                                            }
                                          },
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

                                          return ListView.builder(
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
                                                    _tryDirectExtraction(
                                                      ep.playLink!,
                                                    );
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

        // 1. Discovery/Extraction WebView (Hidden in background)
        if (!_discoveryComplete)
          SizedBox(
            height: 1,
            width: 1,
            child: InAppWebView(
              key: _webViewKey,
              initialUrlRequest: URLRequest(
                url: WebUri(_currentExtractionUrl ?? widget.url),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                allowsInlineMediaPlayback: true,
                mediaPlaybackRequiresUserGesture: false,
                useShouldOverrideUrlLoading: true,
                useOnLoadResource: true,
                javaScriptCanOpenWindowsAutomatically: false,
                supportMultipleWindows: true,
              ),
              onWebViewCreated: (controller) => _webViewController = controller,
              onCreateWindow: (controller, createWindowAction) async {
                return true;
              },
              onLoadResource: (controller, resource) {
                if (resource.url != null) {
                  _handleExtractedLink(resource.url.toString());
                }
              },
            ),
          ),

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
            child: _hasError
                ? _buildErrorOverlay()
                : _isExtracting
                    ? _buildDiscoveryProgress(key: const ValueKey('loader'))
                    : _useWebViewEngine
                        ? _buildWebPlayer(key: const ValueKey('web_player'))
                        : (!_isInitialized || _isLoading)
                            ? _buildLoadingState(key: const ValueKey('prep'))
                            : _buildPlayerInterface(),
          ),
        ),

        // 4. Back button during extraction
        if (!_hasError && _isExtracting && !_useWebViewEngine)
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GestureDetector(
                  onTap: _goBack,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 26,
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
              _buildTopBar(),
              _buildEpisodeInfoOverlay(),
              _buildControlHints(),
            ],
          ),
        ),
      ],
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
    // Auto-close player after 5 seconds on error
    _errorAutoCloseTimer?.cancel();
    _errorAutoCloseTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _hasError) {
        _goBack();
      }
    });

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
