
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../domain/models/manifest_item.dart';
import '../providers/watchlist_provider.dart';
import '../providers/active_card_provider.dart';
import '../providers/manifest_provider.dart';

import '../../core/utils/toast_utils.dart';
import 'poster_touch_handler.dart';

/// Movie/TV poster card — used in grids and horizontal rows.
class MovieCard extends ConsumerStatefulWidget {
  final ManifestItem item;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final int? rank;

  const MovieCard({
    super.key,
    required this.item,
    this.width,
    this.height,
    this.onTap,
    this.rank,
  });

  @override
  ConsumerState<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends ConsumerState<MovieCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverController;

  String get _cardKey => '${widget.item.mediaType}_${widget.item.id}';

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 100),
    );
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  void _navigate() {
    if (widget.onTap != null) {
      widget.onTap!();
    } else {
      context.push('/details/${widget.item.mediaType}/${widget.item.id}');
    }
  }

  void _onLongHoldChanged(bool active) {
    if (active) {
      ref.read(activeCardProvider.notifier).state = _cardKey;
      _hoverController.forward();
    } else {
      ref.read(activeCardProvider.notifier).state = null;
      _hoverController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final posterUrlAsync = ref.watch(posterUrlProvider('${item.id}_${item.mediaType}'));
    final posterUrl = posterUrlAsync.valueOrNull ?? '';
    final logoUrl = item.logoUrl;

    // Selective watch: only rebuild THIS card when its active state changes
    final isActive = ref.watch(activeCardProvider.select((key) => key == _cardKey));

    // Sync hover animation with active state (for external changes)
    if (isActive && !_hoverController.isCompleted) {
      _hoverController.forward();
    } else if (!isActive && _hoverController.value > 0) {
      _hoverController.reverse();
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main card with touch handler
          Positioned.fill(
            child: PosterTouchHandler(
              onTap: _navigate,
              onLongHold: _onLongHoldChanged,
              child: _buildCardContent(
                item: item,
                posterUrl: posterUrl,
                logoUrl: logoUrl,
                isInWatchlist: false,
                isHovering: isActive,
                hoverAnimation: _hoverController,
              ),
            ),
          ),
          // Save button: positioned OUTSIDE PosterTouchHandler
          // so tapping it doesn't trigger navigation — moved to bottom-right
          Positioned(
            bottom: 6,
            right: 6,
            child: _SaveButton(item: item),
          ),
        ],
      ),
    );
  }

  Widget _buildCardContent({
    required ManifestItem item,
    required String posterUrl,
    required String? logoUrl,
    required bool isInWatchlist,
    required bool isHovering,
    AnimationController? hoverAnimation,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Poster Area ──
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Rank Number (Optional)
              if (widget.rank != null)
                Positioned(
                  left: -32,
                  bottom: -15,
                  child: _RankNumber(rank: widget.rank!),
                ),

              // 2. Main Poster Stack (Image + Overlays)
              Positioned.fill(
                child: RepaintBoundary(child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.04),
                          width: 0.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 2.0,
                            offset: const Offset(0, 1.0),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Base Poster
                      _PosterImage(
                        itemId: item.id.toString(),
                        mediaType: item.mediaType,
                        initialPosterUrl: item.posterUrl,
                      ),

                      // Language Badge (top-left)
                      if (item.displayLanguage.isNotEmpty)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: _LanguageBadge(text: item.displayLanguage),
                        ),

                      // Season & Episode Added Badge (bottom-left)
                      if (item.seasonDetail != null && item.seasonDetail!.isNotEmpty)
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: _SeasonBadge(text: item.seasonDetail!),
                        ),
                    ],
                  ),
                ),
              )),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // ── Text Labels (Outside Poster) ──
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.cleanTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  _MovieYearWidget(item: item),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('•',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 10)),
                  ),
                  Text(
                    item.mediaType == 'tv' ? 'Series' : 'Movie',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _MovieYearWidget extends ConsumerWidget {
  final ManifestItem item;
  const _MovieYearWidget({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final direct = item.displayYear ?? item.releaseYear;
    if (direct != null && direct > 0) {
      return Text(
        '$direct',
        style: GoogleFonts.inter(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final key = '${item.id}___${item.mediaType}___${item.cleanTitle}';
    final yearAsync = ref.watch(releaseYearProvider(key));

    return yearAsync.maybeWhen(
      data: (yr) {
        if (yr != null && yr > 0) {
          return Text(
            '$yr',
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          );
        }
        return const SizedBox.shrink();
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}


class _SaveButton extends ConsumerStatefulWidget {
  final ManifestItem item;
  const _SaveButton({required this.item});

  @override
  ConsumerState<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends ConsumerState<_SaveButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.25), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 0.95), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 25),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final watchlistAsync = ref.watch(watchlistProvider);
    final isInWatchlist = watchlistAsync.maybeWhen(
      data: (items) => items.any((w) =>
          w.tmdbId == widget.item.id && w.mediaType == widget.item.mediaType),
      orElse: () => false,
    );

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _controller.forward(from: 0.0);
          HapticFeedback.lightImpact();
          
          final effectiveDate = widget.item.releaseDate ??
              (widget.item.displayYear ?? widget.item.releaseYear)?.toString();
          ref.read(watchlistProvider.notifier).toggle(
                tmdbId: widget.item.id,
                mediaType: widget.item.mediaType,
                title: widget.item.title,
                posterPath: widget.item.posterUrl,
                releaseDate: effectiveDate,
                voteAverage: widget.item.voteAverage,
              );

          CustomToast.show(
            context,
            isInWatchlist ? 'Removed from watchlist' : 'Added to watchlist',
            type: isInWatchlist ? ToastType.info : ToastType.success,
            icon: isInWatchlist
                ? Icons.bookmark_remove_rounded
                : Icons.bookmark_added_rounded,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
            border: Border.all(
              color: isInWatchlist ? AppColors.primary : Colors.white24,
              width: 1,
            ),
          ),
          child: Icon(
            isInWatchlist ? Icons.bookmark : Icons.bookmark_outline,
            size: 18,
            color: isInWatchlist ? AppColors.primary : Colors.white,
          ),
        ),
      ),
    );
  }
}

class LanguageBadge extends StatelessWidget {
  final String text;
  const LanguageBadge({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxWidth: 85),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
          height: 1.2,
        ),
      ),
    );
  }
}

