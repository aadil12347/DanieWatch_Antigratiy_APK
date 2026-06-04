import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/watch_history_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../widgets/play_loader_overlay.dart';
import '../../services/video_extractor_service.dart';
import '../screens/video_player/video_player_screen.dart';
import '../providers/detail_provider.dart';
import '../providers/delete_mode_provider.dart';

class ContinueWatchingRow extends ConsumerStatefulWidget {
  const ContinueWatchingRow({super.key});

  @override
  ConsumerState<ContinueWatchingRow> createState() => _ContinueWatchingRowState();
}

class _ContinueWatchingRowState extends ConsumerState<ContinueWatchingRow> {
  void _resumePlayback(BuildContext context, WatchHistoryItem item) {
    // Look up seasons data for episode picker in player
    List<int>? seasons;
    try {
      final detailAsync = ref.read(
        detailProvider(
          DetailParams(tmdbId: item.tmdbId, mediaType: item.mediaType),
        ),
      );
      seasons = detailAsync.valueOrNull?.seasonNumbers;
    } catch (_) {}

    showPlayLoader<Map<String, String>>(
      context: context,
      fetchLinkFuture: () async {
        if (item.mediaType == 'offline') {
          return {'extracted': item.playUrl ?? '', 'original': item.playUrl ?? ''};
        }

        String originalLink = '';

        // Prioritize original iframe link if valid
        if (item.playUrl != null &&
            item.playUrl!.isNotEmpty &&
            !item.playUrl!.contains('.m3u8') &&
            !item.playUrl!.contains('.mp4')) {
          originalLink = item.playUrl!;
        } else {
          // Fallback if we only have the extracted link in db
          try {
            if (item.mediaType == 'movie') {
              final detailAsync = await ref.read(
                detailProvider(
                  DetailParams(tmdbId: item.tmdbId, mediaType: item.mediaType),
                ).future,
              );
              originalLink = detailAsync?.watchLink ?? '';
            } else {
              final episodesAsync = await ref.read(
                episodesProvider(
                  EpisodeParams(tmdbId: item.tmdbId, seasonNumber: item.season ?? 1),
                ).future,
              );
              final ep = episodesAsync.firstWhere(
                (e) => e.episodeNumber == item.episode,
                orElse: () => episodesAsync.first,
              );
              originalLink = ep.playLink ?? '';
            }
          } catch (_) {
            return null;
          }
        }

        if (originalLink.isEmpty) return null;

        try {
          final extractor = VideoExtractorService();
          String? m3u8Url =
              await extractor.extractVideoUrl(originalLink, bypassCache: true);

          if (m3u8Url == null || m3u8Url.isEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('extract_$originalLink');
            m3u8Url = await extractor.extractVideoUrl(originalLink, bypassCache: true);
          }
          if (m3u8Url != null && m3u8Url.isNotEmpty) {
            return {'extracted': m3u8Url, 'original': originalLink};
          }
          return null;
        } catch (e) {
          return null;
        }
      },
      onSuccess: (data) {
        if (!context.mounted) return;
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              title: item.title,
              url: data['extracted'] ?? '',
              originalUrl: data['original'],
              tmdbId: item.tmdbId,
              mediaType: item.mediaType,
              season: item.season,
              episode: item.episode,
              seasons: seasons,
              startPosition: item.currentTime,
              posterUrl: item.posterUrl,
              isOffline: item.mediaType == 'offline',
              isDirectLink: item.mediaType != 'offline',
            ),
          ),
        );
      },
      onError: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load video'),
            backgroundColor: Colors.red,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(watchHistoryProvider);
    if (history.isEmpty) return const SizedBox.shrink();

    // Limit to 10 posts as requested
    final items = history.take(10).toList();
    final isDeleteMode = ref.watch(continueWatchingDeleteModeProvider);
    final r = Responsive(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: r.w(20)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Continue Watching',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: r.f(20).clamp(18.0, 24.0),
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
              ),
              if (isDeleteMode)
                TextButton(
                  onPressed: () => ref.read(continueWatchingDeleteModeProvider.notifier).state = false,
                  child: Text(
                    'Done',
                    style: GoogleFonts.inter(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: r.h(160).clamp(140.0, 200.0),
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: r.w(20)),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final item = items[index];
              return _ContinueWatchingCard(
                item: item,
                isDeleteMode: isDeleteMode,
                onDelete: () {
                  ref.read(watchHistoryProvider.notifier).removeItem(
                    item.tmdbId,
                    season: item.season,
                    episode: item.episode,
                  );
                },
                onLongPress: () {
                  ref.read(continueWatchingDeleteModeProvider.notifier).state = true;
                },
                onTap: () {
                  if (isDeleteMode) {
                    ref.read(continueWatchingDeleteModeProvider.notifier).state = false;
                  } else {
                    _resumePlayback(context, item);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ContinueWatchingCard extends StatefulWidget {
  final WatchHistoryItem item;
  final bool isDeleteMode;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;
  final VoidCallback onTap;

  const _ContinueWatchingCard({
    required this.item,
    required this.isDeleteMode,
    required this.onDelete,
    required this.onLongPress,
    required this.onTap,
  });

  @override
  State<_ContinueWatchingCard> createState() => _ContinueWatchingCardState();
}

class _ContinueWatchingCardState extends State<_ContinueWatchingCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _wiggleController;
  late Animation<double> _wiggleAnimation;

  @override
  void initState() {
    super.initState();
    _wiggleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _wiggleAnimation = Tween<double>(
      begin: -0.012, // ~ -0.7 degrees
      end: 0.012,   // ~ +0.7 degrees
    ).animate(CurvedAnimation(
      parent: _wiggleController,
      curve: Curves.easeInOut,
    ));

    if (widget.isDeleteMode) {
      _wiggleController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_ContinueWatchingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDeleteMode && !oldWidget.isDeleteMode) {
      _wiggleController.repeat(reverse: true);
    } else if (!widget.isDeleteMode && oldWidget.isDeleteMode) {
      _wiggleController.stop();
      _wiggleController.reset();
    }
  }

  @override
  void dispose() {
    _wiggleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isDeleteMode = widget.isDeleteMode;
    final onDelete = widget.onDelete;
    final onLongPress = widget.onLongPress;
    final onTap = widget.onTap;

    final r = Responsive(context);
    final width = r.w(240).clamp(200.0, 300.0);

    return AnimatedBuilder(
      animation: _wiggleAnimation,
      builder: (context, child) {
        return Transform.rotate(
          angle: isDeleteMode ? _wiggleAnimation.value : 0,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
              // 1. Thumbnail
              _buildThumbnail(),

              // 2. Premium Gradient Overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.1),
                        Colors.black.withValues(alpha: 0.4),
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      stops: const [0.0, 0.4, 0.6, 1.0],
                    ),
                  ),
                ),
              ),

              // 3. Info Content
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (item.mediaType != 'movie')
                          Text(
                            'S${item.season} E${item.episode}',
                            style: GoogleFonts.inter(
                              color: AppColors.primary.withValues(alpha: 0.9),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (item.mediaType != 'movie')
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Text('·', style: TextStyle(color: Colors.white30)),
                          ),
                        Text(
                          item.timeWatchedText,
                          style: GoogleFonts.inter(
                            color: Colors.white60,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 3,
                        child: LinearProgressIndicator(
                          value: item.progress,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 4. Play Button Overlay
              if (!isDeleteMode)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                  ),
                ),

              // 5. Delete Action
              if (isDeleteMode)
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                ),

              // 6. Media Type Badge
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.mediaType.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildThumbnail() {
    final item = widget.item;
    String? imageUrl;

    if (item.mediaType == 'movie') {
      // Movie: Backdrop -> Poster
      imageUrl = item.backdropUrl ?? item.posterUrl;
    } else {
      // Series: Episode Thumbnail -> Backdrop -> Season Poster (stored in posterUrl)
      imageUrl = item.thumbnailUrl ?? item.backdropUrl ?? item.posterUrl;
    }
    
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        color: const Color(0xFF1A1A1A),
        child: const Center(
          child: Icon(Icons.movie_filter_rounded, color: Colors.white12, size: 40),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: const Color(0xFF1A1A1A)),
      errorWidget: (_, __, ___) => Container(
        color: const Color(0xFF1A1A1A),
        child: const Icon(Icons.broken_image_rounded, color: Colors.white12),
      ),
    );
  }
}
