/// Player controller — manages BetterPlayer lifecycle and state.
///
/// Replaces the extraction and playback state management that was
/// embedded in the old 5000+ line video_player_screen.dart.
/// Uses BetterPlayer (ExoPlayer wrapper) for all playback — no WebView.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';
import 'package:better_player_plus/better_player_plus.dart';
import '../../../services/extraction/models.dart';
import '../../../services/extraction/provider_registry.dart';

/// Playback state for the UI to observe.
enum PlaybackState {
  idle,
  extracting,
  buffering,
  playing,
  paused,
  completed,
  error,
}

/// Resize mode for video display.
enum VideoResizeMode {
  fit,
  fill,
  zoom,
}

class PlayerController extends ChangeNotifier {
  // ─── BetterPlayer ──────────────────────────────────────────────────────
  BetterPlayerController? _betterPlayerController;
  BetterPlayerController? get betterPlayerController => _betterPlayerController;

  // ─── State ─────────────────────────────────────────────────────────────
  PlaybackState _state = PlaybackState.idle;
  PlaybackState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // ─── Sources ───────────────────────────────────────────────────────────
  final List<ExtractorLink> _sources = [];
  List<ExtractorLink> get sources => List.unmodifiable(_sources);

  ExtractorLink? _currentSource;
  ExtractorLink? get currentSource => _currentSource;

  final Map<String, ProviderStatus> _providerStatuses = {};
  Map<String, ProviderStatus> get providerStatuses =>
      Map.unmodifiable(_providerStatuses);

  // ─── Playback Info ─────────────────────────────────────────────────────
  Duration _position = Duration.zero;
  Duration get position => _position;

  Duration _duration = Duration.zero;
  Duration get duration => _duration;

  Duration _buffered = Duration.zero;
  Duration get buffered => _buffered;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  double _playbackSpeed = 1.0;
  double get playbackSpeed => _playbackSpeed;

  VideoResizeMode _resizeMode = VideoResizeMode.fit;
  VideoResizeMode get resizeMode => _resizeMode;

  bool _controlsVisible = true;
  bool get controlsVisible => _controlsVisible;

  bool _isLocked = false;
  bool get isLocked => _isLocked;

  // ─── Content Info ──────────────────────────────────────────────────────
  String _title = '';
  String get title => _title;

  int _tmdbId = 0;
  String _mediaType = 'movie';
  String? _imdbId;
  int? _year;
  int? _season;
  int? _episode;

  // ─── Timers ────────────────────────────────────────────────────────────
  Timer? _controlsTimer;
  Timer? _positionTimer;

  // ─── Callbacks ─────────────────────────────────────────────────────────
  Function(Duration position, Duration duration)? onProgressUpdate;
  VoidCallback? onPlaybackComplete;

  // ─── Initialize ────────────────────────────────────────────────────────

  /// Initialize the player and start extraction.
  Future<void> initialize({
    required String title,
    required int tmdbId,
    required String mediaType,
    String? imdbId,
    int? year,
    int? season,
    int? episode,
    String? directUrl,
    double? startPosition,
  }) async {
    _title = title;
    _tmdbId = tmdbId;
    _mediaType = mediaType;
    _imdbId = imdbId;
    _year = year;
    _season = season;
    _episode = episode;

    // Lock to landscape
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (directUrl != null && directUrl.isNotEmpty) {
      // Direct link mode — skip extraction
      _sources.add(ExtractorLink(
        sourceName: 'Direct',
        displayName: 'Direct Link',
        url: directUrl,
      ));
      await _playSource(_sources.first, startPosition: startPosition);
    } else {
      // Start extraction from all providers
      _state = PlaybackState.extracting;
      notifyListeners();
      await _startExtraction(startPosition: startPosition);
    }
  }

  // ─── Extraction ────────────────────────────────────────────────────────

  Future<void> _startExtraction({double? startPosition}) async {
    bool firstLinkPlayed = false;

    try {
      await ProviderRegistry().extractAll(
        tmdbId: _tmdbId.toString(),
        imdbId: _imdbId,
        title: _title,
        mediaType: _mediaType,
        year: _year,
        season: _season,
        episode: _episode,
        onLinkFound: (link) {
          _sources.add(link);
          notifyListeners();

          // Auto-play the first link found
          if (!firstLinkPlayed) {
            firstLinkPlayed = true;
            _playSource(link, startPosition: startPosition);
          }
        },
        onProviderStatus: (providerName, status) {
          _providerStatuses[providerName] = status;
          notifyListeners();
        },
      );

      if (_sources.isEmpty) {
        _state = PlaybackState.error;
        _errorMessage = 'No streaming sources found';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[PlayerController] Extraction error: $e');
      if (_sources.isEmpty) {
        _state = PlaybackState.error;
        _errorMessage = 'Extraction failed: $e';
        notifyListeners();
      }
    }
  }

  // ─── Playback ──────────────────────────────────────────────────────────

  /// Play a specific source.
  Future<void> _playSource(ExtractorLink source, {double? startPosition}) async {
    _state = PlaybackState.buffering;
    _currentSource = source;
    _errorMessage = null;
    notifyListeners();

    try {
      // Dispose previous controller if exists
      _betterPlayerController?.dispose();

      // Determine data source type
      BetterPlayerDataSourceType dataSourceType;
      switch (source.resolvedType) {
        case LinkType.m3u8:
          dataSourceType = BetterPlayerDataSourceType.network;
          break;
        case LinkType.dash:
          dataSourceType = BetterPlayerDataSourceType.network;
          break;
        default:
          dataSourceType = BetterPlayerDataSourceType.network;
      }

      // Create data source with headers
      final dataSource = BetterPlayerDataSource(
        dataSourceType,
        source.url,
        headers: source.headers.isNotEmpty ? source.headers : null,
        useAsmsSubtitles: true,
        useAsmsTracks: true,
        useAsmsAudioTracks: true,
      );

      // Create player configuration
      final playerConfig = BetterPlayerConfiguration(
        autoPlay: true,
        looping: false,
        fit: _getBetterPlayerFit(),
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          showControls: false, // We use custom controls
        ),
        allowedScreenSleep: false,
        startAt: startPosition != null
            ? Duration(milliseconds: (startPosition * 1000).toInt())
            : null,
      );

      _betterPlayerController = BetterPlayerController(
        playerConfig,
        betterPlayerDataSource: dataSource,
      );

      // Listen to events
      _betterPlayerController!.addEventsListener(_onPlayerEvent);

      // Start position tracking
      _startPositionTracking();

      debugPrint('[PlayerController] Playing: ${source.displayName}');
    } catch (e) {
      debugPrint('[PlayerController] Play error: $e');
      _state = PlaybackState.error;
      _errorMessage = 'Playback failed: $e';
      notifyListeners();
    }
  }

