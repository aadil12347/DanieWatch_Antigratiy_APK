import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../providers/detail_provider.dart';
import '../providers/watch_history_provider.dart';
import '../screens/video_player/video_player_screen.dart';

/// Premium "Continue Watching" row for the home screen.
/// Shows recent watch history with progress bars and thumbnails.
class ContinueWatchingRow extends ConsumerWidget {
  const ContinueWatchingRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(watchHistoryProvider);
    // Filter out finished items (>95%)
    final items = history.where((e) => !e.isFinished).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    final r = Responsive(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: EdgeInsets.fromLTRB(r.w(16), r.h(28), r.w(16), r.h(12)),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(r.w(6)),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.play_circle_rounded,
                  color: AppColors.primary,
                  size: r.f(18).clamp(14.0, 24.0),
                ),
              ),
              SizedBox(width: r.w(10)),
              Text(
                'Continue Watching',
                style: GoogleFonts.lora(
                  color: AppColors.textPrimary,
                  fontSize: r.f(22).clamp(16.0, 28.0),
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        // Scrollable cards
        SizedBox(
          height: r.h(170).clamp(140.0, 220.0),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: r.w(12)),
            itemCount: items.length,
            itemBuilder: (context, index) {
              return _ContinueWatchingCard(
                item: items[index],
                index: index,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ContinueWatchingCard extends ConsumerWidget {
  final WatchHistoryItem item;
  final int index;

  const _ContinueWatchingCard({required this.item, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = Responsive(context);
    final cardWidth = r.w(260).clamp(200.0, 340.0);
    final cardHeight = r.h(150).clamp(120.0, 200.0);

    return GestureDetector(
      onTap: () => _resumePlayback(context, ref),
      child: Container(
        width: cardWidth,
        height: cardHeight,
        margin: EdgeInsets.symmetric(horizontal: r.w(4)),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF1A1A1A),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Thumbnail / poster
              _buildThumbnail(),

              // 2. Gradient overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      stops: const [0.3, 0.6, 1.0],
                    ),
                  ),
                ),
              ),

              // 3. Play button center
              Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.9),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),

              // 4. Info overlay (bottom)
              Positioned(
                left: 10,
                right: 10,
                bottom: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    Text(
                      item.title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: r.f(13).clamp(10.0, 16.0),
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // Episode info + time remaining
                    Row(
                      children: [
                        if (item.mediaType != 'movie' &&
                            item.season != null &&
                            item.episode != null)
                          Text(
                            'S${item.season.toString().padLeft(2, '0')} E${item.episode.toString().padLeft(2, '0')}',
                            style: GoogleFonts.inter(
                              color: AppColors.primary,
                              fontSize: r.f(10).clamp(8.0, 13.0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (item.mediaType != 'movie' &&
                            item.season != null &&
                            item.episode != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              '·',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 10,
                              ),
                            ),
                          ),
                        Text(
                          item.timeRemainingText,
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: r.f(10).clamp(8.0, 13.0),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 3.5,
                        child: LinearProgressIndicator(
                          value: item.progress,
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 5. Top-right badge (episode number or movie icon)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Text(
                    item.mediaType != 'movie'
                        ? 'EP ${item.episode ?? 1}'
                        : 'MOVIE',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    // Prefer backdrop (landscape) > thumbnail > poster for continue watching cards
    final imageUrl = item.backdropUrl ?? item.thumbnailUrl ?? item.posterUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        color: const Color(0xFF222222),
        child: Center(
          child: Icon(
            Icons.movie_rounded,
            color: Colors.white.withValues(alpha: 0.1),
            size: 40,
          ),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: const Color(0xFF222222)),
      errorWidget: (_, __, ___) => Container(
        color: const Color(0xFF222222),
        child: Center(
          child: Icon(
            Icons.broken_image_rounded,
            color: Colors.white.withValues(alpha: 0.1),
            size: 30,
          ),
        ),
      ),
    );
  }

  void _resumePlayback(BuildContext context, WidgetRef ref) {
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

    // Navigate to the video player with resume position
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          title: item.title,
          url: item.playUrl ?? '',
          tmdbId: item.tmdbId,
          mediaType: item.mediaType,
          season: item.season,
          episode: item.episode,
          seasons: seasons,
          startPosition: item.currentTime,
          posterUrl: item.posterUrl,
        ),
      ),
    );
  }
}
