
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../data/clients/tmdb_client.dart';
import '../../domain/models/manifest_item.dart';
import '../providers/watchlist_provider.dart';
import '../providers/active_card_provider.dart';
import '../../core/utils/toast_utils.dart';

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
  late AnimationController _pinchController;
  late Animation<double> _pinchAnimation;

  String get _cardKey => '${widget.item.mediaType}_${widget.item.id}';

  @override
  void initState() {
    super.initState();
    _pinchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 100),
    );
    _pinchAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pinchController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _pinchController.dispose();
    super.dispose();
  }

  void _activateHover() {
    ref.read(activeCardProvider.notifier).state = _cardKey;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final posterUrl = item.effectivePosterUrl ?? '';
    final logoUrl = item.logoUrl;

    final activeKey = ref.watch(activeCardProvider);
    final isActive = activeKey == _cardKey;

    // Drive the pinch from active state
    if (isActive && !_pinchController.isCompleted) {
      _pinchController.forward();
    } else if (!isActive && _pinchController.value > 0) {
      _pinchController.reverse();
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
      child: AnimatedBuilder(
        animation: _pinchAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pinchAnimation.value,
            child: child,
          );
        },
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: _buildCardContent(
            item: item,
            posterUrl: posterUrl,
            logoUrl: logoUrl,
            isInWatchlist: isInWatchlist,
            isHovering: isActive,
            hoverAnimation: _pinchController,
          ),
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
                child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 12.0,
                            offset: const Offset(0, 6.0),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Base Poster
                      if (posterUrl.isNotEmpty)
                        _PosterImage(
                          posterUrl: posterUrl,
                          tmdbId: item.id,
                          mediaType: item.mediaType,
                        )
                      else
                        _placeholder(),

                      // Hover Overlay (simple darken)
                      if (hoverAnimation != null)
                        AnimatedBuilder(
                          animation: hoverAnimation,
                          builder: (context, _) {
                            if (hoverAnimation.value == 0.0) {
                              return const SizedBox.shrink();
                            }
                            return Positioned.fill(
                              child: ColoredBox(
                                color: Colors.black.withValues(alpha: 0.5 * hoverAnimation.value),
                              ),
                            );
                          },
                        ),

                      // Save Button (top-right)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: AnimatedBuilder(
                          animation: hoverAnimation ?? const AlwaysStoppedAnimation(0),
                          builder: (context, child) {
                            final opacity = 1.0 - (hoverAnimation?.value ?? 0.0);
                            return Opacity(
                              opacity: opacity,
                              child: child,
                            );
                          },
                          child: _SaveButton(item: item),
                        ),
                      ),

                      // Language Badge (top-left)
                      if (item.language.isNotEmpty)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: AnimatedBuilder(
                            animation: hoverAnimation ?? const AlwaysStoppedAnimation(0),
                            builder: (context, child) {
                              final opacity = 1.0 - (hoverAnimation?.value ?? 0.0);
                              return Opacity(
                                opacity: opacity,
                                child: child,
                              );
                            },
                            child: _LanguageBadge(text: item.language.first),
                          ),
                        ),

                      // Logo/Title Overlay
                      if (hoverAnimation != null)
                        AnimatedBuilder(
                          animation: hoverAnimation,
                          builder: (context, _) {
                            if (hoverAnimation.value == 0.0) {
                              return const SizedBox.shrink();
                            }
                            final slideOff = (1.0 - hoverAnimation.value) * 120;

                            return Positioned(
                              bottom: -slideOff + 24,
                              left: 12,
                              right: 12,
                              child: Opacity(
                                opacity: hoverAnimation.value,
                                child: (logoUrl != null && logoUrl.isNotEmpty)
                                    ? CachedNetworkImage(
                                        imageUrl: logoUrl,
                                        height: 50,
                                        fit: BoxFit.contain,
                                        errorWidget: (_, __, ___) =>
                                            _titleOverlayText(item.title),
                                      )
                                    : _titleOverlayText(item.title),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
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
                item.title,
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
                  Text(
                    item.releaseYear?.toString() ?? 'N/A',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
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

  Widget _titleOverlayText(String title) {
    return Text(
      title,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.lora(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.1,
        letterSpacing: -0.5,
        shadows: [
          Shadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 4)),
        ],
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
        onTap: () {
          _controller.forward(from: 0.0);
          HapticFeedback.lightImpact();
          
          ref.read(watchlistProvider.notifier).toggle(
                tmdbId: widget.item.id,
                mediaType: widget.item.mediaType,
                title: widget.item.title,
                posterPath: widget.item.posterUrl,
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

class _LanguageBadge extends StatelessWidget {
  final String text;
  const _LanguageBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Poster image with automatic TMDB fallback for unsupported formats (.avif etc).
class _PosterImage extends StatefulWidget {
  final String posterUrl;
  final int tmdbId;
  final String mediaType;

  const _PosterImage({
    required this.posterUrl,
    required this.tmdbId,
    required this.mediaType,
  });

  @override
  State<_PosterImage> createState() => _PosterImageState();
}

class _PosterImageState extends State<_PosterImage> {
  String? _fallbackUrl;
  bool _primaryFailed = false;

  @override
  void initState() {
    super.initState();
    // Proactively skip .avif URLs since Flutter can't render them well
    if (widget.posterUrl.toLowerCase().endsWith('.avif')) {
      _primaryFailed = true;
      _fetchTmdbPoster();
    }
  }

  void _onPrimaryError() {
    if (_primaryFailed) return;
    _primaryFailed = true;
    _fetchTmdbPoster();
  }

  Future<void> _fetchTmdbPoster() async {
    try {
      final isTv = widget.mediaType == 'tv' || widget.mediaType == 'series';
      final details = isTv
          ? await TmdbClient.instance.getTvDetails(widget.tmdbId)
          : await TmdbClient.instance.getMovieDetails(widget.tmdbId);
      final posterPath = details?['poster_path']?.toString();
      if (posterPath != null && posterPath.isNotEmpty && mounted) {
        setState(() {
          _fallbackUrl = TmdbClient.posterUrl(posterPath);
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final url = _primaryFailed ? _fallbackUrl : widget.posterUrl;

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
      placeholder: (_, __) => Container(
        color: AppColors.surfaceElevated,
        child: const Center(
          child: Icon(Icons.movie_outlined, color: AppColors.textMuted, size: 24),
        ),
      ),
      errorWidget: (_, __, ___) {
        if (!_primaryFailed) {
          // Primary URL failed → trigger TMDB fallback
          WidgetsBinding.instance.addPostFrameCallback((_) => _onPrimaryError());
        }
        return Container(
          color: AppColors.surfaceElevated,
          child: const Center(
            child: Icon(Icons.movie_outlined, color: AppColors.textMuted, size: 24),
          ),
        );
      },
      fadeOutDuration: const Duration(milliseconds: 200),
      fadeInDuration: const Duration(milliseconds: 200),
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

