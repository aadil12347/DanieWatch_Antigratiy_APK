import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models/manifest_item.dart';
import '../providers/watchlist_provider.dart';
import '../providers/active_card_provider.dart';

/// Movie/TV poster card — used in grids and horizontal rows.
class MovieCard extends ConsumerStatefulWidget {
  final ManifestItem item;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  const MovieCard({
    super.key,
    required this.item,
    this.width,
    this.height,
    this.onTap,
  });

  @override
  ConsumerState<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends ConsumerState<MovieCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverController;
  late Animation<double> _slideAnimation;

  String get _cardKey => '${widget.item.mediaType}_${widget.item.id}';

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _hoverController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  void _activateHover() {
    ref.read(activeCardProvider.notifier).state = _cardKey;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final posterUrl = item.posterUrl ?? '';
    final logoUrl = item.logoUrl;

    final activeKey = ref.watch(activeCardProvider);
    final isActive = activeKey == _cardKey;

    if (isActive && !_hoverController.isCompleted) {
      _hoverController.forward();
    } else if (!isActive && _hoverController.value > 0) {
      _hoverController.reverse();
    }

    final watchlistAsync = ref.watch(watchlistProvider);
    final isInWatchlist = watchlistAsync.maybeWhen(
      data: (items) => items
          .any((w) => w.tmdbId == item.id && w.mediaType == item.mediaType),
      orElse: () => false,
    );

    return GestureDetector(
      onTap: widget.onTap ??
          () => context.push('/details/${item.mediaType}/${item.id}'),
      onLongPress: () => _activateHover(),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildCardContent(
          item: item,
          posterUrl: posterUrl,
          logoUrl: logoUrl,
          isInWatchlist: isInWatchlist,
          isHovering: isActive,
          hoverAnimation: _hoverController,
        ),
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
    // Determine the rating to display, optionally capped to 10
    final rating =
        item.voteAverage > 0 ? item.voteAverage.toStringAsFixed(1) : 'NR';

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Base Poster ──
        if (posterUrl.isNotEmpty)
          AnimatedBuilder(
            animation: hoverAnimation ?? const AlwaysStoppedAnimation(0),
            builder: (context, _) {
              final showHover = hoverAnimation != null &&
                  hoverAnimation.value > 0.5 &&
                  item.hoverImageUrl != null &&
                  item.hoverImageUrl!.isNotEmpty;

              return CachedNetworkImage(
                imageUrl: showHover ? item.hoverImageUrl! : posterUrl,
                fit: BoxFit.cover,
                memCacheWidth: 300,
                placeholder: (_, __) => _placeholder(),
                errorWidget: (_, __, ___) => _placeholder(error: true),
                fadeOutDuration: const Duration(milliseconds: 200),
                fadeInDuration: const Duration(milliseconds: 200),
              );
            },
          )
        else
          _placeholder(),

        // ── Hover Overlay — logo only ──
        if (hoverAnimation != null)
          AnimatedBuilder(
            animation: hoverAnimation,
            builder: (context, _) {
              if (hoverAnimation.value == 0.0) return const SizedBox.shrink();
              final slideOff = (1.0 - hoverAnimation.value) * 120;

              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black
                                .withValues(alpha: 0.9 * hoverAnimation.value),
                            Colors.black
                                .withValues(alpha: 0.4 * hoverAnimation.value),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -slideOff + 16,
                    left: 8,
                    right: 8,
                    child: Opacity(
                      opacity: hoverAnimation.value,
                      child: (logoUrl != null && logoUrl.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: logoUrl,
                              height: 36,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) =>
                                  _titleText(item.title),
                            )
                          : _titleText(item.title),
                    ),
                  ),
                ],
              );
            },
          ),

        // ── Rating badge (top-left) ──
        if (item.voteAverage > 0)
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(10),
                ),
              ),
              child: Text(
                rating,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _titleText(String title) {
    return Text(
      title,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
    );
  }

  Widget _placeholder({bool error = false}) {
    return Container(
      color: AppColors.surfaceElevated,
      child: Center(
        child: Icon(
          error ? Icons.broken_image_outlined : Icons.movie_outlined,
          color: AppColors.textMuted,
          size: 24,
        ),
      ),
    );
  }
}
