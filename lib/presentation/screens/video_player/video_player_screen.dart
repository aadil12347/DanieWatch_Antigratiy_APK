import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'dart:ui' show ImageFilter, FontFeature;

import '../../providers/detail_provider.dart';
import '../../providers/watch_history_provider.dart';
import '../../widgets/sticky_dropdown_modal.dart';
import '../../../pip/pip_controller.dart';
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
  final Map<String, PeachifyStream>? extractedStreams;
  final bool is3rdPartyHosted;

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
    this.is3rdPartyHosted = false,
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
  bool _hasVideoStarted = false;
  String? _extractionError;
  String? _extractedLink;
  InAppWebViewController? _webViewController;
  Timer? _extractionTimer;
  Timer? _fallbackTimer;



  // Extraction Window variables
  Timer? _masterWaitTimer;
  Timer? _autoClickTimer;
  Timer? _bgDiscoveryTimer;
  final Set<String> _discoveredLinks = {};



  // Watch progress tracking
  double _lastCurrentTime = 0;
  double _lastDuration = 0;
  Timer? _errorAutoCloseTimer;
  Timer? _progressSaveTimer;  // Periodic Dart-side save
  bool _startPositionApplied = false;  // Track if we've seeked to startPosition

  // Native Control State
  bool _areControlsVisible = true;
  Timer? _controlsTimer;
  bool _isLocked = false;
  double _brightness = 0.5;
  double _volume = 1.0;
  bool _showBrightnessIndicator = false;
  bool _showVolumeIndicator = false;
  Timer? _brightnessTimer;
  Timer? _volumeTimer;
  double _playbackSpeed = 1.0;
  bool _isMuted = false;
  double _preMuteVolume = 1.0;
  bool _showSpeedPill = false;
  bool _showLeftRipple = false;
  bool _showRightRipple = false;
  Timer? _leftRippleTimer;
  Timer? _rightRippleTimer;
  String? _notifyPillText;
  Timer? _notifyPillTimer;
  Timer? _singleTapTimer;
  DateTime? _lastTapUpTime;
  AnimationController? _speedPillController;
  Animation<Color?>? _speedPillColorAnimation;

  // Gesture drag accumulators & activity flags
  double _volumeDragAccumulator = 0.0;
  bool _volumeDragActive = false;
  double _brightnessDragAccumulator = 0.0;
  bool _brightnessDragActive = false;

  // PiP mode state
  bool _isInPipMode = false;

  // Episode Info
  int? _currentEpisode;
  int? _currentSeason;
  String? _episodeSearchQuery;
  final TextEditingController _searchController = TextEditingController();

  // Extraction State
  BetterPlayerController? _betterPlayerController;
  final GlobalKey _betterPlayerKey = GlobalKey();
  bool _useWebViewEngine = false;
  int _retryCount = 0;
  String? _currentExtractionUrl;
  bool _canPop = false;
  bool _isClosing = false; // Prevents double pops/crashes when pressing back
  String? _selectedServer;
  String? _selectedResolution;
  Map<String, String>? _explicitResolutions;
  Map<String, PeachifyStream>? _currentStreamsMap;
  Map<String, Map<String, String>> _vcloudServerMap = {};
  final Set<String> _failedVcloudCombinations = {};
  String _activeServer = 'Server 1';
  int _selectedAudioIndex = 0;
  double? _resumeTimeOverride;
  double? _seekingToTime;
  Timer? _seekTimeoutTimer;
  Timer? _playbackWatchdogTimer;
  bool _isSwipeSeeking = false;
  double _swipeSeekTarget = 0.0;
  double _swipeSeekStartValue = 0.0;
  String? _activeVerticalDrag;
  bool _wasPlayingBeforeFastForward = true;

  // Real-time extraction tracking variables
  bool _isBackgroundExtracting = false;
  List<String> _dbResolutions = [];
  final ValueNotifier<int> _vcloudUpdateNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _resumeTimeOverride = widget.startPosition?.toDouble();
    _speedPillController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _speedPillColorAnimation = ColorTween(
      begin: Colors.white,
      end: Colors.white30,
    ).animate(
      CurvedAnimation(
        parent: _speedPillController!,
        curve: Curves.easeInOut,
      ),
    );
    _speedPillController!.repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);
    _currentSeason = widget.season;
    _currentEpisode = widget.episode;

    // Set up PiP mode change listener
    PipController.instance.onPipModeChanged = (isInPip) {
      if (mounted) {
        setState(() => _isInPipMode = isInPip);
      }
    };

    // Handle PiP action buttons (play/pause, seek backward/forward)
    PipController.instance.onPipAction = (action) {
      if (!mounted || _betterPlayerController == null) return;
      debugPrint('[PIP] Handling action: $action');
      switch (action) {
        case 'play':
          _betterPlayerController?.play();
          break;
        case 'pause':
          _betterPlayerController?.pause();
          break;
        case 'seekForward':
          final newPos = (_lastCurrentTime + 10).clamp(0.0, _lastDuration);
          _betterPlayerController?.seekTo(Duration(seconds: newPos.toInt()));
          break;
        case 'seekBackward':
          final newPos = (_lastCurrentTime - 10).clamp(0.0, _lastDuration);
          _betterPlayerController?.seekTo(Duration(seconds: newPos.toInt()));
          break;
      }
    };

    _initBrightness();
    _initVolume();
    _resetControlsTimer();

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

    // 3rd party hosted items skip Vcloud — go straight to VidNest/Peachify WebView
    if (widget.is3rdPartyHosted) {
      debugPrint('[Engine] 3rd party hosted item — skipping Vcloud, using VidNest/Peachify WebView.');
      _tryVidNestPeachifyExtraction();
    } else {
      // Try direct Vcloud API extraction first (much faster ~1-2s)
      _tryDirectExtraction();
    }

    // Start periodic progress save timer (every 15 seconds)
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _saveToWatchHistory();
    });
  }
  PeachifyStream? _extractedStream;

  /// Start the extraction using Vcloud database service.
  Future<void> _tryDirectExtraction() async {
    final s = _currentSeason ?? widget.season ?? 1;
    final e = _currentEpisode ?? widget.episode ?? 1;

    debugPrint('[Engine] Starting Vcloud database extraction in player screen');
    setState(() {
      _isExtracting = true;
      _isLoading = false;
      _hasError = false;
      _isBackgroundExtracting = false;
      _dbResolutions = [];
    });
    _vcloudUpdateNotifier.value++;

    // Start 30-second fallback timer
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_isClosing && _isExtracting) {
        debugPrint('[Engine] 30 seconds reached. Falling back to VidNest/Peachify extraction.');
        _tryVidNestPeachifyExtraction();
      }
    });

    try {
      final vcloudLinksMap = await VcloudExtractorService().fetchResolutionLinksMap(
        tmdbId: widget.tmdbId,
        mediaType: widget.mediaType,
        title: widget.title,
        season: widget.mediaType == 'movie' ? null : s,
        episode: widget.mediaType == 'movie' ? null : e,
      );

      if (!mounted || _isClosing) return;

      if (vcloudLinksMap.isEmpty) {
        debugPrint('[Engine] No streaming links found in Vcloud database. Waiting for fallback timer.');
        return;
      }

      setState(() {
        _dbResolutions = vcloudLinksMap.keys.toList();
      });
      _vcloudUpdateNotifier.value++;

      // Build preference list: 720p > 480p > 1080p > 4k
      final preferenceOrder = ['720p', '480p', '1080p', '4k'];
      final List<String> availableOrdered = [];
      for (final pref in preferenceOrder) {
        final match = vcloudLinksMap.keys.firstWhere(
          (k) => k.toLowerCase() == pref || k.toLowerCase().contains(pref.replaceAll('p', '')),
          orElse: () => '',
        );
        if (match.isNotEmpty && !availableOrdered.contains(match)) {
          availableOrdered.add(match);
        }
      }
      for (final k in vcloudLinksMap.keys) {
        if (!availableOrdered.contains(k)) {
          availableOrdered.add(k);
        }
      }

      bool startedPlayback = false;

      // Sequential fast-playback search (First Pass)
      for (final res in availableOrdered) {
        if (startedPlayback) break;

        final url = vcloudLinksMap[res]!;
        debugPrint('[Engine] Fast Pass: extracting servers for resolution $res');
        
        try {
          final resolved = await VcloudExtractorService().extractVcloud(url);
          if (!mounted || _isClosing) return;

          if (resolved.isNotEmpty) {
            final priorityServers = ['Server 1', 'Server 2', 'Server 3'];
            for (final srv in priorityServers) {
              if (resolved.containsKey(srv)) {
                var playUrl = resolved[srv]!;
                
                // If it is Server 3, resolve it
                if (srv == 'Server 3' && (playUrl.contains('hubcloud') || playUrl.contains('gpdl'))) {
                  debugPrint('[Engine] Fast Pass: Pre-resolving HubCloud redirect for Server 3...');
                  final resolvedUrl = await VcloudExtractorService().resolveHubCloudRedirect(playUrl);
                  if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
                    playUrl = resolvedUrl;
                  }
                }

                // Verify if the link is actually valid and playable
                debugPrint('[Engine] Fast Pass: Verifying direct link for $srv ($res)...');
                final isValid = await VcloudExtractorService().verifyDirectLink(playUrl);
                if (isValid) {
                  debugPrint('[Engine] Fast Pass: Direct link for $srv ($res) verified working! Starting playback...');
                  
                  if (!mounted || _isClosing) return;
                  
                  setState(() {
                    _vcloudServerMap.putIfAbsent(srv, () => {})[res] = playUrl;
                    _activeServer = srv;
                    _selectedServer = srv;
                    _selectedResolution = res;
                  });
                  _vcloudUpdateNotifier.value++;

                  startedPlayback = true;
                  await _startVcloudPlayback();
                  break; // break server loop
                } else {
                  debugPrint('[Engine] Fast Pass: Direct link for $srv ($res) failed verification.');
                }
              }
            }
          }
        } catch (err) {
          debugPrint('[Engine] Fast Pass failed for resolution $res: $err');
        }
      }

      // If we found a working link, fetch remaining servers/resolutions in the background
      if (startedPlayback) {
        // Fire-and-forget background extraction
        _extractRemainingLinksInBackground(vcloudLinksMap, availableOrdered);
      } else {
        // If all resolutions and servers failed in VCloud, fallback to VidNest/Peachify
        debugPrint('[Engine] Fast Pass failed for all resolutions. Falling back to VidNest/Peachify.');
        await _tryVidNestPeachifyExtraction();
      }

    } catch (err) {
      debugPrint('[Engine] Vcloud extraction failed: $err. Waiting for fallback timer.');
    }
  }

  Future<void> _extractRemainingLinksInBackground(
      Map<String, String> vcloudLinksMap, List<String> availableOrdered) async {
    debugPrint('[BackgroundExtractor] Starting background extraction for other servers and resolutions...');
    if (mounted) {
      setState(() {
        _isBackgroundExtracting = true;
      });
      _vcloudUpdateNotifier.value++;
    }
    
    for (final res in availableOrdered) {
      if (!mounted || _isClosing) return;
      
      final url = vcloudLinksMap[res]!;
      try {
        final resolved = await VcloudExtractorService().extractVcloud(url);
        if (!mounted || _isClosing) return;

        if (resolved.isNotEmpty) {
          final priorityServers = ['Server 1', 'Server 2', 'Server 3'];
          for (final srv in priorityServers) {
            if (!mounted || _isClosing) return;

            // Skip if already verified in the map
            if (_vcloudServerMap[srv]?.containsKey(res) == true) {
              continue;
            }

            if (resolved.containsKey(srv)) {
              var playUrl = resolved[srv]!;
              if (srv == 'Server 3' && (playUrl.contains('hubcloud') || playUrl.contains('gpdl'))) {
                final resolvedUrl = await VcloudExtractorService().resolveHubCloudRedirect(playUrl);
                if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
                  playUrl = resolvedUrl;
                }
              }

              // Verify
              final isValid = await VcloudExtractorService().verifyDirectLink(playUrl);
              if (isValid) {
                if (mounted) {
                  setState(() {
                    _vcloudServerMap.putIfAbsent(srv, () => {})[res] = playUrl;
                    
                    // If this is the active server, update explicit resolutions dropdown
                    if (srv == _activeServer) {
                      final resolutions = _vcloudServerMap[_activeServer];
                      if (resolutions != null) {
                        final sortedResKeys = resolutions.keys.toList();
                        sortedResKeys.sort((a, b) {
                          final aInt = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
                          final bInt = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
                          return aInt.compareTo(bInt);
                        });
                        final Map<String, String> explicitResolutions = {};
                        for (var key in sortedResKeys) {
                          explicitResolutions[key] = resolutions[key]!;
                        }
                        _explicitResolutions = explicitResolutions;
                      }
                    }
                  });
                  _vcloudUpdateNotifier.value++;
                  debugPrint('[BackgroundExtractor] Added verified $srv ($res) to server map.');
                }
              }
            }
          }
        }
      } catch (err) {
        debugPrint('[BackgroundExtractor] Failed extracting $res in background: $err');
      }
    }
    
    if (mounted) {
      setState(() {
        _isBackgroundExtracting = false;
      });
      _vcloudUpdateNotifier.value++;
    }
    debugPrint('[BackgroundExtractor] Background extraction finished.');
  }

  Future<void> _startVcloudPlayback() async {
    if (_isClosing) return;

    _fallbackTimer?.cancel();

    final resolutions = _vcloudServerMap[_activeServer];
    if (resolutions == null || resolutions.isEmpty) {
      debugPrint('[VcloudPlayer] No resolutions available for $_activeServer');
      _handleFailover();
      return;
    }

    // Sort resolutions: worst to best (360p -> 480p -> 720p -> 1080p)
    final sortedResKeys = resolutions.keys.toList();
    sortedResKeys.sort((a, b) {
      final aInt = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final bInt = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
      return aInt.compareTo(bInt);
    });

    // Try to preserve current resolution if available, otherwise fallback to closest to 720p
    String? targetRes = _selectedResolution;
    if (targetRes == null || !resolutions.containsKey(targetRes)) {
      try {
        targetRes = sortedResKeys.firstWhere((k) => k.contains('720'));
      } catch (_) {
        targetRes = sortedResKeys.last;
      }
    }

    _selectedResolution = targetRes;
    String playUrl = resolutions[targetRes]!;

    if (playUrl.contains('hubcloud') || playUrl.contains('gpdl')) {
      debugPrint('[VcloudPlayer] Resolving HubCloud redirect just-in-time...');
      setState(() {
        _isExtracting = true;
      });
      final gDriveUrl = await VcloudExtractorService().resolveHubCloudRedirect(playUrl);
      if (gDriveUrl != null && gDriveUrl.isNotEmpty) {
        playUrl = gDriveUrl;
        // Cache it back
        _vcloudServerMap[_activeServer]![targetRes] = playUrl;
        if (_selectedResolution == targetRes) {
          _explicitResolutions?[targetRes] = playUrl;
        }
        debugPrint('[VcloudPlayer] JIT resolved url: $playUrl');
      }

      // Verify JIT resolved URL is a valid playable video
      final isValid = await VcloudExtractorService().verifyDirectLink(playUrl);
      if (!isValid) {
        debugPrint('[VcloudPlayer] JIT resolved link failed verification. Handling failover.');
        _handleFailover();
        return;
      }
    }

    // Populate explicit resolutions for dropdown UI in ascending sorted order
    final Map<String, String> explicitResolutions = {};
    for (var key in sortedResKeys) {
      explicitResolutions[key] = resolutions[key]!;
    }
    _explicitResolutions = explicitResolutions;

    try {
      if (_betterPlayerController != null) {
        _betterPlayerController!.videoPlayerController?.removeListener(_videoPlayerListener);
        _betterPlayerController!.dispose();
        _betterPlayerController = null;
      }
    } catch (e) {
      debugPrint('[VcloudPlayer] Error disposing BetterPlayer: $e');
    }

    debugPrint('[VcloudPlayer] Playing in native BetterPlayer: $playUrl');

    setState(() {
      _isExtracting = false;
      _isLoading = true;
      _isInitialized = false;
      _useWebViewEngine = false; // Native player!
      _extractedLink = playUrl;
    });
    _vcloudUpdateNotifier.value++;

    _initializeBetterPlayer(playUrl, isOffline: false);

    // Watchdog: if video doesn't start within 20s, fall back to failover or WebView
    _playbackWatchdogTimer?.cancel();
    _playbackWatchdogTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted || _isClosing || _hasVideoStarted) return;
      debugPrint('[Watchdog] Video did not start within 20s on $_activeServer. Handling failover.');
      try {
        _betterPlayerController?.videoPlayerController?.removeListener(_videoPlayerListener);
        _betterPlayerController?.dispose();
        _betterPlayerController = null;
      } catch (_) {}
      _handleFailover();
    });
  }

  void _handleFailover() {
    if (!mounted || _isClosing) return;

    final currentKey = '${_activeServer}_$_selectedResolution';
    _failedVcloudCombinations.add(currentKey);
    debugPrint('[VcloudPlayer] Failover: Marked $currentKey as failed.');

    // Priority order for servers and resolutions
    final priorityServers = ['Server 1', 'Server 2', 'Server 3'];
    final priorityResolutions = ['720p', '480p', '1080p', '4k'];

    String? nextServer;
    String? nextRes = _selectedResolution;

    // 1. Try to find another server for the CURRENT resolution
    if (nextRes != null) {
      for (final srv in priorityServers) {
        final key = '${srv}_$nextRes';
        if (!_failedVcloudCombinations.contains(key) &&
            _vcloudServerMap[srv]?.containsKey(nextRes) == true) {
          nextServer = srv;
          break;
        }
      }
    }

    // 2. If no server found for current resolution, search other resolutions
    if (nextServer == null) {
      for (final res in priorityResolutions) {
        final matchedRes = _vcloudServerMap.values
            .expand((m) => m.keys)
            .cast<String?>()
            .firstWhere((k) => k!.toLowerCase() == res.toLowerCase() || k.toLowerCase().contains(res.replaceAll('p', '')), orElse: () => null);

        if (matchedRes != null) {
          for (final srv in priorityServers) {
            final key = '${srv}_$matchedRes';
            if (!_failedVcloudCombinations.contains(key) &&
                _vcloudServerMap[srv]?.containsKey(matchedRes) == true) {
              nextServer = srv;
              nextRes = matchedRes;
              break;
            }
          }
        }
        if (nextServer != null) break;
      }
    }

    // 3. Final fallback: try any available untried combination in the entire map
    if (nextServer == null) {
      for (final srv in _vcloudServerMap.keys) {
        for (final res in _vcloudServerMap[srv]!.keys) {
          final key = '${srv}_$res';
          if (!_failedVcloudCombinations.contains(key)) {
            nextServer = srv;
            nextRes = res;
            break;
          }
        }
        if (nextServer != null) break;
      }
    }

    if (nextServer != null && nextRes != null) {
      debugPrint('[VcloudPlayer] Failing over to server $nextServer on resolution $nextRes');
      setState(() {
        _activeServer = nextServer!;
        _selectedServer = nextServer;
        _selectedResolution = nextRes;
      });
      _vcloudUpdateNotifier.value++;
      _startVcloudPlayback();

      // Notify user
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Server/Quality failed, falling back to $nextServer ($nextRes)...'),
              backgroundColor: AppColors.primary,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    } else {
      debugPrint('[VcloudPlayer] All servers and resolutions failed! Switching to WebView.');
      _switchToWebEngine();
    }
  }



  /// Stream extracted successfully — switch to custom player
  void _onExtractionSuccess(PeachifyStream stream) {
    if (!mounted || _isClosing) return;

    debugPrint('[Engine] 🎬 Playing in native BetterPlayer: ${stream.url}');

    setState(() {
      _extractedStream = stream;
      _extractedLink = stream.url;
      _isExtracting = false;
      _useWebViewEngine = false;
      _isLoading = true;
      _isInitialized = false;
      _selectedServer = stream.providerName;
    });

    _initializeBetterPlayer(stream.url, isOffline: false, extractedStream: stream);
  }

  /// Extraction failed — show error with retry
  void _onExtractionFailed() {
    if (!mounted || _isClosing) return;

    debugPrint('[Engine] ❌ Vcloud extraction failed, falling back to VidNest/Peachify extraction...');
    _tryVidNestPeachifyExtraction();
  }

  Future<void> _tryVidNestPeachifyExtraction() async {
    _fallbackTimer?.cancel();
    final s = _currentSeason ?? widget.season ?? 1;
    final e = _currentEpisode ?? widget.episode ?? 1;

    setState(() {
      _isExtracting = true;
      _isLoading = false;
      _hasError = false;
    });

    try {
      final streams = await VidNestExtractorService.fetchMergedAndSortedStreams(
        tmdbId: widget.tmdbId,
        mediaType: widget.mediaType,
        season: widget.mediaType == 'movie' ? 1 : s,
        episode: widget.mediaType == 'movie' ? 1 : e,
      );

      if (!mounted || _isClosing) return;

      if (streams.isEmpty) {
        debugPrint('[Engine] No streams found on VidNest/Peachify.');
        setState(() {
          _isExtracting = false;
          _hasError = true;
        });
        return;
      }

      // Store ALL streams for server switching
      _currentStreamsMap = {for (var s in streams) s.providerName: s};
      _selectedServer = streams.first.providerName;
      _extractedLink = streams.first.url;
      _extractedStream = streams.first;

      debugPrint('[Engine] Routing ${streams.length} VidNest/Peachify streams to WebView HLS player.');

      // Route to WebView HLS player (NOT BetterPlayer)
      setState(() {
        _isExtracting = false;
        _useWebViewEngine = true;
        _isLoading = false;
        _isInitialized = false;
      });
    } catch (err) {
      debugPrint('[Engine] VidNest/Peachify extraction failed: $err');
      if (mounted && !_isClosing) {
        setState(() {
          _isExtracting = false;
          _hasError = true;
        });
      }
    }
  }

  void _startPlayback(String link, {bool isOffline = false, PeachifyStream? extractedStream}) {
    debugPrint('[Playback] Starting for link: $link (isOffline: $isOffline)');
    _failedVcloudCombinations.clear();
    setState(() {
      _hasVideoStarted = false;
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

    _initializeBetterPlayer(link, isOffline: isOffline, extractedStream: extractedStream);
  }

  Future<String?> _downloadSubtitleContent(String url, Map<String, String>? headers) async {
    try {
      var finalUrl = url;
      if (finalUrl.startsWith('//')) {
        finalUrl = 'https:$finalUrl';
      }
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(Uri.parse(finalUrl));
      if (headers != null) {
        headers.forEach((key, val) {
          request.headers.set(key, val);
        });
      }
      final response = await request.close();
      if (response.statusCode == 200) {
        final content = await response.transform(utf8.decoder).join();
        client.close();
        return content;
      }
      client.close();
    } catch (e) {
      debugPrint('[Subtitles] Failed to download subtitle from $url: $e');
    }
    return null;
  }

  Future<void> _initializeBetterPlayer(
    String url, {
    bool isOffline = false,
    PeachifyStream? extractedStream,
  }) async {
    try {
      _hasVideoStarted = false;
      _startPositionApplied = false;
      if (_betterPlayerController != null) {
        _betterPlayerController!.dispose();
      }

      debugPrint(
        '[BetterPlayer] Initializing for: $url (isOffline: $isOffline)',
      );

      List<BetterPlayerSubtitlesSource>? subtitles;
      if (extractedStream != null && extractedStream.tracks.isNotEmpty) {
        final List<BetterPlayerSubtitlesSource> subsList = [];
        final tracksToProcess = extractedStream.tracks
            .where((t) => t['kind'] == 'captions' || t['kind'] == 'subtitles')
            .toList();

        for (final t in tracksToProcess) {
          var subtitleUrl = t['file']?.toString() ?? '';
          if (subtitleUrl.isEmpty) continue;
          if (subtitleUrl.startsWith('//')) {
            subtitleUrl = 'https:$subtitleUrl';
          }
          final label = t['label']?.toString() ?? 'Subtitle';
          final subHeaders = {
            ...extractedStream.headers,
            'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          };

          final String? subContent = await _downloadSubtitleContent(subtitleUrl, subHeaders);
          if (subContent != null && subContent.isNotEmpty) {
            subsList.add(BetterPlayerSubtitlesSource(
              type: BetterPlayerSubtitlesSourceType.memory,
              name: label,
              content: subContent,
            ));
            debugPrint('[Subtitles] Loaded subtitles into memory for label: $label');
          }
        }
        if (subsList.isNotEmpty) {
          subtitles = subsList;
        }
      }

      Map<String, String>? explicitResolutions;
      if (_vcloudServerMap.isNotEmpty) {
        // Preserve _explicitResolutions for Vcloud database streams!
        explicitResolutions = _explicitResolutions;
        debugPrint('[BetterPlayer] Preserving Vcloud explicit resolutions: ${_explicitResolutions?.keys.join(", ")}');
      } else {
        _explicitResolutions = null;
        _selectedResolution = null;
      }

      final isStorageOrGoogle = url.contains('googleusercontent.com') ||
          url.contains('google.com') ||
          url.contains('r2.dev') ||
          url.contains('r2.cloudflarestorage.com') ||
          url.contains('cloudflarestorage') ||
          url.contains('gdrive') ||
          url.contains('fsl') ||
          url.contains('fslv2');

      BetterPlayerDataSource dataSource = BetterPlayerDataSource(
        isOffline ? BetterPlayerDataSourceType.file : BetterPlayerDataSourceType.network,
        url,
        subtitles: subtitles,
        resolutions: explicitResolutions ?? _explicitResolutions,
        videoFormat: url.toLowerCase().contains('.m3u8')
            ? BetterPlayerVideoFormat.hls
            : BetterPlayerVideoFormat.other,
        cacheConfiguration: BetterPlayerCacheConfiguration(
          useCache: !isStorageOrGoogle && !isOffline,
          preCacheSize: 10 * 1024 * 1024,
          maxCacheSize: 500 * 1024 * 1024,
          maxCacheFileSize: 100 * 1024 * 1024,
        ),
        useAsmsAudioTracks: url.toLowerCase().contains('.m3u8'),
        useAsmsTracks: url.toLowerCase().contains('.m3u8'),
        useAsmsSubtitles: url.toLowerCase().contains('.m3u8'),
        headers: !isOffline ? (isStorageOrGoogle ? null : {
          if (extractedStream != null) ...extractedStream.headers,
          if (extractedStream == null) ...{
            'Referer': 'https://peachify.top/',
            'Origin': 'https://peachify.top',
          },
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': '*/*',
        }) : null,
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
          controlsConfiguration: const BetterPlayerControlsConfiguration(
            showControls: false,
            showControlsOnInitialize: false,
          ),
        ),
        betterPlayerDataSource: dataSource,
      );
      _betterPlayerController!.setVolume(_isMuted ? 0.0 : _volume);

      // Listen for events
      _betterPlayerController!.addEventsListener((event) {
        if (event.betterPlayerEventType == BetterPlayerEventType.exception) {
          debugPrint('[BetterPlayer] Exception detected: ${event.parameters}');
          if (_vcloudServerMap.isNotEmpty) {
            _handleFailover();
          } else {
            _switchToWebEngine();
          }
        } else if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
          debugPrint('[BetterPlayer] Playback finished. Playing next episode if available.');
          _playNextEpisode();
        } else if (event.betterPlayerEventType == BetterPlayerEventType.setupDataSource) {
          debugPrint('[BetterPlayer] setupDataSource event. Re-attaching listener.');
          _betterPlayerController!.videoPlayerController?.removeListener(_videoPlayerListener);
          _betterPlayerController!.videoPlayerController?.addListener(_videoPlayerListener);
        }
      });

      _betterPlayerController!.videoPlayerController?.addListener(_videoPlayerListener);

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
      if (_vcloudServerMap.isNotEmpty) {
        _handleFailover();
      } else {
        _switchToWebEngine();
      }
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
            _selectedResolution = resolutions.keys.last;
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    });
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

    _hasVideoStarted = false;
    _extractedLink = null;
    _discoveredLinks.clear();
    _isExtracting = true;
    _isLoading = false;
    _hasError = false;
    _isInitialized = false;
    _useWebViewEngine = false;

    debugPrint('[Retry] Invoking VcloudExtractorService...');
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
    _fallbackTimer?.cancel();
    _errorAutoCloseTimer?.cancel();
    _progressSaveTimer?.cancel();
    _extractionTimer?.cancel();
    _masterWaitTimer?.cancel();
    _autoClickTimer?.cancel();
    _seekTimeoutTimer?.cancel();
    _playbackWatchdogTimer?.cancel();

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
    final targetLink = (nextEp.playLink != null && nextEp.playLink!.isNotEmpty)
        ? nextEp.playLink!
        : '';

    debugPrint('[NextEp] Playing Episode ${nextEp.episodeNumber}');

    setState(() {
      _hasVideoStarted = false;
      _currentEpisode = nextEp.episodeNumber;
      _currentExtractionUrl = targetLink;
      _isExtracting = true;
      _isInitialized = false;
      _extractedLink = null;
      _discoveredLinks.clear();
      _lastCurrentTime = 0.0; // Reset progress for new episode
    });

    _tryDirectExtraction();
  }

  List<BetterPlayerAsmsAudioTrack> _getAvailableAudioTracks() {
    if (_betterPlayerController == null) return [];
    
    // First try the native ASMS audio tracks from controller
    final asmsAudioTracks = _betterPlayerController!.betterPlayerAsmsAudioTracks;
    if (asmsAudioTracks != null && asmsAudioTracks.length > 1) {
      return asmsAudioTracks;
    }
    
    // Fallback: If ASMS tracks are empty/null, check if we have languages from VcloudExtractor
    final lastLangs = VcloudExtractorService().lastLanguages;
    if (lastLangs.isNotEmpty) {
      final List<BetterPlayerAsmsAudioTrack> fallbackTracks = [];
      for (int i = 0; i < lastLangs.length; i++) {
        fallbackTracks.add(BetterPlayerAsmsAudioTrack(
          id: i,
          label: lastLangs[i],
          language: lastLangs[i],
        ));
      }
      return fallbackTracks;
    }
    
    return [];
  }

  BetterPlayerAsmsAudioTrack? _getActiveAudioTrack() {
    if (_betterPlayerController == null) return null;
    
    final asmsAudioTracks = _betterPlayerController!.betterPlayerAsmsAudioTracks;
    if (asmsAudioTracks != null && asmsAudioTracks.length > 1) {
      return _betterPlayerController!.betterPlayerAsmsAudioTrack;
    }
    
    final fallbackTracks = _getAvailableAudioTracks();
    if (fallbackTracks.isNotEmpty && _selectedAudioIndex >= 0 && _selectedAudioIndex < fallbackTracks.length) {
      return fallbackTracks[_selectedAudioIndex];
    }
    
    return null;
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
    _fallbackTimer?.cancel();
    _errorAutoCloseTimer?.cancel();
    _progressSaveTimer?.cancel();
    _extractionTimer?.cancel();
    _masterWaitTimer?.cancel();
    _autoClickTimer?.cancel();
    _controlsTimer?.cancel();
    _brightnessTimer?.cancel();
    _volumeTimer?.cancel();
    _leftRippleTimer?.cancel();
    _rightRippleTimer?.cancel();
    _notifyPillTimer?.cancel();
    _seekTimeoutTimer?.cancel();
    _singleTapTimer?.cancel();
    _playbackWatchdogTimer?.cancel();
    _speedPillController?.dispose();

    // Dispose controllers (null-safe since _goBack may have already nulled them)
    try { ScreenBrightness().resetScreenBrightness(); } catch (_) {}
    _searchController.dispose();
    try {
      _betterPlayerController?.videoPlayerController?.removeListener(_videoPlayerListener);
      _betterPlayerController?.dispose();
    } catch (_) {}
    _betterPlayerController = null;
    _webViewController = null;

    // Restore orientation and system UI (fire-and-forget)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );

    _vcloudUpdateNotifier.dispose();
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
            handlerName: 'getSystemVolume',
            callback: (args) {
              return _volume;
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'setSystemVolume',
            callback: (args) {
              if (_isClosing) return;
              if (args.isNotEmpty) {
                final vol = (args[0] as num).toDouble().clamp(0.0, 1.0);
                if (mounted) {
                  setState(() {
                    _volume = vol;
                    _isMuted = vol == 0;
                  });
                }
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
          // Allow file:// URLs (our player.html), peachify.top, and vidnest.fun
          if (url.startsWith('file://') || url.contains('peachify.top') || url.contains('vidnest.fun')) {
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

            final isStorageOrGoogle = _extractedLink!.contains('googleusercontent.com') ||
                _extractedLink!.contains('google.com') ||
                _extractedLink!.contains('r2.dev') ||
                _extractedLink!.contains('r2.cloudflarestorage.com') ||
                _extractedLink!.contains('cloudflarestorage') ||
                _extractedLink!.contains('gdrive') ||
                _extractedLink!.contains('fsl') ||
                _extractedLink!.contains('fslv2');
            final headersMap = isStorageOrGoogle ? <String, String>{} : (_extractedStream?.headers ?? {
              'Referer': 'https://peachify.top/',
              'Origin': 'https://peachify.top'
            });
            final headersJson = jsonEncode(headersMap);

            String serversJs = '[]';
            if (_vcloudServerMap.isNotEmpty) {
              final serversList = _vcloudServerMap.keys.toList();
              final priority = ['Server 1', 'Server 2', 'Server 3'];
              serversList.sort((a, b) {
                final aIndex = priority.indexOf(a);
                final bIndex = priority.indexOf(b);
                if (aIndex != -1 && bIndex != -1) {
                  return aIndex.compareTo(bIndex);
                } else if (aIndex != -1) {
                  return -1;
                } else if (bIndex != -1) {
                  return 1;
                }
                return a.compareTo(b);
              });
              serversJs = jsonEncode(serversList);
            } else if (_currentStreamsMap != null && _currentStreamsMap!.isNotEmpty) {
              final serversList = _currentStreamsMap!.keys.toList();
              final priority = ['Server 1', 'Server 2', 'Server 3'];
              serversList.sort((a, b) {
                final aIndex = priority.indexOf(a);
                final bIndex = priority.indexOf(b);
                if (aIndex != -1 && bIndex != -1) {
                  return aIndex.compareTo(bIndex);
                } else if (aIndex != -1) {
                  return -1;
                } else if (bIndex != -1) {
                  return 1;
                }
                return a.compareTo(b);
              });
              serversJs = jsonEncode(serversList);
            }

            final double resumeTime = _lastCurrentTime > 1 ? _lastCurrentTime : (widget.startPosition?.toDouble() ?? 0.0);

            // Setup custom quality picker if we have vcloud server map resolutions
            String customQualitiesJs = '{}';
            if (_vcloudServerMap.containsKey(_activeServer)) {
              final Map<String, String> resUrls = _vcloudServerMap[_activeServer]!;
              customQualitiesJs = jsonEncode(resUrls);
            }

            String languagesJs = '[]';
            if (VcloudExtractorService().lastLanguages.isNotEmpty) {
              final List<Map<String, dynamic>> langList = [];
              for (var i = 0; i < VcloudExtractorService().lastLanguages.length; i++) {
                final lang = VcloudExtractorService().lastLanguages[i];
                langList.add({
                  'id': i,
                  'name': lang,
                  'lang': lang,
                });
              }
              languagesJs = jsonEncode(langList);
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

                // Setup languages list for audio track picker if available
                var langTracks = $languagesJs;
                if (langTracks.length > 0) {
                  window.setupAudioPicker(langTracks, true);
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
                                                   final targetLink = (ep.playLink != null && ep.playLink!.isNotEmpty)
                                                       ? ep.playLink!
                                                       : '';
                                                   Navigator.pop(context);
                                                   setState(() {
                                                     _currentSeason = tempSeason;
                                                     _currentEpisode = ep.episodeNumber;
                                                     _currentExtractionUrl = targetLink;
                                                     _isExtracting = true;
                                                     _isInitialized = false;
                                                     _extractedLink = null;
                                                     _discoveredLinks.clear();
                                                     _lastCurrentTime = 0.0; // Reset progress for new episode
                                                   });
                                                   _webViewController?.evaluateJavascript(
                                                     source: "updateEpisodeButton('Episodes')",
                                                   );
                                                   _tryDirectExtraction();
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





        // 3. Main UI Layer
        if (_hasError)
          Positioned.fill(
            child: _buildErrorOverlay(),
          )
        else if (_useWebViewEngine)
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
            child: (_isExtracting || (_isInitialized && !_hasVideoStarted && !_useWebViewEngine))
                ? _buildDiscoveryProgress(key: const ValueKey('loader'))
                : const SizedBox.shrink(key: ValueKey('empty')),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerInterface() {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          BetterPlayer(
            key: _betterPlayerKey,
            controller: _betterPlayerController!,
          ),
          if (!_isInPipMode) ...[
            if (!_hasVideoStarted)
              Positioned.fill(
                child: Container(
                  color: Colors.black,
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              )
            else
              Positioned.fill(
                child: _isLocked 
                    ? _buildLockedControls() 
                    : _buildUnlockedControls(),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildLockedControls() {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              setState(() {
                _areControlsVisible = !_areControlsVisible;
              });
              if (_areControlsVisible) {
                _controlsTimer?.cancel();
                _controlsTimer = Timer(const Duration(seconds: 2), () {
                  if (mounted) setState(() => _areControlsVisible = false);
                });
              }
            },
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: 24,
          top: MediaQuery.of(context).size.height / 2 - 28,
          child: AnimatedOpacity(
            opacity: _areControlsVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: IgnorePointer(
              ignoring: !_areControlsVisible,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isLocked = false;
                    _areControlsVisible = true;
                  });
                  _resetControlsTimer();
                  _triggerHaptic();
                },
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnlockedControls() {
    final isPlaying = _betterPlayerController?.videoPlayerController?.value.isPlaying ?? false;

    final screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) {
              if (_isLocked) return;
              final now = DateTime.now();
              final isDoubleTap = _lastTapUpTime != null &&
                  now.difference(_lastTapUpTime!) < const Duration(milliseconds: 280);
              _lastTapUpTime = now;

              if (isDoubleTap) {
                _singleTapTimer?.cancel();
                _singleTapTimer = null;

                final x = details.localPosition.dx;
                if (x < screenWidth * 0.35) {
                  _handleDoubleTapLeft(details);
                } else if (x > screenWidth * 0.65) {
                  _handleDoubleTapRight(details);
                }
              } else {
                _singleTapTimer?.cancel();
                _singleTapTimer = Timer(const Duration(milliseconds: 280), () {
                  _toggleControlsVisibility();
                });
              }
            },
            onLongPressStart: (details) {
              _singleTapTimer?.cancel();
              final x = details.localPosition.dx;
              if (x < screenWidth * 0.35 || x > screenWidth * 0.65) {
                _startFastForward();
              }
            },
            onLongPressEnd: (_) => _stopFastForward(),
            onVerticalDragStart: (details) {
              _singleTapTimer?.cancel();
              final x = details.localPosition.dx;
              if (x < screenWidth * 0.35) {
                _activeVerticalDrag = 'brightness';
                _handleBrightnessDragStart(details);
              } else if (x > screenWidth * 0.65) {
                _activeVerticalDrag = 'volume';
                _handleVolumeDragStart(details);
              } else {
                _activeVerticalDrag = null;
              }
            },
            onVerticalDragUpdate: (details) {
              if (_activeVerticalDrag == 'brightness') {
                _handleBrightnessDragUpdate(details);
              } else if (_activeVerticalDrag == 'volume') {
                _handleVolumeDragUpdate(details);
              }
            },
            onVerticalDragEnd: (_) {
              if (_activeVerticalDrag == 'brightness') {
                _fadeBrightnessIndicator();
              } else if (_activeVerticalDrag == 'volume') {
                _fadeVolumeIndicator();
              }
              _activeVerticalDrag = null;
            },
            onHorizontalDragStart: (details) {
              _singleTapTimer?.cancel();
              _handleSwipeSeekStart(details);
            },
            onHorizontalDragUpdate: _handleSwipeSeekUpdate,
            onHorizontalDragEnd: _handleSwipeSeekEnd,
            child: Container(color: Colors.transparent),
          ),
        ),

        // Volume indicator — animated fade+scale
        Positioned(
          left: 24,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _showVolumeIndicator ? 1.0 : 0.0,
              duration: Duration(milliseconds: _showVolumeIndicator ? 150 : 300),
              curve: Curves.easeOutCubic,
              child: AnimatedScale(
                scale: _showVolumeIndicator ? 1.0 : 0.85,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildVerticalGestureIndicator(
                    icon: _volume == 0 ? Icons.volume_mute_rounded : Icons.volume_up_rounded,
                    value: _volume,
                    label: '${(_volume * 100).toInt()}%',
                  ),
                ),
              ),
            ),
          ),
        ),

        // Brightness indicator — animated fade+scale
        Positioned(
          right: 24,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _showBrightnessIndicator ? 1.0 : 0.0,
              duration: Duration(milliseconds: _showBrightnessIndicator ? 150 : 300),
              curve: Curves.easeOutCubic,
              child: AnimatedScale(
                scale: _showBrightnessIndicator ? 1.0 : 0.85,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _buildVerticalGestureIndicator(
                    icon: Icons.brightness_6_rounded,
                    value: _brightness,
                    label: '${(_brightness * 100).toInt()}%',
                  ),
                ),
              ),
            ),
          ),
        ),

        // Left skip ripple — animated scale+fade
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: MediaQuery.of(context).size.width * 0.4,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _showLeftRipple ? 1.0 : 0.0,
              duration: Duration(milliseconds: _showLeftRipple ? 150 : 400),
              curve: Curves.easeOutCubic,
              child: AnimatedScale(
                scale: _showLeftRipple ? 1.0 : 0.7,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: _buildSkipRipple(isLeft: true),
              ),
            ),
          ),
        ),
        // Right skip ripple — animated scale+fade
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: MediaQuery.of(context).size.width * 0.4,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _showRightRipple ? 1.0 : 0.0,
              duration: Duration(milliseconds: _showRightRipple ? 150 : 400),
              curve: Curves.easeOutCubic,
              child: AnimatedScale(
                scale: _showRightRipple ? 1.0 : 0.7,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: _buildSkipRipple(isLeft: false),
              ),
            ),
          ),
        ),

        // Speed pill — animated bloom in/out
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _showSpeedPill ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: AnimatedScale(
              scale: _showSpeedPill ? 1.0 : 0.8,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 24.0),
                  child: _buildSpeedPill(),
                ),
              ),
            ),
          ),
        ),

        // Notification pill — animated bloom in/out
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _notifyPillText != null ? 1.0 : 0.0,
            duration: Duration(milliseconds: _notifyPillText != null ? 200 : 300),
            curve: Curves.easeOutCubic,
            child: AnimatedScale(
              scale: _notifyPillText != null ? 1.0 : 0.8,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: Align(
                alignment: const Alignment(0.0, -0.4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _notifyPillText ?? '',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // HUD controls overlay — use IgnorePointer when hidden so taps pass through
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !(_areControlsVisible || _isSwipeSeeking),
            child: Stack(
              children: [
                // Top HUD — slides down from above + fades
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedSlide(
                    offset: _areControlsVisible ? Offset.zero : const Offset(0, -0.08),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: _areControlsVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: _buildTopHUD(),
                    ),
                  ),
                ),
                // Center HUD — scales in + fades
                AnimatedScale(
                  scale: _areControlsVisible ? 1.0 : 0.85,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _areControlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: _buildCenterHUD(isPlaying),
                  ),
                ),
                // Bottom HUD — slides up from below + fades
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedSlide(
                    offset: (_areControlsVisible || _isSwipeSeeking) ? Offset.zero : const Offset(0, 0.08),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: (_areControlsVisible || _isSwipeSeeking) ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: _buildBottomHUD(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isSwipeSeeking)
          IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Text(
                  _getSwipeDeltaText(_swipeSeekTarget - _swipeSeekStartValue),
                  style: GoogleFonts.inter(
                    color: (_swipeSeekTarget >= _swipeSeekStartValue)
                        ? const Color(0xFF00E5FF)
                        : const Color(0xFFE74C3C),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _getSwipeDeltaText(double diff) {
    final prefix = diff >= 0 ? '+' : '−';
    final absDiff = diff.abs().toInt();
    final minutes = absDiff ~/ 60;
    final seconds = absDiff % 60;
    if (minutes > 0) {
      return '$prefix${minutes}m ${seconds}s';
    } else {
      return '$prefix${seconds}s';
    }
  }

  Widget _buildVerticalGestureIndicator({
    required IconData icon,
    required double value,
    required String label,
  }) {
    return Container(
      width: 48,
      height: 180,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: 6,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: value,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xFFB81D24), Color(0xFFE04048)],
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkipRipple({required bool isLeft}) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: isLeft ? const Alignment(-0.5, 0.0) : const Alignment(0.5, 0.0),
          radius: 0.8,
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.transparent,
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isLeft ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
            color: Colors.white,
            size: 40,
          ),
          const SizedBox(height: 8),
          Text(
            isLeft ? '−15s' : '+15s',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedPill() {
    return AnimatedBuilder(
      animation: _speedPillColorAnimation!,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fast_forward_rounded,
              color: _speedPillColorAnimation!.value,
              size: 14,
              shadows: const [
                Shadow(
                  color: Colors.black54,
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
            ),
            const SizedBox(width: 6),
            Text(
              '2x Speed',
              style: TextStyle(
                color: _speedPillColorAnimation!.value,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                shadows: const [
                  Shadow(
                    color: Colors.black54,
                    offset: Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopHUD() {
    final s = _currentSeason ?? widget.season;
    final e = _currentEpisode ?? widget.episode;
    String episodeLabel = '';
    if (widget.mediaType != 'movie' && s != null && e != null) {
      episodeLabel = 'S${s.toString().padLeft(2, '0')} E${e.toString().padLeft(2, '0')}';
    }

    return Container(
      height: 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.8),
            Colors.transparent,
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          // Left: Back Button
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: _goBack,
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
              ),
            ),
          ),
          
          // Center: Title + Episode
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 120),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    widget.title,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  if (episodeLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      episodeLabel,
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          // Right: Episodes button (if applicable)
          if (widget.mediaType != 'movie')
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: _showEpisodeSelector,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.grid_view_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Episodes',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCenterHUD(bool isPlaying) {
    return Align(
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildCenterCircularButton(
            icon: Icons.replay_10_rounded,
            size: 56,
            onTap: () {
              final newPos = (_lastCurrentTime - 15).clamp(0.0, _lastDuration);
              _betterPlayerController!.seekTo(Duration(seconds: newPos.toInt()));
              _resetControlsTimer();
              _triggerHaptic();
            },
          ),
          const SizedBox(width: 40),
          _buildCenterCircularButton(
            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 80,
            isPlayPause: true,
            onTap: () {
              if (isPlaying) {
                _betterPlayerController!.pause();
              } else {
                _betterPlayerController!.play();
              }
              _resetControlsTimer();
              _triggerHaptic();
            },
          ),
          const SizedBox(width: 40),
          _buildCenterCircularButton(
            icon: Icons.forward_10_rounded,
            size: 56,
            onTap: () {
              final newPos = (_lastCurrentTime + 15).clamp(0.0, _lastDuration);
              _betterPlayerController!.seekTo(Duration(seconds: newPos.toInt()));
              _resetControlsTimer();
              _triggerHaptic();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCenterCircularButton({
    required IconData icon,
    required double size,
    bool isPlayPause = false,
    required VoidCallback onTap,
  }) {
    return _AnimatedTapScale(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white10),
          boxShadow: isPlayPause
              ? [
                  BoxShadow(
                    color: const Color(0xFFB81D24).withOpacity(0.1),
                    blurRadius: 16,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: Icon(
              icon,
              key: ValueKey<IconData>(icon),
              color: Colors.white,
              size: size * 0.55,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomHUD() {
    final isPlaying = _betterPlayerController?.videoPlayerController?.value.isPlaying ?? false;
    final bufferedSeconds = _getBufferedSeconds();

    return Container(
      height: 96,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.9),
            Colors.transparent,
          ],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Seeker - positioned above the controls stably
          Positioned(
            left: 0,
            right: 0,
            bottom: 44,
            child: GlassmorphicVideoSeekBar(
              position: _lastCurrentTime,
              duration: _lastDuration,
              buffered: bufferedSeconds,
              isSwipeSeeking: _isSwipeSeeking,
              swipeSeekValue: _swipeSeekTarget,
              onChanged: (val) {
                setState(() {
                  _lastCurrentTime = val;
                });
                _controlsTimer?.cancel();
              },
              onChangeEnd: (val) {
                _betterPlayerController!.seekTo(Duration(seconds: val.toInt()));
                _resetControlsTimer();
              },
            ),
          ),
          // Controls / Swipe Seek Info below the seeker
          if (_isSwipeSeeking)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Center(
                child: Text(
                  '${_formatDuration(_swipeSeekTarget)} / ${_formatDuration(_lastDuration)}',
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            )
          else if (_areControlsVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      if (isPlaying) {
                        _betterPlayerController!.pause();
                      } else {
                        _betterPlayerController!.play();
                      }
                      _resetControlsTimer();
                      _triggerHaptic();
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_isMuted) {
                          _isMuted = false;
                          _volume = _preMuteVolume > 0 ? _preMuteVolume : 0.5;
                        } else {
                          _preMuteVolume = _volume;
                          _volume = 0.0;
                          _isMuted = true;
                        }
                      });
                      VolumeController.instance.showSystemUI = false;
                      VolumeController.instance.setVolume(_volume);
                      _betterPlayerController?.setVolume(_volume);
                      _resetControlsTimer();
                      _triggerHaptic();
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatDuration(_lastCurrentTime)} / ${_formatDuration(_lastDuration)}',
                    style: GoogleFonts.inter(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.lock_open_rounded, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _isLocked = true;
                        _areControlsVisible = true;
                      });
                      _controlsTimer?.cancel();
                      _controlsTimer = Timer(const Duration(seconds: 3), () {
                        if (mounted) setState(() => _areControlsVisible = false);
                      });
                      _triggerHaptic();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white),
                    onPressed: () {
                      _saveToWatchHistory();
                      _betterPlayerController?.enablePictureInPicture(_betterPlayerKey);
                      _resetControlsTimer();
                      _triggerHaptic();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_rounded, color: Colors.white),
                    onPressed: () {
                      _showSettingsSheet();
                      _triggerHaptic();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.aspect_ratio_rounded, color: Colors.white),
                    onPressed: () {
                      _cycleAspectRatio();
                      _resetControlsTimer();
                      _triggerHaptic();
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  double _getBufferedSeconds() {
    if (_betterPlayerController == null) return 0.0;
    final value = _betterPlayerController!.videoPlayerController!.value;
    if (!value.initialized) return 0.0;
    if (value.buffered.isEmpty) return 0.0;
    
    final position = value.position;
    for (final range in value.buffered) {
      if (range.start <= position && range.end >= position) {
        return range.end.inSeconds.toDouble();
      }
    }
    return value.buffered.last.end.inSeconds.toDouble();
  }

  String _formatDuration(double seconds) {
    if (seconds.isNaN || seconds.isInfinite) return '00:00';
    final duration = Duration(seconds: seconds.toInt());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$secs';
    } else {
      return '$minutes:$secs';
    }
  }

  Future<void> _initBrightness() async {
    try {
      _brightness = await ScreenBrightness().current;
    } catch (_) {
      _brightness = 0.5;
    }
  }

  void _initVolume() {
    VolumeController.instance.getVolume().then((vol) {
      if (mounted) {
        setState(() {
          _volume = vol;
        });
        _betterPlayerController?.setVolume(vol);
      }
    });
    VolumeController.instance.addListener((vol) {
      if (mounted && !_showVolumeIndicator) {
        setState(() {
          _volume = vol;
          _isMuted = vol == 0;
        });
        _betterPlayerController?.setVolume(vol);
        if (_useWebViewEngine) {
          _webViewController?.evaluateJavascript(
            source: 'if (window.initSystemVolume) window.initSystemVolume($vol);',
          );
        }
      }
    });
  }

  void _handleBrightnessDragStart(DragStartDetails details) {
    _brightnessDragAccumulator = 0.0;
    _brightnessDragActive = false;
  }

  void _handleBrightnessDragUpdate(DragUpdateDetails details) {
    if (_isLocked) return;
    if (!_brightnessDragActive) {
      _brightnessDragAccumulator += details.delta.dy;
      if (_brightnessDragAccumulator.abs() > 15.0) {
        _brightnessDragActive = true;
      } else {
        return;
      }
    }
    double delta = -details.primaryDelta! / MediaQuery.of(context).size.height;
    double newBrightness = (_brightness + delta).clamp(0.0, 1.0);
    setState(() {
      _brightness = newBrightness;
      _showBrightnessIndicator = true;
    });
    try {
      ScreenBrightness().setScreenBrightness(newBrightness);
    } catch (_) {}
    _brightnessTimer?.cancel();
  }

  void _handleVolumeDragStart(DragStartDetails details) {
    _volumeDragAccumulator = 0.0;
    _volumeDragActive = false;
  }

  void _handleVolumeDragUpdate(DragUpdateDetails details) {
    if (_isLocked) return;
    if (!_volumeDragActive) {
      _volumeDragAccumulator += details.delta.dy;
      if (_volumeDragAccumulator.abs() > 15.0) {
        _volumeDragActive = true;
      } else {
        return;
      }
    }
    double delta = -details.primaryDelta! / MediaQuery.of(context).size.height;
    double newVolume = (_volume + delta).clamp(0.0, 1.0);
    setState(() {
      _volume = newVolume;
      _showVolumeIndicator = true;
      _isMuted = newVolume == 0;
    });
    VolumeController.instance.showSystemUI = false;
    VolumeController.instance.setVolume(newVolume);
    _betterPlayerController?.setVolume(newVolume);
    _volumeTimer?.cancel();
  }

  void _fadeBrightnessIndicator() {
    _brightnessTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showBrightnessIndicator = false;
        });
      }
    });
  }

  void _fadeVolumeIndicator() {
    _volumeTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showVolumeIndicator = false;
        });
      }
    });
  }

  void _handleSwipeSeekStart(DragStartDetails details) {
    if (_isLocked || _betterPlayerController == null) return;
    
    setState(() {
      _isSwipeSeeking = true;
      _swipeSeekTarget = _lastCurrentTime;
      _swipeSeekStartValue = _lastCurrentTime;
    });
    _controlsTimer?.cancel();
  }

  void _handleSwipeSeekUpdate(DragUpdateDetails details) {
    if (!_isSwipeSeeking) return;
    
    // Sensitivity: 0.15 seconds per logical pixel (gentle and precise)
    final double sensitivity = 0.15;
    double delta = details.delta.dx * sensitivity;
    setState(() {
      _swipeSeekTarget = (_swipeSeekTarget + delta).clamp(0.0, _lastDuration);
    });
  }

  void _handleSwipeSeekEnd(DragEndDetails details) {
    if (!_isSwipeSeeking) return;
    _betterPlayerController!.seekTo(Duration(seconds: _swipeSeekTarget.toInt()));
    setState(() {
      _isSwipeSeeking = false;
      _lastCurrentTime = _swipeSeekTarget;
    });
    _resetControlsTimer();
  }

  void _handleDoubleTapLeft(TapUpDetails details) {
    if (_isLocked) return;
    _triggerHaptic();
    final newPos = (_lastCurrentTime - 15).clamp(0.0, _lastDuration);
    _betterPlayerController!.seekTo(Duration(seconds: newPos.toInt()));
    setState(() {
      _showLeftRipple = true;
    });
    if (_areControlsVisible) {
      _resetControlsTimer();
    }
    _leftRippleTimer?.cancel();
    _leftRippleTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _showLeftRipple = false;
        });
      }
    });
  }

  void _handleDoubleTapRight(TapUpDetails details) {
    if (_isLocked) return;
    _triggerHaptic();
    final newPos = (_lastCurrentTime + 15).clamp(0.0, _lastDuration);
    _betterPlayerController!.seekTo(Duration(seconds: newPos.toInt()));
    setState(() {
      _showRightRipple = true;
    });
    if (_areControlsVisible) {
      _resetControlsTimer();
    }
    _rightRippleTimer?.cancel();
    _rightRippleTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _showRightRipple = false;
        });
      }
    });
  }

  void _startFastForward() {
    if (_isLocked || _betterPlayerController == null) return;
    _wasPlayingBeforeFastForward = _betterPlayerController!.videoPlayerController?.value.isPlaying ?? false;
    _betterPlayerController!.setSpeed(2.0);
    if (!_wasPlayingBeforeFastForward) {
      _betterPlayerController!.play();
    }
    setState(() {
      _showSpeedPill = true;
      _areControlsVisible = false;
    });
    _controlsTimer?.cancel();
    _triggerHaptic();
  }

  void _stopFastForward() {
    if (_betterPlayerController == null) return;
    _betterPlayerController!.setSpeed(_playbackSpeed);
    if (!_wasPlayingBeforeFastForward) {
      _betterPlayerController!.pause();
    }
    setState(() {
      _showSpeedPill = false;
    });
    _triggerHaptic();
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (!_isLocked) {
      _controlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _areControlsVisible = false;
          });
        }
      });
    }
  }

  void _toggleControlsVisibility() {
    if (_isLocked) return;
    setState(() {
      _areControlsVisible = !_areControlsVisible;
    });
    if (_areControlsVisible) {
      _resetControlsTimer();
    } else {
      _controlsTimer?.cancel();
    }
  }

  void _triggerHaptic() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  void _showNotifyPill(String text) {
    setState(() {
      _notifyPillText = text;
    });
    _notifyPillTimer?.cancel();
    _notifyPillTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _notifyPillText = null;
        });
      }
    });
  }

  void _cycleAspectRatio() {
    if (_betterPlayerController == null) return;
    final fit = _betterPlayerController!.getFit();
    BoxFit nextFit;
    String label;
    if (fit == BoxFit.contain) {
      nextFit = BoxFit.cover;
      label = 'Fill';
    } else {
      nextFit = BoxFit.contain;
      label = 'Fit';
    }
    _betterPlayerController!.setOverriddenFit(nextFit);
    _showNotifyPill('Aspect Ratio: $label');
  }

  Future<void> _changeServer(String serverName) async {
    double currentPos = _lastCurrentTime;
    try {
      if (_betterPlayerController?.videoPlayerController?.value.initialized == true) {
        currentPos = _betterPlayerController!.videoPlayerController!.value.position.inSeconds.toDouble();
      }
    } catch (_) {}
    
    debugPrint('[ServerSwap] Saving position: $currentPos before switching to $serverName');
    
    _failedVcloudCombinations.clear();
    setState(() {
      _hasVideoStarted = false;
      _resumeTimeOverride = currentPos;
      _startPositionApplied = false;
      _activeServer = serverName;
      _selectedServer = serverName;
    });
    _vcloudUpdateNotifier.value++;

    await _startVcloudPlayback();
  }

  void _performSeek(double time) {
    if (_betterPlayerController == null) return;
    _seekingToTime = time;
    _lastCurrentTime = time;
    _betterPlayerController!.seekTo(Duration(seconds: time.toInt()));
    _seekTimeoutTimer?.cancel();
    _seekTimeoutTimer = Timer(const Duration(seconds: 4), () {
      _seekingToTime = null;
    });
  }

  Future<void> _changeResolution(String resolutionName) async {
    var resUrl = _explicitResolutions![resolutionName]!;
    final double currentPos = _betterPlayerController != null 
        ? _betterPlayerController!.videoPlayerController!.value.position.inSeconds.toDouble()
        : _lastCurrentTime;
        
    debugPrint('[QualitySwap] Quality swap to $resolutionName at position $currentPos');
    
    _failedVcloudCombinations.clear();
    setState(() {
      _selectedResolution = resolutionName;
    });
    _vcloudUpdateNotifier.value++;

    if (resUrl.contains('hubcloud') || resUrl.contains('gpdl')) {
      debugPrint('[QualitySwap] Resolving HubCloud redirect just-in-time for resolution change...');
      setState(() {
        _isExtracting = true;
      });
      _vcloudUpdateNotifier.value++;
      final gDriveUrl = await VcloudExtractorService().resolveHubCloudRedirect(resUrl);
      if (gDriveUrl != null && gDriveUrl.isNotEmpty) {
        resUrl = gDriveUrl;
        _explicitResolutions![resolutionName] = resUrl;
        if (_vcloudServerMap[_activeServer] != null) {
          _vcloudServerMap[_activeServer]![resolutionName] = resUrl;
        }
      }
      setState(() {
        _isExtracting = false;
      });
      _vcloudUpdateNotifier.value++;
    }

    if (_betterPlayerController != null) {
      _performSeek(currentPos);
      await _betterPlayerController!.setResolution(resUrl);
    } else {
      setState(() {
        _resumeTimeOverride = currentPos;
        _startPositionApplied = false;
      });
      _vcloudUpdateNotifier.value++;
      await _initializeBetterPlayer(resUrl, isOffline: false, extractedStream: _extractedStream);
    }
  }

  void _videoPlayerListener() {
    if (!mounted || _betterPlayerController == null) return;
    final value = _betterPlayerController!.videoPlayerController!.value;
    
    final position = value.position;
    final duration = value.duration;
    
    if (value.initialized) {
      if (_startPositionApplied && _seekingToTime == null) {
        if (value.isPlaying && !value.isBuffering && position.inMilliseconds > 0) {
          if (!_hasVideoStarted) {
            setState(() {
              _hasVideoStarted = true;
            });
            _playbackWatchdogTimer?.cancel();
            // Re-apply volume to ensure audio works after server switch
            _betterPlayerController?.setVolume(_isMuted ? 0.0 : _volume);
            debugPrint('[BetterPlayerListener] Video started playing at ${position.inMilliseconds}ms');
          }
        }
      }
      if (!_startPositionApplied) {
        _startPositionApplied = true;
        final resumeTime = _resumeTimeOverride ?? widget.startPosition?.toDouble() ?? 0.0;
        _resumeTimeOverride = null;
        if (resumeTime > 1.0) {
          debugPrint('[BetterPlayerListener] Seeking to resume time: $resumeTime');
          _performSeek(resumeTime);
        }
      } else {
        final currentPos = position.inSeconds.toDouble();
        if (_seekingToTime != null) {
          if ((currentPos - _seekingToTime!).abs() < 5) {
            _seekingToTime = null;
            _seekTimeoutTimer?.cancel();
          } else {
            // Ignore position updates while seeking to avoid resetting progress bar/history to 0
            return;
          }
        }
        if (mounted) {
          setState(() {
            _lastCurrentTime = currentPos;
            _lastDuration = duration?.inSeconds.toDouble() ?? _lastDuration;
          });
        }
      }
    }
  }

  void _showSettingsSheet() {
    _controlsTimer?.cancel();
    final screenH = MediaQuery.of(context).size.height;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Settings',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final double width = 240;
        final curvedAnim = CurvedAnimation(parent: anim1, curve: Curves.easeOutQuart);
        return FadeTransition(
          opacity: curvedAnim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.75, end: 1.0).animate(curvedAnim),
            alignment: const Alignment(0.75, 0.95),
            child: Align(
              alignment: Alignment.bottomRight,
              child: Container(
                margin: const EdgeInsets.only(right: 16, bottom: 68),
                width: width,
                constraints: BoxConstraints(maxHeight: screenH * 0.55),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0A).withOpacity(0.88),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                    BoxShadow(
                      color: Colors.white.withOpacity(0.03),
                      blurRadius: 1,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                    child: Material(
                      color: Colors.transparent,
                      child: _SettingsSheetContent(
                        controller: _betterPlayerController,
                        activeServer: _activeServer,
                        selectedResolution: _selectedResolution,
                        vcloudServerMap: _vcloudServerMap,
                        explicitResolutions: _explicitResolutions,
                        playbackSpeed: _playbackSpeed,
                        availableAudioTracks: _getAvailableAudioTracks(),
                        activeAudioTrack: _getActiveAudioTrack(),
                        onServerChanged: (server) => _changeServer(server),
                        onResolutionChanged: (res) => _changeResolution(res),
                        onSpeedChanged: (speed) {
                          setState(() {
                            _playbackSpeed = speed;
                          });
                          _betterPlayerController?.setSpeed(speed);
                        },
                        onAspectChanged: (fit) {
                          _betterPlayerController?.setOverriddenFit(fit);
                        },
                        onAudioChanged: (track) {
                          final asmsAudioTracks = _betterPlayerController?.betterPlayerAsmsAudioTracks ?? [];
                          if (asmsAudioTracks.isNotEmpty) {
                            _betterPlayerController?.setAudioTrack(track);
                          } else {
                            // Fallback progressive audio track selection
                            if (track.id != null) {
                              setState(() {
                                _selectedAudioIndex = track.id!;
                              });
                              _betterPlayerController?.videoPlayerController?.setAudioTrack(track.label, track.id);
                            }
                          }
                          _showNotifyPill('Audio: ${track.label ?? track.language ?? "Track"}');
                        },
                        onSubtitleChanged: (source) {
                          _betterPlayerController?.setupSubtitleSource(source);
                          _showNotifyPill(source.type == BetterPlayerSubtitlesSourceType.none ? 'Subtitles Off' : 'Subtitles: ${source.name}');
                        },
                        playerState: this,
                        updateNotifier: _vcloudUpdateNotifier,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      _resetControlsTimer();
    });
  }

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

// ─────────────────────────────────────────────────────────────────────────────
// ── GLASSMORPHIC VIDEO SEEK BAR
// ─────────────────────────────────────────────────────────────────────────────
class GlassmorphicVideoSeekBar extends StatefulWidget {
  final double position;
  final double duration;
  final double buffered;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final bool isSwipeSeeking;
  final double? swipeSeekValue;

  const GlassmorphicVideoSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onChanged,
    required this.onChangeEnd,
    this.isSwipeSeeking = false,
    this.swipeSeekValue,
  });

  @override
  State<GlassmorphicVideoSeekBar> createState() => _GlassmorphicVideoSeekBarState();
}

class _GlassmorphicVideoSeekBarState extends State<GlassmorphicVideoSeekBar> {
  bool _isDragging = false;
  double? _dragValue;

  String _formatDuration(double seconds) {
    if (seconds.isNaN || seconds.isInfinite) return '00:00';
    final duration = Duration(seconds: seconds.toInt());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$secs';
    } else {
      return '$minutes:$secs';
    }
  }

  @override
  Widget build(BuildContext context) {
    double activeValue = _isDragging 
        ? (_dragValue ?? widget.position) 
        : (widget.isSwipeSeeking ? (widget.swipeSeekValue ?? widget.position) : widget.position);
    double progressPercent = widget.duration > 0 ? (activeValue / widget.duration).clamp(0.0, 1.0) : 0.0;
    double bufferPercent = widget.duration > 0 ? (widget.buffered / widget.duration).clamp(0.0, 1.0) : 0.0;
    final isSeeking = _isDragging || widget.isSwipeSeeking;

    return GestureDetector(
      onHorizontalDragStart: (details) {
        setState(() {
          _isDragging = true;
        });
      },
      onHorizontalDragUpdate: (details) {
        final box = context.findRenderObject() as RenderBox;
        final localPos = box.globalToLocal(details.globalPosition);
        final val = (localPos.dx / box.size.width).clamp(0.0, 1.0) * widget.duration;
        setState(() {
          _dragValue = val;
        });
        widget.onChanged(val);
      },
      onHorizontalDragEnd: (details) {
        final finalVal = _dragValue ?? widget.position;
        setState(() {
          _isDragging = false;
          _dragValue = null;
        });
        widget.onChangeEnd(finalVal);
      },
      onTapDown: (details) {
        final box = context.findRenderObject() as RenderBox;
        final localPos = box.globalToLocal(details.globalPosition);
        final val = (localPos.dx / box.size.width).clamp(0.0, 1.0) * widget.duration;
        widget.onChanged(val);
        widget.onChangeEnd(val);
      },
      child: Container(
        height: 36,
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final thumbOffset = constraints.maxWidth * progressPercent;
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                // Background Track
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  height: isSeeking ? 6 : 4,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                // Buffer Bar
                FractionallySizedBox(
                  widthFactor: bufferPercent,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    height: isSeeking ? 6 : 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                // Progress Bar
                FractionallySizedBox(
                  widthFactor: progressPercent,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    height: isSeeking ? 6 : 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB81D24),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: isSeeking
                          ? [
                              const BoxShadow(
                                color: Color(0x7FB81D24),
                                blurRadius: 8,
                              )
                            ]
                          : null,
                    ),
                  ),
                ),
                // Floating Tooltip — animated fade+slide from below
                Positioned(
                  left: (thumbOffset - 30).clamp(0.0, constraints.maxWidth - 60),
                  bottom: 28,
                  child: AnimatedOpacity(
                    opacity: isSeeking ? 1.0 : 0.0,
                    duration: Duration(milliseconds: isSeeking ? 150 : 250),
                    curve: Curves.easeOutCubic,
                    child: AnimatedSlide(
                      offset: isSeeking ? Offset.zero : const Offset(0, 0.3),
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFB81D24), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFB81D24).withOpacity(0.15),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                            const BoxShadow(
                              color: Colors.black54,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            )
                          ],
                        ),
                        child: Text(
                          _formatDuration(activeValue),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Thumb with animated glow
                Positioned(
                  left: (thumbOffset - 8).clamp(0.0, constraints.maxWidth - 16),
                  child: AnimatedScale(
                    scale: isSeeking ? 1.3 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFFB81D24),
                        shape: BoxShape.circle,
                        boxShadow: [
                          const BoxShadow(
                            color: Colors.black45,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                          if (isSeeking)
                            BoxShadow(
                              color: const Color(0xFFB81D24).withOpacity(0.4),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── SETTINGS BOTTOM SHEET CONTENT
// ─────────────────────────────────────────────────────────────────────────────
class _SettingsSheetContent extends StatefulWidget {
  final BetterPlayerController? controller;
  final String activeServer;
  final String? selectedResolution;
  final Map<String, Map<String, String>> vcloudServerMap;
  final Map<String, String>? explicitResolutions;
  final double playbackSpeed;
  final Function(String) onServerChanged;
  final Function(String) onResolutionChanged;
  final Function(double) onSpeedChanged;
  final Function(BoxFit) onAspectChanged;
  final Function(BetterPlayerAsmsAudioTrack) onAudioChanged;
  final Function(BetterPlayerSubtitlesSource) onSubtitleChanged;
  final List<BetterPlayerAsmsAudioTrack> availableAudioTracks;
  final BetterPlayerAsmsAudioTrack? activeAudioTrack;
  final _VideoPlayerScreenState playerState;
  final ValueNotifier<int> updateNotifier;

  const _SettingsSheetContent({
    super.key,
    required this.controller,
    required this.activeServer,
    required this.selectedResolution,
    required this.vcloudServerMap,
    required this.explicitResolutions,
    required this.playbackSpeed,
    required this.onServerChanged,
    required this.onResolutionChanged,
    required this.onSpeedChanged,
    required this.onAspectChanged,
    required this.onAudioChanged,
    required this.onSubtitleChanged,
    required this.availableAudioTracks,
    required this.activeAudioTrack,
    required this.playerState,
    required this.updateNotifier,
  });

  @override
  State<_SettingsSheetContent> createState() => _SettingsSheetContentState();
}

class _SettingsSheetContentState extends State<_SettingsSheetContent> {
  String _currentView = 'main';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.updateNotifier,
      builder: (context, _, __) {
        Widget currentChild;
        switch (_currentView) {
          case 'server':
            currentChild = _buildServerView();
            break;
          case 'quality':
            currentChild = _buildQualityView();
            break;
          case 'audio':
            currentChild = _buildAudioView();
            break;
          case 'subtitles':
            currentChild = _buildSubtitlesView();
            break;
          case 'speed':
            currentChild = _buildSpeedView();
            break;
          case 'aspect':
            currentChild = _buildAspectView();
            break;
          case 'main':
          default:
            currentChild = _buildMainView();
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final isForward = _currentView != 'main';
            final offsetTween = Tween<Offset>(
              begin: Offset(isForward ? 0.15 : -0.15, 0),
              end: Offset.zero,
            );
            return SlideTransition(
              position: offsetTween.animate(animation),
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<String>(_currentView),
            child: currentChild,
          ),
        );
      },
    );
  }

  Widget _buildHeader(String title) {
    final canGoBack = _currentView != 'main';
    final headerContent = Row(
      children: [
        if (canGoBack) ...[
          const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
          const SizedBox(width: 12),
        ],
        Text(
          title,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );

    return GestureDetector(
      onTap: canGoBack ? () => setState(() => _currentView = 'main') : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: headerContent,
      ),
    );
  }

  Widget _buildMainView() {
    final isOffline = widget.playerState.widget.isOffline;
    final isDirectLink = widget.playerState.widget.isDirectLink;
    final is3rdPartyHosted = widget.playerState.widget.is3rdPartyHosted;
    final isVcloud = !isOffline && !isDirectLink && !is3rdPartyHosted;

    final hasServers = isVcloud || widget.vcloudServerMap.isNotEmpty;
    final hasResolutions = isVcloud || (widget.explicitResolutions != null && widget.explicitResolutions!.isNotEmpty);
    
    final audioTracks = widget.availableAudioTracks;
    final hasAudioTracks = audioTracks.length > 1;
    
    final subtitles = widget.controller?.betterPlayerSubtitlesSourceList ?? [];
    final hasSubtitles = subtitles.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader('Settings'),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasServers)
                  _buildMenuRow(
                    icon: Icons.language_rounded,
                    label: 'Server',
                    value: widget.activeServer,
                    onTap: () => setState(() => _currentView = 'server'),
                  ),
                if (hasResolutions)
                  _buildMenuRow(
                    icon: Icons.high_quality_rounded,
                    label: 'Quality',
                    value: widget.selectedResolution ?? 'Auto',
                    onTap: () => setState(() => _currentView = 'quality'),
                  ),
                // if (hasAudioTracks)
                //   _buildMenuRow(
                //     icon: Icons.audiotrack_rounded,
                //     label: 'Audio',
                //     value: widget.activeAudioTrack?.label ?? widget.activeAudioTrack?.language ?? 'Default',
                //     onTap: () => setState(() => _currentView = 'audio'),
                //   ),
                // if (hasSubtitles)
                //   _buildMenuRow(
                //     icon: Icons.subtitles_rounded,
                //     label: 'Subtitles',
                //     value: widget.controller?.betterPlayerSubtitlesSource?.name ?? 'Off',
                //     onTap: () => setState(() => _currentView = 'subtitles'),
                //   ),
                _buildMenuRow(
                  icon: Icons.speed_rounded,
                  label: 'Speed',
                  value: widget.playbackSpeed == 1.0 ? 'Normal' : '${widget.playbackSpeed}x',
                  onTap: () => setState(() => _currentView = 'speed'),
                ),
                _buildMenuRow(
                  icon: Icons.aspect_ratio_rounded,
                  label: 'Aspect Ratio',
                  value: _getAspectLabel(widget.controller?.getFit() ?? BoxFit.contain),
                  onTap: () => setState(() => _currentView = 'aspect'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildServerView() {
    final allServers = ['Server 1', 'Server 2', 'Server 3'];
    final vcloudMap = widget.playerState._vcloudServerMap;
    final activeServer = widget.playerState._activeServer;
    final isExtracting = widget.playerState._isExtracting || widget.playerState._isBackgroundExtracting;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader('Server'),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: allServers.map((server) {
                final isSelected = server == activeServer;
                final resolutionsMap = vcloudMap[server];
                final isAvailable = resolutionsMap != null && resolutionsMap.isNotEmpty;
                
                String label = server;
                if (server == 'Server 1') label = 'Server 1 (FSL)';
                if (server == 'Server 2') label = 'Server 2 (FSLv2)';
                if (server == 'Server 3') label = 'Server 3 (G-Drive)';
                
                Widget? trailingWidget;
                bool clickable = isAvailable;
                Color textColor = Colors.white;

                if (isSelected) {
                  textColor = const Color(0xFFB81D24);
                  trailingWidget = const Icon(Icons.check_rounded, color: Color(0xFFB81D24));
                  clickable = true;
                } else if (isAvailable) {
                  textColor = Colors.white;
                  trailingWidget = null;
                } else if (isExtracting) {
                  textColor = Colors.white38;
                  trailingWidget = const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.white70,
                    ),
                  );
                } else {
                  textColor = Colors.white24;
                  trailingWidget = Text(
                    'Unavailable',
                    style: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
                  );
                }

                return ListTile(
                  enabled: clickable,
                  title: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: textColor,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: trailingWidget,
                  onTap: clickable
                      ? () {
                          Navigator.pop(context);
                          widget.onServerChanged(server);
                        }
                      : null,
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildQualityView() {
    final dbResolutions = widget.playerState._dbResolutions;
    final activeServer = widget.playerState._activeServer;
    final vcloudMap = widget.playerState._vcloudServerMap;
    final selectedResolution = widget.playerState._selectedResolution;
    final isExtracting = widget.playerState._isExtracting || widget.playerState._isBackgroundExtracting;

    final resolutionsToShow = dbResolutions.isNotEmpty
        ? dbResolutions
        : (widget.explicitResolutions?.keys.toList() ?? []);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader('Quality'),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: resolutionsToShow.map((res) {
                final isSelected = res == selectedResolution;
                final serverResolutions = vcloudMap[activeServer];
                final isAvailable = serverResolutions != null && serverResolutions.containsKey(res);

                String label = res.toUpperCase();
                Widget? trailingWidget;
                bool clickable = isAvailable;
                Color textColor = Colors.white;

                if (isSelected) {
                  textColor = const Color(0xFFB81D24);
                  trailingWidget = const Icon(Icons.check_rounded, color: Color(0xFFB81D24));
                  clickable = true;
                } else if (isAvailable) {
                  textColor = Colors.white;
                  trailingWidget = null;
                } else if (isExtracting) {
                  textColor = Colors.white38;
                  trailingWidget = const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.white70,
                    ),
                  );
                } else {
                  textColor = Colors.white24;
                  trailingWidget = Text(
                    'Unavailable',
                    style: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
                  );
                }

                return InkWell(
                  onTap: clickable
                      ? () {
                          Navigator.pop(context);
                          widget.onResolutionChanged(res);
                        }
                      : null,
                  child: Opacity(
                    opacity: clickable ? 1.0 : 0.5,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: textColor,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (trailingWidget != null) trailingWidget,
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildAudioView() {
    final audioTracks = widget.availableAudioTracks;
    final currentAudio = widget.activeAudioTrack;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader('Audio Language'),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: audioTracks.map((track) {
                final isSelected = track.id == currentAudio?.id;
                return ListTile(
                  title: Text(
                    track.label ?? track.language ?? 'Audio Track',
                    style: GoogleFonts.inter(
                      color: isSelected ? const Color(0xFFB81D24) : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected ? const Icon(Icons.check_rounded, color: Color(0xFFB81D24)) : null,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onAudioChanged(track);
                  },
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSubtitlesView() {
    final subtitleSources = widget.controller?.betterPlayerSubtitlesSourceList ?? [];
    final currentSub = widget.controller?.betterPlayerSubtitlesSource;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader('Subtitles'),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    'Off',
                    style: GoogleFonts.inter(
                      color: currentSub == null || currentSub.type == BetterPlayerSubtitlesSourceType.none ? const Color(0xFFB81D24) : Colors.white,
                      fontWeight: currentSub == null || currentSub.type == BetterPlayerSubtitlesSourceType.none ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: currentSub == null || currentSub.type == BetterPlayerSubtitlesSourceType.none ? const Icon(Icons.check_rounded, color: Color(0xFFB81D24)) : null,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onSubtitleChanged(BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.none));
                  },
                ),
                ...subtitleSources.map((source) {
                  if (source.type == BetterPlayerSubtitlesSourceType.none) return const SizedBox.shrink();
                  final isSelected = currentSub != null && currentSub.name == source.name;
                  return ListTile(
                    title: Text(
                      source.name ?? 'Subtitle',
                      style: GoogleFonts.inter(
                        color: isSelected ? const Color(0xFFB81D24) : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected ? const Icon(Icons.check_rounded, color: Color(0xFFB81D24)) : null,
                    onTap: () {
                      Navigator.pop(context);
                      widget.onSubtitleChanged(source);
                    },
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSpeedView() {
    final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader('Playback Speed'),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: speeds.map((speed) {
                final isSelected = speed == widget.playbackSpeed;
                return ListTile(
                  title: Text(
                    speed == 1.0 ? 'Normal' : '${speed}x',
                    style: GoogleFonts.inter(
                      color: isSelected ? const Color(0xFFB81D24) : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected ? const Icon(Icons.check_rounded, color: Color(0xFFB81D24)) : null,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onSpeedChanged(speed);
                  },
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildAspectView() {
    final fits = [BoxFit.contain, BoxFit.cover];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader('Aspect Ratio'),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: fits.map((fit) {
                final currentFit = widget.controller?.getFit() ?? BoxFit.contain;
                final isSelected = fit == currentFit;
                return ListTile(
                  title: Text(
                    _getAspectLabel(fit),
                    style: GoogleFonts.inter(
                      color: isSelected ? const Color(0xFFB81D24) : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected ? const Icon(Icons.check_rounded, color: Color(0xFFB81D24)) : null,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onAspectChanged(fit);
                  },
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  String _getAspectLabel(BoxFit fit) {
    switch (fit) {
      case BoxFit.cover:
        return 'Fill';
      case BoxFit.contain:
      default:
        return 'Fit';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── ANIMATED TAP SCALE — press-and-release bounce for buttons
// ─────────────────────────────────────────────────────────────────────────────
class _AnimatedTapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleDown;

  const _AnimatedTapScale({
    required this.child,
    required this.onTap,
    this.scaleDown = 0.85,
  });

  @override
  State<_AnimatedTapScale> createState() => _AnimatedTapScaleState();
}

class _AnimatedTapScaleState extends State<_AnimatedTapScale>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scaleDown,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
      reverseCurve: Curves.easeOutBack,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _controller.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}