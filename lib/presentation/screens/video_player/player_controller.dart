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
import '../../../services/extraction/site_post_extractor.dart';

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
  Duration? _targetSeekPosition;

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

  bool _isInPip = false;
  bool get isInPip => _isInPip;

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

  bool _subtitlesExplicitlyDisabled = true;
  bool get subtitlesExplicitlyDisabled => _subtitlesExplicitlyDisabled;

  // ─── Available Resolutions & Servers ────────────────────────────────────
  final Map<String, String> _availableResolutions = {};
  Map<String, String> get availableResolutions => _availableResolutions;

  String _selectedResolution = '720p';
  String get selectedResolution => _selectedResolution;

  Map<String, String> _currentServers = {};
  Map<String, String> get currentServers => _currentServers;

  String _selectedServer = '';
  String get selectedServer => _selectedServer;

  final Map<String, int> _subtitleNativeIndices = {};

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
    int? year,
    String? imdbId,
    int? season,
    int? episode,
    String? directUrl,
    double? startPosition,
    List<int>? seasonNumbers,
    int? totalEpisodes,
    Future<String?> Function()? streamResolver,
    Map<String, String>? initialResolutionMap,
    Future<Map<String, String>> Function()? resolutionMapResolver,
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
    _subtitlesExplicitlyDisabled = true;

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
          final initialLink = ExtractorLink(
            sourceName: 'VCloud',
            displayName: 'Auto (720p)',
            url: resolvedUrl,
            quality: 720,
          );
          _sources.add(initialLink);

          // Populate initial resolutions if provided
          if (initialResolutionMap != null && initialResolutionMap.isNotEmpty) {
            _populateResolutionMap(initialResolutionMap);
          }

          await _playSource(_sources.first, startPosition: startPosition);

          // Background resolution resolver
          if (resolutionMapResolver != null) {
            _resolveBackgroundResolutions(resolutionMapResolver);
          }

          // Run extraction in background to load all other resolutions & servers for switching
          _startExtraction(startPosition: startPosition, isBackground: true);
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
      if (initialResolutionMap != null && initialResolutionMap.isNotEmpty) {
        _populateResolutionMap(initialResolutionMap);
      }
      if (resolutionMapResolver != null) {
        _resolveBackgroundResolutions(resolutionMapResolver);
      }
      await _startExtraction(startPosition: startPosition);
    }
  }

  void _populateResolutionMap(Map<String, String> resMap) {
    _availableResolutions.addAll(resMap);

    // If current source matches a resolution, set _selectedResolution
    for (final k in resMap.keys) {
      if (_currentSource != null &&
          (_currentSource!.displayName.toLowerCase().contains(k.toLowerCase()) ||
           (_currentSource!.quality > 0 && '${_currentSource!.quality}p'.toLowerCase() == k.toLowerCase()))) {
        _selectedResolution = k;
        break;
      }
    }

    for (final entry in resMap.entries) {
      final res = entry.key; // e.g. "480p", "720p", "1080p", "2160p"
      final url = entry.value;
      if (url.isEmpty) continue;

      int qVal = 720;
      if (res.contains('480')) {
        qVal = 480;
      } else if (res.contains('1080')) {
        qVal = 1080;
      } else if (res.contains('2160') || res.contains('4k')) {
        qVal = 2160;
      }

      // Check if resolution is already in _sources
      final alreadyExists = _sources.any((s) =>
          s.quality == qVal ||
          s.displayName.toLowerCase().contains(res.toLowerCase()));

      if (!alreadyExists) {
        _sources.add(ExtractorLink(
          sourceName: 'VCloud',
          displayName: res.toUpperCase(),
          url: url,
          quality: qVal,
        ));
      }
    }
    _safeNotify();
  }

  void _resolveBackgroundResolutions(
      Future<Map<String, String>> Function() resolver) async {
    try {
      final resMap = await resolver();
      if (!_isDisposed && resMap.isNotEmpty) {
        _populateResolutionMap(resMap);
      }
    } catch (e) {
      debugPrint('[PlayerController] Error resolving background resolutions: $e');
    }
  }

  // ─── Extraction ────────────────────────────────────────────────────────

  Future<void> _startExtraction({double? startPosition, bool isBackground = false}) async {
    bool firstLinkPlayed = isBackground;

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

          // STRICT RULE: Never play online with 10Gbps / Server 3 links!
          final lowerUrl = link.url.toLowerCase();
          final lowerName = link.displayName.toLowerCase();
          if (lowerName.contains('server 3') ||
              lowerName.contains('10gbps') ||
              lowerUrl.contains('hubcloud') ||
              lowerUrl.contains('gpdl')) {
            debugPrint('[PlayerController] Skipping 10Gbps link for online play: ${link.displayName}');
            return;
          }

          // Avoid duplicate links
          if (!_sources.any((s) => s.url == link.url)) {
            _sources.add(link);
            _safeNotify();
          }

          // Auto-play the first link found (priority 720p > 480p > 1080p from provider)
          if (!firstLinkPlayed && !isBackground) {
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
      if (_sources.isEmpty && !isBackground) {
        _state = PlaybackState.error;
        _errorMessage = 'No streaming sources found';
        _safeNotify();
      }
    } catch (e) {
      debugPrint('[PlayerController] Extraction error: $e');
      if (_isDisposed) return;
      if (_sources.isEmpty && !isBackground) {
        _state = PlaybackState.error;
        _errorMessage = 'Extraction failed: $e';
        _safeNotify();
      }
    }
  }

  // ─── Playback ──────────────────────────────────────────────────────────

  /// Play a specific source.
  Future<void> _playSource(
    ExtractorLink source, {
    double? startPosition,
    bool skipServerExtraction = false,
  }) async {
    if (_isDisposed) return;
    _state = PlaybackState.buffering;
    _currentSource = source;
    _errorMessage = null;
    if (startPosition != null && startPosition > 0) {
      _targetSeekPosition = Duration(milliseconds: (startPosition * 1000).toInt());
    } else {
      _targetSeekPosition = null;
    }
    _safeNotify();

    String playableUrl = source.url;
    final lower = playableUrl.toLowerCase();
    if (!skipServerExtraction &&
        (lower.contains('vcloud') ||
         lower.contains('v-cloud') ||
         lower.contains('hubcloud') ||
         lower.contains('nexdrive') ||
         lower.contains('vgmlink') ||
         lower.contains('fastdl') ||
         lower.contains('vegadrive') ||
         lower.contains('gdflix') ||
         lower.contains('filebee') ||
         lower.contains('download.php') ||
         lower.contains('/drive/'))) {
      try {
        final streamRes =
            await SitePostExtractor.instance.resolveVcloudStream(playableUrl);

        final newServers = <String, String>{};
        if (streamRes.fslv2Url != null && streamRes.fslv2Url!.isNotEmpty) {
          newServers['Server 2 (FSLv2)'] = streamRes.fslv2Url!;
        }
        if (streamRes.fslUrl != null && streamRes.fslUrl!.isNotEmpty) {
          newServers['Server 1 (FSL)'] = streamRes.fslUrl!;
        }
        if (streamRes.fastDlUrl != null && streamRes.fastDlUrl!.isNotEmpty) {
          newServers['FastDL [Google]'] = streamRes.fastDlUrl!;
        }
        if (streamRes.pixeldrainUrl != null && streamRes.pixeldrainUrl!.isNotEmpty) {
          final px = streamRes.pixeldrainUrl!;
          final cleanPx = px.contains('/u/')
              ? 'https://pixeldrain.dev/api/file/${px.split('/u/').last.split('?').first.trim()}'
              : px;
          newServers['Pixeldrain'] = cleanPx;
        }

        if (newServers.isNotEmpty) {
          _currentServers = newServers;
        }

        if (streamRes.canStreamOnline && streamRes.onlineStreamUrl != null) {
          playableUrl = streamRes.onlineStreamUrl!; // Strictly FSLv2 > FSL > FastDL > Pixeldrain
          if (playableUrl == streamRes.fslv2Url) {
            _selectedServer = 'Server 2 (FSLv2)';
          } else if (playableUrl == streamRes.fslUrl) {
            _selectedServer = 'Server 1 (FSL)';
          } else if (playableUrl == streamRes.fastDlUrl) {
            _selectedServer = 'FastDL [Google]';
          } else {
            _selectedServer = 'Pixeldrain';
          }
        } else {
          final servers =
              await VcloudExtractorService().extractVcloud(playableUrl);
          final vcloudServers = <String, String>{};
          if (servers.containsKey('Server 2') &&
              servers['Server 2']!.isNotEmpty) {
            vcloudServers['Server 2 (FSLv2)'] = servers['Server 2']!;
          }
          if (servers.containsKey('Server 1') &&
              servers['Server 1']!.isNotEmpty) {
            vcloudServers['Server 1 (FSL)'] = servers['Server 1']!;
          }
          if (servers.containsKey('PixelServer') &&
              servers['PixelServer']!.isNotEmpty) {
            vcloudServers['Pixeldrain'] = servers['PixelServer']!;
          }

          if (vcloudServers.isNotEmpty) {
            _currentServers = vcloudServers;
          }

          if (servers.containsKey('Server 2') &&
              servers['Server 2']!.isNotEmpty) {
            playableUrl = servers['Server 2']!;
            _selectedServer = 'Server 2 (FSLv2)';
          } else if (servers.containsKey('Server 1') &&
              servers['Server 1']!.isNotEmpty) {
            playableUrl = servers['Server 1']!;
            _selectedServer = 'Server 1 (FSL)';
          } else if (servers.containsKey('PixelServer') &&
              servers['PixelServer']!.isNotEmpty) {
            playableUrl = servers['PixelServer']!;
            _selectedServer = 'Pixeldrain';
          }
        }
      } catch (e) {
        debugPrint(
            '[PlayerController] Error resolving target resolution stream: $e');
      }
    } else {
      if (_selectedServer.isEmpty) {
        if (playableUrl.contains('fslv2') || playableUrl.contains('s3.')) {
          _selectedServer = 'Server 2 (FSLv2)';
        } else if (playableUrl.contains('fsl') || playableUrl.contains('s1.')) {
          _selectedServer = 'Server 1 (FSL)';
        } else if (playableUrl.contains('fastdl') || playableUrl.contains('googleusercontent')) {
          _selectedServer = 'FastDL [Google]';
        } else if (playableUrl.contains('pixeldrain')) {
          _selectedServer = 'Pixeldrain';
        } else {
          _selectedServer = source.displayName.isNotEmpty ? source.displayName : 'Server 1';
        }
      }
      if (_currentServers.isEmpty) {
        _currentServers[_selectedServer] = playableUrl;
      }
    }

    final targetSource = ExtractorLink(
      sourceName: source.sourceName,
      displayName: source.displayName,
      url: playableUrl,
      quality: source.quality,
      type: source.type,
      headers: source.headers,
    );

    // Update in _sources list
    final srcIdx =
        _sources.indexWhere((s) => s.displayName == source.displayName);
    if (srcIdx >= 0) {
      _sources[srcIdx] = targetSource;
    }
    _currentSource = targetSource;

    try {
      // Dispose previous controller if exists
      _betterPlayerController?.removeEventsListener(_onPlayerEvent);
      _betterPlayerController?.dispose();
      _betterPlayerController = null;

      final isLocalFile = targetSource.url.startsWith('/') || !targetSource.url.startsWith('http');
      final isHls = targetSource.resolvedType == LinkType.m3u8 ||
          targetSource.url.toLowerCase().contains('.m3u8') ||
          targetSource.url.toLowerCase().contains('hsl') ||
          targetSource.url.toLowerCase().contains('master');

      final dataSource = isLocalFile
          ? BetterPlayerDataSource(
              BetterPlayerDataSourceType.file,
              targetSource.url,
            )
          : BetterPlayerDataSource(
              BetterPlayerDataSourceType.network,
              targetSource.url,
              headers: targetSource.headers.isNotEmpty
                  ? targetSource.headers
                  : {
                      if (!targetSource.url.contains('google') && !targetSource.url.contains('storage')) ...{
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
                minBufferMs: 20000,
                maxBufferMs: 50000,
                bufferForPlaybackMs: 1500,
                bufferForPlaybackAfterRebufferMs: 3000,
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

      // Ensure volume is at 1.0 (full volume)
      try {
        _betterPlayerController!.setVolume(1.0);
      } catch (_) {}

      if (startPosition != null && startPosition > 0) {
        _targetSeekPosition =
            Duration(milliseconds: (startPosition * 1000).toInt());
      }

      // Listen to events
      _betterPlayerController!.addEventsListener(_onPlayerEvent);

      // Start position tracking
      _startPositionTracking();

      debugPrint('[PlayerController] Playing: ${targetSource.displayName} (${targetSource.url})');
    } catch (e) {
      debugPrint('[PlayerController] Play error: $e');
      // Auto-try next source on failure
      _tryNextSource(targetSource, startPosition: startPosition);
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

  /// Switch resolution (e.g. "480p", "720p", "1080p", "2160p" / "4k") with timestamp preservation.
  Future<void> switchResolution(String resKey) async {
    final targetUrl = _availableResolutions[resKey] ??
        _availableResolutions.entries
            .firstWhere(
              (e) => e.key.toLowerCase().contains(resKey.toLowerCase()),
              orElse: () => const MapEntry('', ''),
            )
            .value;

    if (targetUrl.isEmpty) {
      debugPrint('[PlayerController] switchResolution: No link found for $resKey');
      return;
    }

    _selectedResolution = resKey;
    final currentPos = _position;
    final startSeconds = currentPos.inMilliseconds / 1000.0;

    int qVal = 720;
    if (resKey.contains('480')) {
      qVal = 480;
    } else if (resKey.contains('1080')) {
      qVal = 1080;
    } else if (resKey.contains('2160') || resKey.contains('4k')) {
      qVal = 2160;
    }

    _state = PlaybackState.buffering;
    _safeNotify();

    String streamUrl = targetUrl;
    final lower = targetUrl.toLowerCase();
    if (lower.contains('vcloud') ||
        lower.contains('v-cloud') ||
        lower.contains('hubcloud') ||
        lower.contains('nexdrive') ||
        lower.contains('vgmlink') ||
        lower.contains('fastdl') ||
        lower.contains('download.php') ||
        lower.contains('/drive/')) {
      try {
        final res = await SitePostExtractor.instance.resolveVcloudStream(targetUrl);
        if (res.canStreamOnline && res.onlineStreamUrl != null) {
          streamUrl = res.onlineStreamUrl!;
        } else {
          final servers = await VcloudExtractorService().extractVcloud(targetUrl);
          if (servers.containsKey('Server 2') && servers['Server 2']!.isNotEmpty) {
            streamUrl = servers['Server 2']!;
          } else if (servers.containsKey('Server 1') &&
              servers['Server 1']!.isNotEmpty) {
            streamUrl = servers['Server 1']!;
          } else if (servers.containsKey('PixelServer') && servers['PixelServer']!.isNotEmpty) {
            streamUrl = servers['PixelServer']!;
          }
        }
      } catch (e) {
        debugPrint('[PlayerController] Error resolving resolution link: $e');
      }
    }

    final targetSource = ExtractorLink(
      sourceName: 'VCloud',
      displayName: resKey.toUpperCase(),
      url: streamUrl,
      quality: qVal,
    );

    await _playSource(targetSource, startPosition: startSeconds);
  }

  /// Switch to a different direct server (e.g. "Server 2 (FSLv2)", "Server 1 (FSL)", "FastDL", "Pixeldrain")
  Future<void> switchServer(String serverName, String streamUrl) async {
    if (streamUrl.isEmpty) return;
    _selectedServer = serverName;
    final currentPos = _position;
    final startSeconds = currentPos.inMilliseconds / 1000.0;

    final targetSource = ExtractorLink(
      sourceName: serverName,
      displayName: serverName,
      url: streamUrl,
      quality: _currentSource?.quality ?? 720,
    );

    await _playSource(targetSource,
        startPosition: startSeconds, skipServerExtraction: true);
  }

  /// Switch to a different source / resolution with timestamp preservation.
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
        _betterPlayerController?.setVolume(1.0);
        if (_betterPlayerController?.videoPlayerController?.value.duration !=
            null) {
          _duration = _betterPlayerController!
              .videoPlayerController!.value.duration!;
        }
        if (_targetSeekPosition != null && _targetSeekPosition! > Duration.zero) {
          _betterPlayerController?.seekTo(_targetSeekPosition!);
          _position = _targetSeekPosition!;
          _targetSeekPosition = null;
        }
        _updateTracksAndSubtitles();
        notifyListeners();
        break;
      case BetterPlayerEventType.play:
        _state = PlaybackState.playing;
        _isPlaying = true;
        _betterPlayerController?.setVolume(1.0);
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
        final exDesc = event.parameters?['exception'];
        debugPrint('[PlayerController] Playback exception: $exDesc');
        _state = PlaybackState.error;
        _errorMessage = 'Playback error: ${exDesc ?? "Unknown error"}';
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
        for (int i = 0; i < nativeAudio.length; i++)
          BetterPlayerAsmsAudioTrack(
            id: nativeAudio[i]['index'] as int?,
            label: _cleanLanguageName(
              nativeAudio[i]['language'] as String?,
              nativeAudio[i]['label'] as String?,
              channels: nativeAudio[i]['channels'] as int?,
              trackIndex: i,
              totalTracks: nativeAudio.length,
            ),
            language: nativeAudio[i]['language'] as String?,
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
    _subtitleNativeIndices.clear();
    if (nativeText.isNotEmpty) {
      // First pass: count languages
      final langCounts = <String, int>{};
      for (final t in nativeText) {
        final code = (t['language'] as String? ?? '').toLowerCase();
        final rawLang = _mapCodeToLanguageName(code);
        final lang = rawLang.isNotEmpty ? rawLang : 'Subtitle';
        langCounts[lang] = (langCounts[lang] ?? 0) + 1;
      }

      final langCurrentIndex = <String, int>{};
      final generatedSources = <BetterPlayerSubtitlesSource>[];

      for (int i = 0; i < nativeText.length; i++) {
        final t = nativeText[i];
        final code = (t['language'] as String? ?? '').toLowerCase();
        final rawLang = _mapCodeToLanguageName(code);
        final lang = rawLang.isNotEmpty ? rawLang : 'Subtitle';
        final occ = (langCurrentIndex[lang] ?? 0) + 1;
        langCurrentIndex[lang] = occ;

        final subName = _cleanSubtitleName(
          t['language'] as String?,
          t['label'] as String?,
          trackIndex: i,
          occurrence: occ,
          totalSameLanguage: langCounts[lang] ?? 1,
        );

        final nativeIdx = t['index'] as int? ?? i;
        _subtitleNativeIndices[subName] = nativeIdx;

        generatedSources.add(BetterPlayerSubtitlesSource(
          type: BetterPlayerSubtitlesSourceType.network,
          name: subName,
          selectedByDefault: t['selected'] as bool? ?? false,
        ));
      }

      _subtitleSources = [
        BetterPlayerSubtitlesSource(
          type: BetterPlayerSubtitlesSourceType.none,
          name: 'Off',
        ),
        ...generatedSources,
      ];

      if (!_subtitlesExplicitlyDisabled) {
        final selIdx = nativeText.indexWhere((t) => t['selected'] == true);
        if (selIdx >= 0 && selIdx < generatedSources.length) {
          _currentSubtitleSource = generatedSources[selIdx];
          final nativeIdx = _subtitleNativeIndices[_currentSubtitleSource!.name!] ?? selIdx;
          _betterPlayerController?.setTextTrack(_currentSubtitleSource!.name, nativeIdx);
        } else {
          // Auto-select first English track that is NOT forced (or first valid track)
          final engTracks = generatedSources
              .where((s) => (s.name ?? '').toLowerCase().contains('english'))
              .toList();
          final pick = engTracks.firstWhere(
            (s) => !(s.name ?? '').toLowerCase().contains('forced'),
            orElse: () => engTracks.isNotEmpty
                ? engTracks.first
                : (generatedSources.isNotEmpty ? generatedSources.first : _subtitleSources.first),
          );
          if (pick.type != BetterPlayerSubtitlesSourceType.none && pick.name != 'Off') {
            _currentSubtitleSource = pick;
            final nativeIdx = _subtitleNativeIndices[pick.name!] ?? 0;
            _betterPlayerController?.setTextTrack(pick.name, nativeIdx);
          }
        }
      } else {
        _currentSubtitleSource = _subtitleSources.first;
        _betterPlayerController?.setTextTrack(null, -1);
        _currentCues = [];
      }
    } else {
      final subs = _betterPlayerController!.betterPlayerSubtitlesSourceList;
      if (subs.isNotEmpty) {
        _subtitleSources = subs;
        if (!_subtitlesExplicitlyDisabled) {
          _currentSubtitleSource =
              _betterPlayerController!.betterPlayerSubtitlesSource ??
                  _subtitleSources.firstWhere(
                    (s) =>
                        s.type != BetterPlayerSubtitlesSourceType.none &&
                        s.name != 'Off',
                    orElse: () => _subtitleSources.first,
                  );
        } else {
          _currentSubtitleSource = _subtitleSources.firstWhere(
            (s) => s.type == BetterPlayerSubtitlesSourceType.none || s.name == 'Off',
            orElse: () => _subtitleSources.first,
          );
          _betterPlayerController?.setTextTrack(null, -1);
          _currentCues = [];
        }
      } else if (_currentSource?.url.toLowerCase().contains('.mkv') == true) {
        _subtitleSources = [
          BetterPlayerSubtitlesSource(
              type: BetterPlayerSubtitlesSourceType.none, name: 'Off'),
          BetterPlayerSubtitlesSource(
              type: BetterPlayerSubtitlesSourceType.network, name: 'English'),
        ];
        if (!_subtitlesExplicitlyDisabled) {
          _currentSubtitleSource = _subtitleSources[1];
        } else {
          _currentSubtitleSource = _subtitleSources.first;
          _betterPlayerController?.setTextTrack(null, -1);
          _currentCues = [];
        }
      }
    }
  }

  String _mapCodeToLanguageName(String code) {
    final c = code.toLowerCase().trim();
    switch (c) {
      case 'hin':
      case 'hi':
        return 'Hindi';
      case 'eng':
      case 'en':
        return 'English';
      case 'tam':
      case 'ta':
        return 'Tamil';
      case 'tel':
      case 'te':
        return 'Telugu';
      case 'ben':
      case 'bn':
        return 'Bengali';
      case 'mal':
      case 'ml':
        return 'Malayalam';
      case 'kan':
      case 'kn':
        return 'Kannada';
      case 'mar':
      case 'mr':
        return 'Marathi';
      case 'guj':
      case 'gu':
        return 'Gujarati';
      case 'pan':
      case 'pa':
        return 'Punjabi';
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
      case 'tur':
      case 'tr':
        return 'Turkish';
      case 'twi':
        return 'Twi';
      case 'tha':
        return 'Thai';
      case 'vie':
        return 'Vietnamese';
      case 'ind':
        return 'Indonesian';
      case 'urd':
      case 'ur':
        return 'Urdu';
      default:
        return '';
    }
  }

  List<String> _extractLanguagesFromText(String text) {
    final lower = text.toLowerCase();
    final List<MapEntry<int, String>> found = [];

    void check(String pattern, String name) {
      final idx = lower.indexOf(pattern);
      if (idx != -1) {
        found.add(MapEntry(idx, name));
      }
    }

    check('hindi', 'Hindi');
    check('english', 'English');
    check('tamil', 'Tamil');
    check('telugu', 'Telugu');
    check('spanish', 'Spanish');
    check('french', 'French');
    check('german', 'German');
    check('italian', 'Italian');
    check('japanese', 'Japanese');
    check('korean', 'Korean');
    check('chinese', 'Chinese');
    check('bengali', 'Bengali');
    check('malayalam', 'Malayalam');
    check('kannada', 'Kannada');
    check('marathi', 'Marathi');
    check('punjabi', 'Punjabi');
    check('russian', 'Russian');
    check('portuguese', 'Portuguese');
    check('arabic', 'Arabic');
    check('turkish', 'Turkish');

    found.sort((a, b) => a.key.compareTo(b.key));
    final result = <String>[];
    for (final e in found) {
      if (!result.contains(e.value)) {
        result.add(e.value);
      }
    }
    return result;
  }

  String _cleanLanguageName(
    String? code,
    String? label, {
    int? channels,
    int trackIndex = 0,
    int totalTracks = 1,
  }) {
    final c = (code ?? '').toLowerCase().trim();
    String l = (label ?? '').trim();

    // Remove common watermarks like 1VegaMovies.tw or Vegamovies or Hubcloud
    l = l.replaceAll(RegExp(r'(?:1)?vegamovies(?:\.tw|\.com)?', caseSensitive: false), '')
         .replaceAll(RegExp(r'hubcloud(?:\.ninja|\.club)?', caseSensitive: false), '')
         .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '')
         .replaceAll(RegExp(r'www\.\S+', caseSensitive: false), '')
         .replaceAll(RegExp(r'[\-_\[\]\(\)]+'), ' ')
         .trim();

    String langName = '';

    // 1. Try code if valid (not 'und', 'unk', 'mis', 'mul')
    if (c.isNotEmpty && c != 'und' && c != 'unk' && c != 'mis' && c != 'mul') {
      langName = _mapCodeToLanguageName(c);
      if (langName.isEmpty && (c.length == 2 || c.length == 3)) {
        langName = c.toUpperCase();
      }
    }

    // 2. Try label if code didn't resolve
    if (langName.isEmpty && l.isNotEmpty) {
      final langsInLabel = _extractLanguagesFromText(l);
      if (langsInLabel.isNotEmpty) {
        langName = langsInLabel.first;
      } else if (l.length > 2 && !l.toLowerCase().contains('audio')) {
        langName = l;
      }
    }

    // 3. Try VcloudExtractorService().lastLanguages
    if (langName.isEmpty) {
      final lastLangs = VcloudExtractorService().lastLanguages;
      if (lastLangs.isNotEmpty && trackIndex < lastLangs.length) {
        langName = lastLangs[trackIndex];
      }
    }

    // 4. Try title or source displayName
    if (langName.isEmpty) {
      final scanText = '$_title ${_currentSource?.displayName ?? ''}';
      final langsInTitle = _extractLanguagesFromText(scanText);
      if (langsInTitle.isNotEmpty && trackIndex < langsInTitle.length) {
        langName = langsInTitle[trackIndex];
      } else if (scanText.toLowerCase().contains('dual audio') || scanText.toLowerCase().contains('dual')) {
        // Dual audio convention: Track 0 is Hindi, Track 1 is English
        if (trackIndex == 0) {
          langName = 'Hindi';
        } else if (trackIndex == 1) {
          langName = 'English';
        }
      }
    }

    // 5. Final fallback - NEVER return 'UND' or 'und'
    if (langName.isEmpty || langName.toLowerCase() == 'und') {
      if (totalTracks == 1) {
        if (_title.toLowerCase().contains('hindi')) {
          langName = 'Hindi';
        } else if (_title.toLowerCase().contains('english')) {
          langName = 'English';
        } else {
          langName = 'Default Audio';
        }
      } else {
        if (trackIndex == 0 && (_title.toLowerCase().contains('hindi') || _title.toLowerCase().contains('dual'))) {
          langName = 'Hindi';
        } else if (trackIndex == 1 && (_title.toLowerCase().contains('english') || _title.toLowerCase().contains('dual'))) {
          langName = 'English';
        } else {
          langName = 'Audio Track ${trackIndex + 1}';
        }
      }
    }

    // 6. Channel info
    if (channels != null && channels > 0) {
      if (channels == 6 && !langName.contains('5.1')) {
        langName = '$langName (5.1)';
      } else if (channels == 8 && !langName.contains('7.1')) {
        langName = '$langName (7.1)';
      }
    }

    return langName;
  }

  String _cleanSubtitleName(
    String? code,
    String? label, {
    int trackIndex = 0,
    int occurrence = 1,
    int totalSameLanguage = 1,
  }) {
    final c = (code ?? '').toLowerCase().trim();
    String l = (label ?? '').trim();

    final isWatermarkOnly = l.toLowerCase() == '1vegamovies.tw' ||
        l.toLowerCase() == 'vegamovies' ||
        l.toLowerCase() == 'hubcloud' ||
        l.toLowerCase() == 'vegamovies.tw';
    if (isWatermarkOnly) l = '';

    String baseName = '';
    if (c.isNotEmpty && c != 'und' && c != 'unk') {
      baseName = _mapCodeToLanguageName(c);
    }
    if (baseName.isEmpty && l.isNotEmpty) {
      final langsInLabel = _extractLanguagesFromText(l);
      if (langsInLabel.isNotEmpty) {
        baseName = langsInLabel.first;
      }
    }
    if (baseName.isEmpty) {
      baseName = 'Subtitle';
    }

    // Check tags: SDH, Forced, Full
    final lowerLabel = l.toLowerCase();
    String tag = '';
    if (lowerLabel.contains('forced')) {
      tag = 'Forced';
    } else if (lowerLabel.contains('sdh')) {
      tag = 'SDH';
    } else if (lowerLabel.contains('full')) {
      tag = 'Full';
    }

    if (tag.isNotEmpty) {
      return totalSameLanguage > 1
          ? '$baseName ($tag $occurrence)'
          : '$baseName ($tag)';
    }

    if (totalSameLanguage > 1) {
      return '$baseName $occurrence';
    }

    return baseName;
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
          // Only trigger UI rebuild if controls are currently on screen and not in PiP
          if (_controlsVisible && !_isInPip) {
            _safeNotify();
          }
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
    if (source.type == BetterPlayerSubtitlesSourceType.none ||
        source.name == 'Off') {
      disableSubtitles();
      return;
    }

    _subtitlesExplicitlyDisabled = false;
    _currentSubtitleSource = source;
    final nonNone = _subtitleSources
        .where((s) =>
            s.type != BetterPlayerSubtitlesSourceType.none && s.name != 'Off')
        .toList();
    final idx = nonNone.indexOf(source);
    final nativeIdx = _subtitleNativeIndices[source.name] ?? idx;

    // Call native text track selection on ExoPlayer
    _betterPlayerController!.setTextTrack(source.name, nativeIdx >= 0 ? nativeIdx : 0);

    // Also pass to BetterPlayer in case it has external parsed subtitles
    if (source.urls != null && source.urls!.isNotEmpty) {
      _betterPlayerController!.setupSubtitleSource(source);
    }
    debugPrint(
        '[PlayerController] Switched subtitle to: ${source.name} (index: $idx)');
    _safeNotify();
  }

  /// Current active subtitle texts from either ExoPlayer cues or parsed subtitle files.
  List<String> get activeSubtitleTexts {
    if (!isSubtitleActive) return const [];
    final validExoCues =
        _currentCues.where((c) => c.trim().isNotEmpty).toList();
    if (validExoCues.isNotEmpty) {
      return validExoCues;
    }
    final bp = _betterPlayerController;
    if (bp != null) {
      final rendered = bp.renderedSubtitle;
      if (rendered != null && rendered.texts != null) {
        final validTexts =
            rendered.texts!.where((c) => c.trim().isNotEmpty).toList();
        if (validTexts.isNotEmpty) return validTexts;
      }
      if (bp.subtitlesLines.isNotEmpty) {
        final pos = _position;
        for (final sub in bp.subtitlesLines) {
          if (sub.start != null &&
              sub.end != null &&
              sub.start! <= pos &&
              sub.end! >= pos) {
            if (sub.texts != null) {
              final validTexts =
                  sub.texts!.where((c) => c.trim().isNotEmpty).toList();
              if (validTexts.isNotEmpty) return validTexts;
            }
          }
        }
      }
    }
    return const [];
  }

  /// Disable subtitles.
  void disableSubtitles() {
    _subtitlesExplicitlyDisabled = true;
    if (_betterPlayerController == null) return;
    // Tell native ExoPlayer to disable subtitles
    _betterPlayerController!.setTextTrack(null, -1);

    final noneSource = _subtitleSources.firstWhere(
      (s) => s.type == BetterPlayerSubtitlesSourceType.none,
      orElse: () => BetterPlayerSubtitlesSource(
          type: BetterPlayerSubtitlesSourceType.none, name: 'Off'),
    );
    _betterPlayerController!.setupSubtitleSource(noneSource);
    _currentSubtitleSource = noneSource;
    _currentCues = [];
    debugPrint('[PlayerController] Disabled subtitles');
    _safeNotify();
  }

  /// Check if audio tracks are available.
  bool get hasAudioTracks => _audioTracks.length > 1;

  /// Check if subtitle sources are available.
  bool get hasSubtitles =>
      _subtitleSources.any((s) => s.type != BetterPlayerSubtitlesSourceType.none);

  /// Check if a subtitle track is currently active (not off/none)
  bool get isSubtitleActive =>
      !_subtitlesExplicitlyDisabled &&
      (_currentSubtitleSource == null ||
          (_currentSubtitleSource?.type !=
                  BetterPlayerSubtitlesSourceType.none &&
              _currentSubtitleSource?.name != 'Off'));

  // ─── Controls Visibility ───────────────────────────────────────────────

  bool _isModalOpen = false;
  bool get isModalOpen => _isModalOpen;

  void setPipMode(bool inPip) {
    _isInPip = inPip;
    if (inPip) {
      _isModalOpen = false;
      _controlsVisible = false;
      _controlsTimer?.cancel();
    }
    _safeNotify();
  }

  void setModalOpen(bool open) {
    if (_isInPip) return;
    _isModalOpen = open;
    if (open) {
      _controlsTimer?.cancel();
      _controlsVisible = true;
    } else {
      _resetControlsTimer();
    }
    _safeNotify();
  }

  void showControls() {
    if (_isLocked || _isInPip) return;
    _controlsVisible = true;
    _safeNotify();
    _resetControlsTimer();
  }

  void hideControls({bool force = false}) {
    if (_isModalOpen && !force && !_isInPip) return;
    _controlsVisible = false;
    _controlsTimer?.cancel();
    _safeNotify();
  }

  void toggleControls() {
    if (_isInPip) return;
    if (_controlsVisible) {
      hideControls();
    } else {
      showControls();
    }
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (_isModalOpen || _isInPip) return;
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (_isPlaying && _controlsVisible && !_isModalOpen && !_isInPip) {
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
