library;

/// Player controller — manages BetterPlayer lifecycle and state.
///
/// Replaces the extraction and playback state management that was
/// embedded in the old 5000+ line video_player_screen.dart.
/// Uses BetterPlayer (ExoPlayer wrapper) for all playback — no WebView.

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:better_player_plus/better_player_plus.dart';
import '../../../services/extraction/models.dart';
import '../../../services/extraction/provider_registry.dart';
import '../../../services/vcloud_extractor.dart';

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
  // ─── Lifecycle Guard ───────────────────────────────────────────────────
  bool _isDisposed = false;

  /// Safe notifyListeners — no-op if disposed.
  void _safeNotify() {
    if (!_isDisposed) notifyListeners();
  }

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

  // ─── Audio/Subtitle Tracks ─────────────────────────────────────────────
  List<BetterPlayerAsmsAudioTrack> _audioTracks = [];
  List<BetterPlayerAsmsAudioTrack> get audioTracks => _audioTracks;
  BetterPlayerAsmsAudioTrack? _currentAudioTrack;
  BetterPlayerAsmsAudioTrack? get currentAudioTrack => _currentAudioTrack;

  List<BetterPlayerSubtitlesSource> _subtitleSources = [];
  List<BetterPlayerSubtitlesSource> get subtitleSources => _subtitleSources;
  BetterPlayerSubtitlesSource? _currentSubtitleSource;
  BetterPlayerSubtitlesSource? get currentSubtitleSource => _currentSubtitleSource;

  List<String> _currentCues = [];
  List<String> get currentCues => _currentCues;

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

  // ─── Episode Navigation ────────────────────────────────────────────────
  int? get season => _season;
  int? get episode => _episode;
  String get mediaType => _mediaType;
  int get tmdbId => _tmdbId;
  bool get isTvShow => _mediaType == 'tv' || _mediaType == 'series';
  List<int> _seasonNumbers = [];
  List<int> get seasonNumbers => _seasonNumbers;
  int _totalEpisodes = 0;
  int get totalEpisodes => _totalEpisodes;
  bool get hasNextEpisode => isTvShow && _episode != null && _episode! < _totalEpisodes;
  bool get hasPreviousEpisode => isTvShow && _episode != null && _episode! > 1;

  // ─── Callbacks ─────────────────────────────────────────────────────────
  Function(Duration position, Duration duration)? onProgressUpdate;
  VoidCallback? onPlaybackComplete;
  void Function(int season, int episode)? onNextEpisode;
  void Function(int season, int episode)? onPreviousEpisode;

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
    List<int>? seasonNumbers,
    int? totalEpisodes,
    Future<String?> Function()? streamResolver,
  }) async {
    _title = title;
    _tmdbId = tmdbId;
    _mediaType = mediaType;
    _imdbId = imdbId;
    _year = year;
    _season = season;
    _episode = episode;
    _seasonNumbers = seasonNumbers ?? [];
    _totalEpisodes = totalEpisodes ?? 0;

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
    } else if (streamResolver != null) {
      _state = PlaybackState.extracting;
      _safeNotify();
      try {
        final resolvedUrl = await streamResolver();
        if (_isDisposed) return;
        if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
          _sources.add(ExtractorLink(
            sourceName: 'FastStream',
            displayName: 'Stream 1',
            url: resolvedUrl,
          ));
          await _playSource(_sources.first, startPosition: startPosition);
          return;
        }
      } catch (e) {
        debugPrint('[PlayerController] streamResolver error: $e');
      }
      // Fallback to provider extraction if streamResolver did not yield a link
      if (!_isDisposed) {
        await _startExtraction(startPosition: startPosition);
      }
    } else {
      // Start extraction from all providers
      _state = PlaybackState.extracting;
      _safeNotify();
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
          if (_isDisposed) return;
          _sources.add(link);
          _safeNotify();

          // Auto-play the first link found
          if (!firstLinkPlayed) {
            firstLinkPlayed = true;
            _playSource(link, startPosition: startPosition);
          }
        },
        onProviderStatus: (providerName, status) {
          if (_isDisposed) return;
          _providerStatuses[providerName] = status;
          _safeNotify();
        },
      );

      if (_isDisposed) return;
      if (_sources.isEmpty) {
        _state = PlaybackState.error;
        _errorMessage = 'No streaming sources found';
        _safeNotify();
      }
    } catch (e) {
      debugPrint('[PlayerController] Extraction error: $e');
      if (_isDisposed) return;
      if (_sources.isEmpty) {
        _state = PlaybackState.error;
        _errorMessage = 'Extraction failed: $e';
        _safeNotify();
      }
    }
  }

  // ─── Playback ──────────────────────────────────────────────────────────

  /// Play a specific source.
  Future<void> _playSource(ExtractorLink source, {double? startPosition}) async {
    if (_isDisposed) return;
    _state = PlaybackState.buffering;
    _currentSource = source;
    _errorMessage = null;
    _safeNotify();

    try {
      // Dispose previous controller if exists
      _betterPlayerController?.removeEventsListener(_onPlayerEvent);
      _betterPlayerController?.dispose();
      _betterPlayerController = null;

      final isLocalFile = source.url.startsWith('/') || !source.url.startsWith('http');
      final isHls = source.resolvedType == LinkType.m3u8 ||
          source.url.toLowerCase().contains('.m3u8') ||
          source.url.toLowerCase().contains('hsl') ||
          source.url.toLowerCase().contains('master');

      final dataSource = isLocalFile
          ? BetterPlayerDataSource(
              BetterPlayerDataSourceType.file,
              source.url,
            )
          : BetterPlayerDataSource(
              BetterPlayerDataSourceType.network,
              source.url,
              headers: source.headers.isNotEmpty
                  ? source.headers
                  : {
                      if (!source.url.contains('google') && !source.url.contains('storage')) ...{
                        'User-Agent':
                            'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                        'Accept': '*/*',
                      },
                    },
              videoFormat: isHls ? BetterPlayerVideoFormat.hls : BetterPlayerVideoFormat.other,
              useAsmsTracks: isHls,
              useAsmsAudioTracks: isHls,
              useAsmsSubtitles: isHls,
              bufferingConfiguration: const BetterPlayerBufferingConfiguration(
                minBufferMs: 15000,
                maxBufferMs: 35000,
                bufferForPlaybackMs: 2500,
                bufferForPlaybackAfterRebufferMs: 4000,
              ),
            );

      // Create player configuration
      final playerConfig = BetterPlayerConfiguration(
        autoPlay: true,
        looping: false,
        fit: _getBetterPlayerFit(),
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          showControls: false, // We use custom controls
        ),
        subtitlesConfiguration: const BetterPlayerSubtitlesConfiguration(
          fontSize: 16,
          fontColor: Colors.white,
          outlineColor: Colors.black,
          outlineSize: 2.0,
          backgroundColor: Colors.transparent,
          alignment: Alignment.bottomCenter,
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
      // Auto-try next source on failure
      _tryNextSource(source, startPosition: startPosition);
    }
  }

  /// If the current source fails, automatically try the next available source.
  void _tryNextSource(ExtractorLink failedSource, {double? startPosition}) {
    if (_isDisposed) return;
    final idx = _sources.indexOf(failedSource);
    if (idx >= 0 && idx + 1 < _sources.length) {
      debugPrint('[PlayerController] Auto-trying next source...');
      _playSource(_sources[idx + 1], startPosition: startPosition);
    } else {
      _state = PlaybackState.error;
      _errorMessage = 'Playback failed for all sources';
      _safeNotify();
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
        _updateTracksAndSubtitles();
        notifyListeners();
        break;
      case BetterPlayerEventType.play:
        _state = PlaybackState.playing;
        _isPlaying = true;
        _updateTracksAndSubtitles();
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
        _updateTracksAndSubtitles();
        notifyListeners();
        break;
      case BetterPlayerEventType.changedSubtitles:
        _updateTracksAndSubtitles();
        notifyListeners();
        break;
      case BetterPlayerEventType.tracksChanged:
        _updateTracksAndSubtitles();
        notifyListeners();
        break;
      case BetterPlayerEventType.cues:
        final cues = event.parameters?['cues'] as List<dynamic>?;
        if (cues != null) {
          _currentCues = cues.map((e) => e.toString()).toList();
          notifyListeners();
        }
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

  void _updateTracksAndSubtitles() {
    if (_betterPlayerController == null) return;
    final vController = _betterPlayerController!.videoPlayerController;
    final nativeAudio = vController?.value.audioTracks ?? [];
    final nativeText = vController?.value.textTracks ?? [];

    // 1. Audio tracks
    if (nativeAudio.isNotEmpty) {
      _audioTracks = [
        for (final a in nativeAudio)
          BetterPlayerAsmsAudioTrack(
            id: a['index'] as int?,
            label: _cleanLanguageName(
              a['language'] as String?,
              a['label'] as String?,
              channels: a['channels'] as int?,
            ),
            language: a['language'] as String?,
          ),
      ];

      final selectedMap = nativeAudio.firstWhere(
        (a) => a['selected'] == true,
        orElse: () => nativeAudio.first,
      );
      final selId = selectedMap['index'] as int?;
      _currentAudioTrack = _audioTracks.firstWhere(
        (t) => t.id == selId,
        orElse: () => _audioTracks.first,
      );
    } else {
      final asmsAudios = _betterPlayerController!.betterPlayerAsmsAudioTracks;
      if (asmsAudios != null && asmsAudios.isNotEmpty) {
        _audioTracks = asmsAudios;
        _currentAudioTrack = _betterPlayerController!.betterPlayerAsmsAudioTrack ?? _audioTracks.first;
      } else {
        final lastLangs = VcloudExtractorService().lastLanguages;
        if (lastLangs.isNotEmpty) {
          _audioTracks = [
            for (int i = 0; i < lastLangs.length; i++)
              BetterPlayerAsmsAudioTrack(
                id: i,
                label: lastLangs[i],
                language: lastLangs[i],
              ),
          ];
          _currentAudioTrack = _audioTracks.first;
        } else {
          // Smart fallback: check source url / title
          final urlOrTitle = '${_currentSource?.url ?? ''} $_title';
          final List<String> extractedLangs = [];
          if (urlOrTitle.toLowerCase().contains('hindi')) extractedLangs.add('Hindi (5.1)');
          if (urlOrTitle.toLowerCase().contains('english')) extractedLangs.add('English (5.1)');
          if (urlOrTitle.toLowerCase().contains('tamil')) extractedLangs.add('Tamil');
          if (urlOrTitle.toLowerCase().contains('telugu')) extractedLangs.add('Telugu');

          if (extractedLangs.isNotEmpty) {
            _audioTracks = [
              for (int i = 0; i < extractedLangs.length; i++)
                BetterPlayerAsmsAudioTrack(
                  id: i,
                  label: extractedLangs[i],
                  language: extractedLangs[i].toLowerCase().contains('hindi') ? 'hin' : 'eng',
                ),
            ];
            _currentAudioTrack ??= _audioTracks.first;
          }
        }
      }
    }

    // 2. Subtitles
    if (nativeText.isNotEmpty) {
      _subtitleSources = [
        BetterPlayerSubtitlesSource(
          type: BetterPlayerSubtitlesSourceType.none,
          name: 'Off',
        ),
        for (final t in nativeText)
          BetterPlayerSubtitlesSource(
            type: BetterPlayerSubtitlesSourceType.network,
            name: _cleanSubtitleName(t['language'] as String?, t['label'] as String?),
            selectedByDefault: t['selected'] as bool? ?? false,
          ),
      ];

      final selectedTextMap = nativeText.firstWhere(
        (t) => t['selected'] == true,
        orElse: () => <String, dynamic>{},
      );
      if (selectedTextMap.isNotEmpty) {
        final selLabel = _cleanSubtitleName(selectedTextMap['language'] as String?, selectedTextMap['label'] as String?);
        _currentSubtitleSource = _subtitleSources.firstWhere(
          (s) => s.name == selLabel,
          orElse: () => _subtitleSources.first,
        );
      }
    } else {
      final subs = _betterPlayerController!.betterPlayerSubtitlesSourceList;
      if (subs.isNotEmpty) {
        _subtitleSources = subs;
        _currentSubtitleSource = _betterPlayerController!.betterPlayerSubtitlesSource;
      } else if (_currentSource?.url.toLowerCase().contains('.mkv') == true) {
        _subtitleSources = [
          BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.none, name: 'Off'),
          BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.network, name: 'English'),
        ];
      }
    }
  }

  String _cleanLanguageName(String? code, String? label, {int? channels}) {
    final c = (code ?? '').toLowerCase().trim();
    final l = (label ?? '').trim();
    final isWatermark = l.toLowerCase().contains('vegamovies') ||
        l.toLowerCase().contains('hubcloud') ||
        l.toLowerCase().contains('1vegamovies') ||
        l.toLowerCase().contains('http') ||
        l.toLowerCase().contains('.tw') ||
        l.toLowerCase().contains('.com');

    String langName = '';
    switch (c) {
      case 'hin':
      case 'hi':
        langName = 'Hindi';
        break;
      case 'eng':
      case 'en':
        langName = 'English';
        break;
      case 'tam':
      case 'ta':
        langName = 'Tamil';
        break;
      case 'tel':
      case 'te':
        langName = 'Telugu';
        break;
      case 'ben':
      case 'bn':
        langName = 'Bengali';
        break;
      case 'mal':
      case 'ml':
        langName = 'Malayalam';
        break;
      case 'kan':
      case 'kn':
        langName = 'Kannada';
        break;
      case 'mar':
      case 'mr':
        langName = 'Marathi';
        break;
      case 'guj':
      case 'gu':
        langName = 'Gujarati';
        break;
      case 'pan':
      case 'pa':
        langName = 'Punjabi';
        break;
      case 'spa':
      case 'es':
        langName = 'Spanish';
        break;
      case 'fre':
      case 'fra':
      case 'fr':
        langName = 'French';
        break;
      case 'ger':
      case 'deu':
      case 'de':
        langName = 'German';
        break;
      case 'ita':
      case 'it':
        langName = 'Italian';
        break;
      case 'por':
      case 'pt':
        langName = 'Portuguese';
        break;
      case 'rus':
      case 'ru':
        langName = 'Russian';
        break;
      case 'jpn':
      case 'ja':
        langName = 'Japanese';
        break;
      case 'kor':
      case 'ko':
        langName = 'Korean';
        break;
      case 'chi':
      case 'zho':
      case 'zh':
        langName = 'Chinese';
        break;
      case 'ara':
      case 'ar':
        langName = 'Arabic';
        break;
      case 'tur':
      case 'tr':
        langName = 'Turkish';
        break;
      default:
        if (!isWatermark && l.isNotEmpty) {
          langName = l;
        } else if (c.isNotEmpty) {
          langName = c.toUpperCase();
        } else {
          langName = 'Audio Track';
        }
        break;
    }

    if (channels != null && channels > 0) {
      if (channels == 6) {
        langName = '$langName (5.1)';
      } else if (channels == 8) {
        langName = '$langName (7.1)';
      } else if (channels == 2) {
        langName = '$langName (Stereo)';
      }
    }

    return langName;
  }

  String _cleanSubtitleName(String? code, String? label) {
    final c = (code ?? '').toLowerCase().trim();
    final l = (label ?? '').trim();
    final isWatermark = l.toLowerCase().contains('vegamovies') ||
        l.toLowerCase().contains('hubcloud') ||
        l.toLowerCase().contains('1vegamovies') ||
        l.toLowerCase().contains('.tw') ||
        l.toLowerCase().contains('.com');

    if (!isWatermark && l.isNotEmpty && !l.startsWith('http')) {
      return l;
    }

    switch (c) {
      case 'eng':
      case 'en':
        return 'English';
      case 'hin':
      case 'hi':
        return 'Hindi';
      case 'spa':
      case 'es':
        return 'Spanish';
      case 'fre':
      case 'fra':
      case 'fr':
        return 'French';
      case 'ger':
      case 'deu':
      case 'de':
        return 'German';
      case 'ita':
      case 'it':
        return 'Italian';
      case 'por':
      case 'pt':
        return 'Portuguese';
      case 'rus':
      case 'ru':
        return 'Russian';
      case 'jpn':
      case 'ja':
        return 'Japanese';
      case 'kor':
      case 'ko':
        return 'Korean';
      case 'chi':
      case 'zho':
      case 'zh':
        return 'Chinese';
      case 'ara':
      case 'ar':
        return 'Arabic';
      default:
        return c.isNotEmpty ? c.toUpperCase() : 'Subtitle Track';
    }
  }

  void _startPositionTracking() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_isDisposed) return;
      final controller = _betterPlayerController?.videoPlayerController;
      if (controller != null && controller.value.initialized) {
        final newPosition = controller.value.position;
        final newDuration = controller.value.duration ?? Duration.zero;
        // Track buffered position
        final bufferedRanges = controller.value.buffered;
        Duration newBuffered = Duration.zero;
        if (bufferedRanges.isNotEmpty) {
          newBuffered = bufferedRanges.last.end;
        }
        if (newPosition != _position || newDuration != _duration || newBuffered != _buffered) {
          _position = newPosition;
          _duration = newDuration;
          _buffered = newBuffered;
          onProgressUpdate?.call(_position, _duration);
          _safeNotify();
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

  void play() {
    _betterPlayerController?.play();
  }

  void pause() {
    _betterPlayerController?.pause();
  }

  void seekTo(Duration position) {
    final vp = _betterPlayerController?.videoPlayerController;
    if (vp == null || !vp.value.initialized) return;
    _betterPlayerController?.seekTo(position);
  }

  void seekRelative(Duration offset) {
    final vp = _betterPlayerController?.videoPlayerController;
    if (vp == null || !vp.value.initialized) return;
    final newPos = _position + offset;
    final clamped = newPos < Duration.zero
        ? Duration.zero
        : (newPos > _duration ? _duration : newPos);
    seekTo(clamped);
  }

  /// Skip forward 10 seconds (CloudStream-style)
  void skipForward() {
    seekRelative(const Duration(seconds: 10));
  }

  /// Skip backward 10 seconds (CloudStream-style)
  void skipBackward() {
    seekRelative(const Duration(seconds: -10));
  }

  /// Navigate to next episode
  void nextEpisode() {
    if (!hasNextEpisode || _season == null || _episode == null) return;
    onNextEpisode?.call(_season!, _episode! + 1);
  }

  /// Navigate to previous episode
  void previousEpisode() {
    if (!hasPreviousEpisode || _season == null || _episode == null) return;
    onPreviousEpisode?.call(_season!, _episode! - 1);
  }

  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    _betterPlayerController?.setSpeed(speed);
    _safeNotify();
  }

  void setResizeMode(VideoResizeMode mode) {
    _resizeMode = mode;
    _betterPlayerController?.setOverriddenFit(_getBetterPlayerFit());
    _safeNotify();
  }

  /// Cycle through resize modes: fit → fill → zoom → fit
  void cycleResizeMode() {
    switch (_resizeMode) {
      case VideoResizeMode.fit:
        setResizeMode(VideoResizeMode.fill);
        break;
      case VideoResizeMode.fill:
        setResizeMode(VideoResizeMode.zoom);
        break;
      case VideoResizeMode.zoom:
        setResizeMode(VideoResizeMode.fit);
        break;
    }
  }

  String get resizeModeLabel {
    switch (_resizeMode) {
      case VideoResizeMode.fit:
        return 'Fit';
      case VideoResizeMode.fill:
        return 'Fill';
      case VideoResizeMode.zoom:
        return 'Stretch';
    }
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

  // ─── Audio Track Switching ─────────────────────────────────────────────

  /// Set audio track by index from the available audio tracks list.
  void setAudioTrack(BetterPlayerAsmsAudioTrack track) {
    if (_betterPlayerController == null) return;
    _currentAudioTrack = track;
    try {
      final trackToSet = BetterPlayerAsmsAudioTrack(
        id: track.id,
        label: track.label,
        language: track.language ?? track.label ?? 'und',
        url: track.url,
      );
      _betterPlayerController!.setAudioTrack(trackToSet);
      _betterPlayerController!.videoPlayerController?.setAudioTrack(
        track.label ?? track.language,
        track.id,
      );
      debugPrint('[PlayerController] Switched audio to: ${track.label ?? track.language} (id: ${track.id})');
    } catch (e) {
      debugPrint('[PlayerController] Error switching audio: $e');
    }
    _safeNotify();
  }

  // ─── Subtitle Track Switching ──────────────────────────────────────────

  /// Set subtitle source from the available subtitle sources list.
  void setSubtitleSource(BetterPlayerSubtitlesSource source) {
    if (_betterPlayerController == null) return;
    if (source.type == BetterPlayerSubtitlesSourceType.none || source.name == 'Off') {
      disableSubtitles();
      return;
    }

    _currentSubtitleSource = source;
    final nonNone = _subtitleSources
        .where((s) => s.type != BetterPlayerSubtitlesSourceType.none && s.name != 'Off')
        .toList();
    final idx = nonNone.indexOf(source);

    // Call native text track selection on ExoPlayer
    _betterPlayerController!.setTextTrack(source.name, idx >= 0 ? idx : 0);

    // Also pass to BetterPlayer in case it has external parsed subtitles
    if (source.urls != null && source.urls!.isNotEmpty) {
      _betterPlayerController!.setupSubtitleSource(source);
    }
    debugPrint('[PlayerController] Switched subtitle to: ${source.name} (index: $idx)');
    _safeNotify();
  }

  /// Disable subtitles.
  void disableSubtitles() {
    if (_betterPlayerController == null) return;
    // Tell native ExoPlayer to disable subtitles
    _betterPlayerController!.setTextTrack(null, -1);

    final noneSource = _subtitleSources.firstWhere(
      (s) => s.type == BetterPlayerSubtitlesSourceType.none,
      orElse: () => BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.none, name: 'Off'),
    );
    _betterPlayerController!.setupSubtitleSource(noneSource);
    _currentSubtitleSource = null;
    _currentCues = [];
    debugPrint('[PlayerController] Disabled subtitles');
    _safeNotify();
  }

  /// Check if audio tracks are available.
  bool get hasAudioTracks => _audioTracks.length > 1;

  /// Check if subtitle sources are available.
  bool get hasSubtitles => _subtitleSources.any((s) => s.type != BetterPlayerSubtitlesSourceType.none);

  /// Check if a subtitle track is currently active (not off/none)
  bool get isSubtitleActive =>
      _currentSubtitleSource != null &&
      _currentSubtitleSource?.type != BetterPlayerSubtitlesSourceType.none &&
      _currentSubtitleSource?.name != 'Off';

  // ─── Controls Visibility ───────────────────────────────────────────────

  void showControls() {
    if (_isLocked) return;
    _controlsVisible = true;
    _safeNotify();
    _resetControlsTimer();
  }

  void hideControls() {
    _controlsVisible = false;
    _controlsTimer?.cancel();
    _safeNotify();
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
    _safeNotify();
  }

  // ─── Retry ─────────────────────────────────────────────────────────────

  Future<void> retry() async {
    if (_isDisposed) return;
    _state = PlaybackState.extracting;
    _errorMessage = null;
    _sources.clear();
    _providerStatuses.clear();
    _safeNotify();
    await _startExtraction();
  }

  // ─── Cleanup ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    _isDisposed = true;
    _controlsTimer?.cancel();
    _positionTimer?.cancel();
    _betterPlayerController?.removeEventsListener(_onPlayerEvent);
    _betterPlayerController?.dispose();
    _betterPlayerController = null;

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
