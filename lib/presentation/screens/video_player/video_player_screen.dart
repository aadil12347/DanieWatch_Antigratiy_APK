/// Video Player Screen — Complete rewrite with Cloudstream-style architecture.
///
/// Replaces the old 5300+ line monolith with a clean, modular player:
/// - PlayerController: manages BetterPlayer lifecycle + extraction
/// - PlayerGestures: double-tap, long-press, swipe gestures
/// - PlayerOverlay: top bar, bottom bar, center controls
/// - SourceSelectorSheet: multi-source picker
/// - PlayerSettingsSheet: speed, resize, etc.
///
/// No WebView — all playback through BetterPlayer (ExoPlayer).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';

import '../../providers/watch_history_provider.dart';
import '../../providers/detail_provider.dart';
import '../../../pip/pip_controller.dart';
import '../../../services/peachify_extractor.dart';

import 'player_controller.dart';
import 'player_gestures.dart';
import 'player_overlay.dart';
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
    with WidgetsBindingObserver {
  late final PlayerController _controller;
  int? _currentSeason;
  int? _currentEpisode;
  Timer? _historyTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = PlayerController();
    _currentSeason = widget.season;
    _currentEpisode = widget.episode;

    // Set up callbacks
    _controller.onProgressUpdate = _onProgressUpdate;
    _controller.onPlaybackComplete = _onPlaybackComplete;
    _controller.onNextEpisode = (season, episode) {
      _switchToEpisode(season, episode);
    };
    _controller.onPreviousEpisode = (season, episode) {
      _switchToEpisode(season, episode);
    };

    // Initialize player
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final content = ref.read(detailProvider(
      DetailParams(tmdbId: widget.tmdbId, mediaType: widget.mediaType),
    )).valueOrNull;

    // Get total episodes for current season (for next/prev navigation)
    int totalEpisodes = 0;
    if (content != null && content.isTv && content.tmdbSeasons != null) {
      final currentSeasonData = content.tmdbSeasons!
          .where((s) => s.seasonNumber == (_currentSeason ?? 1))
          .firstOrNull;
      totalEpisodes = currentSeasonData?.episodeCount ?? 0;
    }

    await _controller.initialize(
      title: _buildTitle(),
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      imdbId: content?.imdbId,
      year: content?.releaseYear,
      season: _currentSeason,
      episode: _currentEpisode,
      directUrl: widget.isDirectLink ? widget.url : null,
      startPosition: widget.startPosition,
      seasonNumbers: content?.seasonNumbers,
      totalEpisodes: totalEpisodes,
    );

    // Start periodic history saving
    _historyTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _saveWatchProgress();
    });
  }

  String _buildTitle() {
    if (_currentSeason != null && _currentEpisode != null) {
      return '${widget.title} — S${_currentSeason.toString().padLeft(2, '0')}E${_currentEpisode.toString().padLeft(2, '0')}';
    }
    return widget.title;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveWatchProgress();
    }
  }

  void _onProgressUpdate(Duration position, Duration duration) {
    // Progress is tracked by the controller, just save periodically
  }

  void _onPlaybackComplete() {
    _saveWatchProgress();
    // Auto-play next episode if available
    if (widget.mediaType == 'tv' && _currentEpisode != null) {
      _playNextEpisode();
    }
  }

  void _playNextEpisode() {
    if (_currentEpisode == null || _currentSeason == null) return;
    _switchToEpisode(_currentSeason!, _currentEpisode! + 1);
  }

  void _playPreviousEpisode() {
    if (_currentEpisode == null || _currentSeason == null) return;
    if (_currentEpisode! <= 1) return;
    _switchToEpisode(_currentSeason!, _currentEpisode! - 1);
  }

  /// Switch to a specific episode — creates a fresh controller to avoid lifecycle issues.
  void _switchToEpisode(int season, int episode) {
    _saveWatchProgress();
    _historyTimer?.cancel();

    // Dispose old controller
    _controller.dispose();

    setState(() {
      _currentSeason = season;
      _currentEpisode = episode;
    });

    // Create fresh controller
    _controller = PlayerController();
    _controller.onProgressUpdate = _onProgressUpdate;
    _controller.onPlaybackComplete = _onPlaybackComplete;
    _controller.onNextEpisode = (s, e) => _switchToEpisode(s, e);
    _controller.onPreviousEpisode = (s, e) => _switchToEpisode(s, e);

    _initializePlayer();
  }

  void _saveWatchProgress() {
    if (_controller.position == Duration.zero ||
        _controller.duration == Duration.zero) return;

    try {
      ref.read(watchHistoryProvider.notifier).saveProgress(
            WatchHistoryItem(
              tmdbId: widget.tmdbId,
              mediaType: widget.mediaType,
              title: widget.title,
              posterUrl: widget.posterUrl,
              season: _currentSeason,
              episode: _currentEpisode,
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
  void dispose() {
    _saveWatchProgress();
    _historyTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // ── Video layer ──
              _buildVideoLayer(),

              // ── Gesture layer ──
              PlayerGestures(
                controller: _controller,
                child: const SizedBox.expand(),
              ),

              // ── Controls overlay ──
              PlayerOverlay(
                controller: _controller,
                onBack: _handleBack,
                onSourceTap: _showSourceSelector,
                onSettingsTap: _showSettings,
                onEpisodeTap: widget.mediaType == 'tv' ? _showEpisodePanel : null,
                onPipTap: _handlePip,
                showEpisodeButton: widget.mediaType == 'tv',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVideoLayer() {
    if (_controller.betterPlayerController == null) {
      return Container(
        color: Colors.black,
        child: widget.posterUrl != null
            ? Opacity(
                opacity: 0.3,
                child: Image.network(
                  widget.posterUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              )
            : const SizedBox.expand(),
      );
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: BetterPlayer(
          controller: _controller.betterPlayerController!,
        ),
      ),
    );
  }

  // ─── Actions ────────────────────────────────────────────────────────────

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

  void _showSourceSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SourceSelectorSheet(controller: _controller),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => PlayerSettingsSheet(controller: _controller),
    );
  }

  void _showEpisodePanel() {
    final content = ref.read(detailProvider(
      DetailParams(tmdbId: widget.tmdbId, mediaType: widget.mediaType),
    )).valueOrNull;

    if (content == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EpisodeSelectorPanel(
        content: content,
        currentSeason: _currentSeason ?? 1,
        currentEpisode: _currentEpisode ?? 1,
        onEpisodeSelected: (season, episode) {
          Navigator.of(context).pop(); // Close panel
          _switchToEpisode(season, episode);
        },
      ),
    );
  }
}

// ─── Episode Selector Panel ────────────────────────────────────────────────

class _EpisodeSelectorPanel extends StatefulWidget {
  final dynamic content;
  final int currentSeason;
  final int currentEpisode;
  final Function(int season, int episode) onEpisodeSelected;

  const _EpisodeSelectorPanel({
    required this.content,
    required this.currentSeason,
    required this.currentEpisode,
    required this.onEpisodeSelected,
  });

  @override
  State<_EpisodeSelectorPanel> createState() => _EpisodeSelectorPanelState();
}

class _EpisodeSelectorPanelState extends State<_EpisodeSelectorPanel> {
  late int _selectedSeason;

  @override
  void initState() {
    super.initState();
    _selectedSeason = widget.currentSeason;
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final seasonNumbers = content.seasonNumbers as List<int>? ?? [1];
    // Build a simple episode count per season (fallback to 20 episodes)
    final int episodeCount = content.isTv
        ? (content.tmdbSeasons
                ?.where((s) => s.seasonNumber == _selectedSeason)
                .firstOrNull
                ?.episodeCount ??
            20)
        : 1;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.playlist_play, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Episodes',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Season tabs
          if (seasonNumbers.length > 1)
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: seasonNumbers.length,
                itemBuilder: (_, index) {
                  final season = seasonNumbers[index];
                  final isSelected = season == _selectedSeason;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedSeason = season),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.red : Colors.white12,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        'S$season',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),

          // Episode grid
          Flexible(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.8,
              ),
              itemCount: episodeCount,
              itemBuilder: (_, index) {
                final ep = index + 1;
                final isCurrent = _selectedSeason == widget.currentSeason &&
                    ep == widget.currentEpisode;
                return GestureDetector(
                  onTap: () =>
                      widget.onEpisodeSelected(_selectedSeason, ep),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isCurrent ? Colors.red : Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                      border: isCurrent
                          ? Border.all(color: Colors.redAccent, width: 1.5)
                          : null,
                    ),
                    child: Text(
                      '$ep',
                      style: GoogleFonts.inter(
                        color: isCurrent ? Colors.white : Colors.white70,
                        fontSize: 14,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
