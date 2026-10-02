library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:better_player_plus/better_player_plus.dart';

import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../providers/watch_history_provider.dart';
import '../../providers/detail_provider.dart';
import '../../../pip/pip_controller.dart';
import '../../../services/peachify_extractor.dart';
import 'player_controller.dart';
import 'player_gestures.dart';
import 'player_overlay.dart';
import 'widgets/audio_track_selector_sheet.dart';
import 'widgets/subtitle_track_selector_sheet.dart';
import 'widgets/speed_selector_sheet.dart';
import 'widgets/source_selector_sheet.dart';

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
  final String? backdropUrl;
  final String? logoUrl;
  final String? description;
  final double? startPosition;
  final int? year;
  final String? imdbId;
  final Map<String, PeachifyStream>? extractedStreams;
  final bool is3rdPartyHosted;
  final Future<String?> Function()? streamResolver;

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
    this.year,
    this.imdbId,
    this.isOffline = false,
    this.isDirectLink = false,
    this.posterUrl,
    this.backdropUrl,
    this.logoUrl,
    this.description,
    this.startPosition,
    this.extractedStreams,
    this.is3rdPartyHosted = false,
    this.streamResolver,
  });

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen>
    with WidgetsBindingObserver {
  late final PlayerController _controller;
  String? _resolvedLogoUrl;
  Timer? _progressSaveTimer;
  bool _hasStartedPlaying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resolvedLogoUrl = widget.logoUrl;

    // Immediately force landscape and immersive sticky UI
    _lockLandscape();

    // Resolve TMDB logo if not provided
    _resolveLogoIfNeeded();

    // Setup native ExoPlayer PlayerController
    _controller = PlayerController();
    _controller.addListener(_onControllerUpdate);

    // Setup PiP listeners
    _setupPipListeners();

    // Periodic watch progress save
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _saveWatchProgress();
    });

    // Start playback flow with native ExoPlayer
    _controller.initialize(
      title: widget.title,
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      year: widget.year,
      imdbId: widget.imdbId,
      season: widget.season,
      episode: widget.episode,
      directUrl: widget.isDirectLink && widget.url.isNotEmpty ? widget.url : null,
      startPosition: widget.startPosition,
      seasonNumbers: widget.seasons,
      streamResolver: widget.streamResolver,
    );
  }

  void _onControllerUpdate() {
    if (_controller.state == PlaybackState.playing && !_hasStartedPlaying) {
      if (mounted) {
        setState(() {
          _hasStartedPlaying = true;
        });
      }
    }
  }

  Future<void> _lockLandscape() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _restoreOrientations() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _resolveLogoIfNeeded() {
    if (_resolvedLogoUrl == null || _resolvedLogoUrl!.isEmpty) {
      ref.read(
        tmdbLogoProvider(TmdbLogoParams(tmdbId: widget.tmdbId, mediaType: widget.mediaType)).future,
      ).then((logo) {
        if (mounted && logo != null && logo.isNotEmpty) {
          setState(() {
            _resolvedLogoUrl = logo;
          });
        }
      }).catchError((_) {});
    }
  }

  void _setupPipListeners() {
    PipController.instance.onPipAction = (action) {
      if (!mounted) return;
      switch (action) {
        case 'play':
          _controller.play();
          break;
        case 'pause':
          _controller.pause();
          break;
        case 'seekForward':
          _controller.skipForward();
          break;
        case 'seekBackward':
          _controller.skipBackward();
          break;
      }
    };
  }

  void _saveWatchProgress() {
    if (_controller.position == Duration.zero || _controller.duration == Duration.zero) return;

    try {
      ref.read(watchHistoryProvider.notifier).saveProgress(
            WatchHistoryItem(
              tmdbId: widget.tmdbId,
              mediaType: widget.mediaType,
              title: widget.title,
              posterUrl: widget.posterUrl,
              season: widget.season,
              episode: widget.episode,
              currentTime: _controller.position.inSeconds.toDouble(),
              duration: _controller.duration.inSeconds.toDouble(),
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    } catch (e) {
      debugPrint('[VideoPlayer] Error saving watch progress: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveWatchProgress();
    }
  }

  @override
  void dispose() {
    _saveWatchProgress();
    _progressSaveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    _restoreOrientations();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final isReady = _hasStartedPlaying &&
              _controller.betterPlayerController != null &&
              _controller.state != PlaybackState.extracting &&
              _controller.state != PlaybackState.idle;

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Native ExoPlayer Video Layer
              if (_controller.betterPlayerController != null)
                Positioned.fill(
                  child: Center(
                    child: BetterPlayer(
                      controller: _controller.betterPlayerController!,
                    ),
                  ),
                ),

              // 2. Subtitle Layer (Vidstack styled, subtle grey pill background, small text at center bottom)
              if (isReady)
                _buildSubtitleOverlay(context),

              // 3. Gesture Controls (VLC style) + Vidstack Player Overlay
              if (isReady)
                Positioned.fill(
                  child: PlayerGestures(
                    controller: _controller,
                    child: PlayerOverlay(
                      controller: _controller,
                      onBack: _handleBack,
                      onPipTap: _handlePip,
                    ),
                  ),
                ),

              // 4. Cinematic Landscape Loading Screen
              if (!isReady)
                _buildCinematicLoadingScreen(),
            ],
          );
        },
      ),
    );
  }

  // ─── Cinematic Landscape Loading Screen ──────────────────────────────────

  Widget _buildCinematicLoadingScreen() {
    final backdrop = widget.backdropUrl ?? widget.posterUrl;
    final logo = _resolvedLogoUrl;

    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Fullscreen Backdrop
            if (backdrop != null && backdrop.isNotEmpty)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.38,
                  child: Image.network(
                    backdrop,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.expand(),
                  ),
                ),
              ),

            // 2. Cinematic Gradient Scrim
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.70),
                      Colors.black.withValues(alpha: 0.95),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),

            // 3. Back Button (Top Left)
            Positioned(
              top: 16,
              left: 16,
              child: SafeArea(
                child: IconButton(
                  onPressed: _handleBack,
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    padding: const EdgeInsets.all(10),
                  ),
                ),
              ),
            ),

            // 4. Content Area (Logo, Title fallback, Description, Red Spinner)
            Positioned(
              left: 36,
              right: 36,
              bottom: 28,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo or single-line title fallback
                    if (logo != null && logo.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 70,
                          maxWidth: 280,
                        ),
                        child: CachedNetworkImage(
                          imageUrl: logo,
                          fit: BoxFit.contain,
                          alignment: Alignment.centerLeft,
                          errorWidget: (_, __, ___) => _buildTitleFallback(),
                        ),
                      )
                    else
                      _buildTitleFallback(),

                    // Episode badge if TV show
                    if (widget.mediaType == 'tv' && widget.episode != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Season ${widget.season ?? 1} • Episode ${widget.episode}',
                          style: GoogleFonts.inter(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),

                    // Description below logo/title
                    if (widget.description != null && widget.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.65,
                          ),
                          child: Text(
                            widget.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),

                    // Small Red Spinner Loader or Error
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: _controller.errorMessage != null
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                                const SizedBox(width: 10),
                                Text(
                                  _controller.errorMessage!,
                                  style: GoogleFonts.inter(
                                    color: Colors.redAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _controller.state == PlaybackState.extracting
                                      ? 'Resolving stream link...'
                                      : 'Connecting to video...',
                                  style: GoogleFonts.inter(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleFallback() {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.70,
      ),
      child: Text(
        widget.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.plusJakartaSans(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  // ─── Actions & Modals ───────────────────────────────────────────────────

  void _handleBack() {
    _saveWatchProgress();
    Navigator.of(context).pop();
  }

  void _handlePip() {
    try {
      PipController.instance.enterPipMode();
    } catch (e) {
      debugPrint('[VideoPlayer] PiP error: $e');
    }
  }

  void _showAudioSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AudioTrackSelectorSheet(controller: _controller),
    );
  }

  void _showSubtitleSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SubtitleTrackSelectorSheet(controller: _controller),
    );
  }

  void _showSpeedSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SpeedSelectorSheet(controller: _controller),
    );
  }

  void _showSourceSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SourceSelectorSheet(controller: _controller),
    );
  }

  void _showSettings() {
    _showSpeedSelector();
  }

  Widget _buildSubtitleOverlay(BuildContext context) {
    if (_controller.currentSubtitleSource == null ||
        _controller.currentSubtitleSource?.type == BetterPlayerSubtitlesSourceType.none ||
        _controller.currentSubtitleSource?.name == 'Off') {
      return const SizedBox.shrink();
    }

    final cues = _controller.currentCues.isNotEmpty
        ? _controller.currentCues
        : _controller.activeSubtitleTexts;
    if (cues.isEmpty) {
      return const SizedBox.shrink();
    }

    final cleanCues = <String>[];
    for (final rawCue in cues) {
      final clean = rawCue.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (clean.isNotEmpty) {
        cleanCues.add(clean);
      }
    }

    if (cleanCues.isEmpty) {
      return const SizedBox.shrink();
    }

    final safeBottom = MediaQuery.of(context).padding.bottom;
    final bottomPadding = _controller.controlsVisible
        ? safeBottom + 82.0
        : safeBottom + 20.0;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: 24,
      right: 24,
      bottom: bottomPadding,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
            decoration: BoxDecoration(
              color: const Color(0x6614151F), // Grey background
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: cleanCues.map((cleanCue) {
                return Text(
                  cleanCue,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14.0, // Small text
                    fontWeight: FontWeight.bold, // Bold text
                    height: 1.25,
                    letterSpacing: 0.1,
                    shadows: const [
                      Shadow(
                        color: Colors.black,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 6,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
