import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
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

  String get _cardKey => '${widget.item.mediaType}_${widget.item.id}';

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
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
    final posterUrl = item.effectivePosterUrl ?? '';
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
      child: Transform(
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateX(0.01)
          ..rotateY(0.01),
        alignment: Alignment.center,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16), // Slightly reduced for better fit
            color: AppColors.card,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Poster Area ──
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Base Poster ──
              if (posterUrl.isNotEmpty)
                _PosterImage(posterUrl: posterUrl, tmdbId: item.id, mediaType: item.mediaType)
              else
                _placeholder(),

              // ── Hover Overlay (Vignette) ──
              if (hoverAnimation != null)
                AnimatedBuilder(
                  animation: hoverAnimation,
                  builder: (context, _) {
                    if (hoverAnimation.value == 0.0) return const SizedBox.shrink();

                    return Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.center,
                            radius: 0.8,
                            colors: [
                              Colors.black.withValues(alpha: 0.2 * hoverAnimation.value),
                              Colors.black.withValues(alpha: 0.85 * hoverAnimation.value),
                            ],
                            stops: const [0.2, 1.0],
                          ),
                        ),
                      ),
                    );
                  },
                ),

              // ── Save Button (top-right) ──
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
              
              // ── Language Badge (top-left) ──
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

              // ── Logo/Title Overlay (Top-most layer during hold) ──
              if (hoverAnimation != null)
                AnimatedBuilder(
                  animation: hoverAnimation,
                  builder: (context, _) {
                    if (hoverAnimation.value == 0.0) return const SizedBox.shrink();
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
                                errorWidget: (_, __, ___) => _titleText(item.title),
                              )
                            : _titleText(item.title),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),

        // ── Metadata Bar ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: AppColors.card,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item.mediaType == 'tv' ? 'Series' : 'Movie',
                style: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                item.releaseYear?.toString() ?? '',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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

class _GlassTag extends StatelessWidget {
  final String text;
  const _GlassTag({required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 0.5,
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
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
        vsync: this, duration: const Duration(milliseconds: 600));
    
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