class SeasonBadge extends StatelessWidget {
  final String text;
  const SeasonBadge({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFF6D00),
            Color(0xFFE65100),
          ],
        ),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66FF6D00),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
          height: 1.2,
        ),
      ),
    );
  }
}

typedef _LanguageBadge = LanguageBadge;
typedef _SeasonBadge = SeasonBadge;

/// Poster image with automatic TMDB fallback for unsupported formats (.avif etc).
/// Poster image with automatic TMDB/OMDb fallback and caching.
class _PosterImage extends ConsumerWidget {
  final String itemId;
  final String mediaType;
  final String? initialPosterUrl;

  const _PosterImage({
    required this.itemId,
    required this.mediaType,
    this.initialPosterUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initialPosterUrl != null && initialPosterUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: initialPosterUrl!,
        fit: BoxFit.cover,
        memCacheWidth: 300,
        memCacheHeight: 450,
        maxWidthDiskCache: 450,
        maxHeightDiskCache: 675,
        placeholder: (_, __) => Container(
          color: AppColors.surfaceElevated,
          child: const Center(
            child: Icon(Icons.movie_outlined, color: AppColors.textMuted, size: 24),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: AppColors.surfaceElevated,
          child: const Center(
            child: Icon(Icons.movie_outlined, color: AppColors.textMuted, size: 24),
          ),
        ),
        fadeOutDuration: Duration.zero,
        fadeInDuration: const Duration(milliseconds: 150),
      );
    }

    final posterAsync = ref.watch(posterUrlProvider('${itemId}_$mediaType'));

    return posterAsync.when(
      data: (url) {
        if (url == null || url.isEmpty) {
          return Container(
            color: AppColors.surfaceElevated,
            child: const Center(
              child: Icon(Icons.movie_outlined, color: AppColors.textMuted, size: 24),
            ),
          );
        }

        return CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          memCacheWidth: 300,
          memCacheHeight: 450,
          maxWidthDiskCache: 450,
          maxHeightDiskCache: 675,
          placeholder: (_, __) => Container(
            color: AppColors.surfaceElevated,
            child: const Center(
              child: Icon(Icons.movie_outlined, color: AppColors.textMuted, size: 24),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            color: AppColors.surfaceElevated,
            child: const Center(
              child: Icon(Icons.movie_outlined, color: AppColors.textMuted, size: 24),
            ),
          ),
          fadeOutDuration: Duration.zero,
          fadeInDuration: const Duration(milliseconds: 150),
        );
      },
      loading: () => Container(
        color: AppColors.surfaceElevated,
        child: const Center(
          child: Icon(Icons.movie_outlined, color: AppColors.textMuted, size: 24),
        ),
      ),
      error: (_, __) => Container(
        color: AppColors.surfaceElevated,
        child: const Center(
          child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 24),
        ),
      ),
    );
  }
}

class _RankNumber extends StatelessWidget {
  final int rank;
  const _RankNumber({required this.rank});

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);
    // Premium font for the rank number
    final textStyle = GoogleFonts.inter(
      fontSize: r.f(90).clamp(60.0, 120.0),
      fontWeight: FontWeight.w900,
      letterSpacing: -4,
      height: 1,
    );

    return Stack(
      children: [
        // Outline
        Text(
          rank.toString(),
          style: textStyle.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.0
              ..color = AppColors.primary.withValues(alpha: 0.9),
          ),
        ),
        // Darkened fill
        Text(
          rank.toString(),
          style: textStyle.copyWith(
            color: Colors.black.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }
}