  /// Switch to a different source.
  Future<void> switchSource(ExtractorLink source) async {
    final currentPos = _position;
    await _playSource(source,
        startPosition: currentPos.inMilliseconds / 1000.0);
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        _state = PlaybackState.playing;
        _isPlaying = true;
        if (_betterPlayerController?.videoPlayerController?.value.duration !=
            null) {
          _duration = _betterPlayerController!
              .videoPlayerController!.value.duration!;
        }
        notifyListeners();
        break;
      case BetterPlayerEventType.play:
        _state = PlaybackState.playing;
        _isPlaying = true;
        notifyListeners();
        break;
      case BetterPlayerEventType.pause:
        _state = PlaybackState.paused;
        _isPlaying = false;
        notifyListeners();
        break;
      case BetterPlayerEventType.bufferingStart:
        _state = PlaybackState.buffering;
        notifyListeners();
        break;
      case BetterPlayerEventType.bufferingEnd:
        _state = _isPlaying ? PlaybackState.playing : PlaybackState.paused;
        notifyListeners();
        break;
      case BetterPlayerEventType.finished:
        _state = PlaybackState.completed;
        _isPlaying = false;
        onPlaybackComplete?.call();
        notifyListeners();
        break;
      case BetterPlayerEventType.exception:
        _state = PlaybackState.error;
        _errorMessage = 'Playback error';
        notifyListeners();
        break;
      default:
        break;
    }
  }

  void _startPositionTracking() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final controller = _betterPlayerController?.videoPlayerController;
      if (controller != null && controller.value.initialized) {
        final newPosition = controller.value.position;
        final newDuration = controller.value.duration ?? Duration.zero;
        if (newPosition != _position || newDuration != _duration) {
          _position = newPosition;
          _duration = newDuration;
          onProgressUpdate?.call(_position, _duration);
          notifyListeners();
        }
      }
    });
  }

  // ─── Controls ──────────────────────────────────────────────────────────

  void togglePlayPause() {
    if (_isPlaying) {
      _betterPlayerController?.pause();
    } else {
      _betterPlayerController?.play();
    }
  }

  void seekTo(Duration position) {
    _betterPlayerController?.seekTo(position);
  }

  void seekRelative(Duration offset) {
    final newPos = _position + offset;
    final clamped = newPos < Duration.zero
        ? Duration.zero
        : (newPos > _duration ? _duration : newPos);
    seekTo(clamped);
  }

  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    _betterPlayerController?.setSpeed(speed);
    notifyListeners();
  }

  void setResizeMode(VideoResizeMode mode) {
    _resizeMode = mode;
    _betterPlayerController?.setOverriddenFit(_getBetterPlayerFit());
    notifyListeners();
  }

  BoxFit _getBetterPlayerFit() {
    switch (_resizeMode) {
      case VideoResizeMode.fit:
        return BoxFit.contain;
      case VideoResizeMode.fill:
        return BoxFit.cover;
      case VideoResizeMode.zoom:
        return BoxFit.fill;
    }
  }

  // ─── Controls Visibility ───────────────────────────────────────────────

  void showControls() {
    if (_isLocked) return;
    _controlsVisible = true;
    notifyListeners();
    _resetControlsTimer();
  }

  void hideControls() {
    _controlsVisible = false;
    _controlsTimer?.cancel();
    notifyListeners();
  }

  void toggleControls() {
    if (_controlsVisible) {
      hideControls();
    } else {
      showControls();
    }
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (_isPlaying && _controlsVisible) {
        hideControls();
      }
    });
  }

  void toggleLock() {
    _isLocked = !_isLocked;
    if (_isLocked) {
      _controlsVisible = false;
    }
    notifyListeners();
  }

  // ─── Retry ─────────────────────────────────────────────────────────────

  Future<void> retry() async {
    _state = PlaybackState.extracting;
    _errorMessage = null;
    _sources.clear();
    _providerStatuses.clear();
    notifyListeners();
    await _startExtraction();
  }

  // ─── Cleanup ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _positionTimer?.cancel();
    _betterPlayerController?.removeEventsListener(_onPlayerEvent);
    _betterPlayerController?.dispose();

    // Restore orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }
}
