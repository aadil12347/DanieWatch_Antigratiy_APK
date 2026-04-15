import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../services/video_extractor_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/detail_provider.dart';
import '../providers/watch_history_provider.dart';
import '../screens/video_player/video_player_screen.dart';
import 'play_loader_overlay.dart';

/// Premium "Continue Watching" row for the home screen.
/// Shows recent watch history in a stacked carousel with "Delete Mode".
class ContinueWatchingRow extends ConsumerStatefulWidget {
  const ContinueWatchingRow({super.key});

  @override
  ConsumerState<ContinueWatchingRow> createState() => _ContinueWatchingRowState();
}

class _ContinueWatchingRowState extends ConsumerState<ContinueWatchingRow> with SingleTickerProviderStateMixin {
  late List<int> _positions;
  List<WatchHistoryItem>? _cachedItems;
  int _activeIndex = 0;
  bool _isDeleteMode = false;
  
  // For wiggle animation
  late AnimationController _wiggleController;

  @override
  void initState() {
    super.initState();
    _wiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _wiggleController.dispose();
    super.dispose();
  }

  void _updatePositions(int itemCount) {
    if (itemCount == 0) {
      _positions = [];
      return;
    }
    // Logic for 5 slots, cycling if we have more
    final displayCount = itemCount > 5 ? 5 : itemCount;
    final maxDist = displayCount ~/ 2;
    _positions = List.generate(itemCount, (index) => index - maxDist);
    _updateActiveIndex();
  }

  void _updateActiveIndex() {
    _activeIndex = _positions.indexOf(0);
  }

  void _step(int direction, int itemCount) {
    if (itemCount <= 1) return;
    setState(() {
      for (int i = 0; i < _positions.length; i++) {
        int current = _positions[i];
        int nextPos = current + direction;
        
        // Wrap logic: -2 to 2 for 5 items. 
        // If more than 5, we still cycle them through the -2 to 2 range.
        int range = (itemCount > 5) ? 2 : (itemCount ~/ 2);
        
        if (nextPos > range) nextPos = -range;
        if (nextPos < -range) nextPos = range;
        
        _positions[i] = nextPos;
      }
      _updateActiveIndex();
    });
  }

  void _enterDeleteMode() {
    setState(() {
      _isDeleteMode = true;
      _wiggleController.repeat(reverse: true);
    });
  }

  void _exitDeleteMode() {
    setState(() {
      _isDeleteMode = false;
      _wiggleController.stop();
      _wiggleController.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(watchHistoryProvider);
    final items = history.where((e) => !e.isFinished).take(10).toList();
    
    if (items.isEmpty) return const SizedBox.shrink();

    // Initialize/Update positions if items changed
    if (_cachedItems == null || _cachedItems!.length != items.length) {
      _updatePositions(items.length);
      _cachedItems = items;
    } else {
      // Check if item IDs changed
      bool changed = false;
      for(int i=0; i<items.length; i++) {
        if (items[i].uniqueKey != _cachedItems![i].uniqueKey) {
          changed = true;
          break;
        }
      }
      if (changed) {
        _updatePositions(items.length);
        _cachedItems = items;
      }
    }

    final r = Responsive(context);
    final carouselHeight = r.h(280).clamp(220.0, 360.0);

    return PopScope(
      canPop: !_isDeleteMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isDeleteMode) {
          _exitDeleteMode();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_isDeleteMode) _exitDeleteMode();
        },
        child: Column(
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
                    color: _isDeleteMode 
                        ? Colors.red.withValues(alpha: 0.15)
                        : AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _isDeleteMode ? Icons.delete_sweep_rounded : Icons.play_circle_rounded,
                    color: _isDeleteMode ? Colors.redAccent : AppColors.primary,
                    size: r.f(18).clamp(14.0, 24.0),
                  ),
                ),
                SizedBox(width: r.w(10)),
                Text(
                  _isDeleteMode ? 'Delete Mode' : 'Continue Watching',
                  style: GoogleFonts.lora(
                    color: AppColors.textPrimary,
                    fontSize: r.f(22).clamp(16.0, 28.0),
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
                if (_isDeleteMode) ...[
                  const Spacer(),
                  TextButton(
                    onPressed: _exitDeleteMode,
                    child: Text('Done', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),
          
          // Carousel
          GestureDetector(
            onHorizontalDragEnd: (details) {
              if (_isDeleteMode) return;
              if (details.primaryVelocity == null) return;
              if (details.primaryVelocity! < 0) {
                _step(-1, items.length);
              } else if (details.primaryVelocity! > 0) {
                _step(1, items.length);
              }
            },
            child: SizedBox(
              height: carouselHeight,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: List.generate(items.length, (index) {
                  final pos = _positions[index];
                  // Hide items that are too far in the stack if we have many
                  if (pos.abs() > 2) return const SizedBox.shrink();
                  
                  return _buildCarouselItem(index, pos, items[index], items.length);
                }).toList()
                  ..sort((a, b) {
                    // This is tricky because some items are SizedBox.shrink()
                    // But those won't affect the visible stack order much.
                    if (a is! AnimatedPositioned || b is! AnimatedPositioned) return 0;
                    final idxA = (a.key as ValueKey<int>).value;
                    final idxB = (b.key as ValueKey<int>).value;
                    final zA = _getZIndex(_positions[idxA]);
                    final zB = _getZIndex(_positions[idxB]);
                    return zA.compareTo(zB);
                  }),
              ),
            ),
          ),
          
          // Subtitle of active item
          if (!_isDeleteMode && _activeIndex >= 0 && _activeIndex < items.length)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  items[_activeIndex].title,
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: r.f(14).clamp(12.0, 18.0),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }

  void _resumePlayback(WatchHistoryItem item) {
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

    // Use the same play loader animation as the detail page
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

  int _getZIndex(int pos) {
    switch (pos) {
      case 0: return 5;
      case -1:
      case 1: return 4;
      case -2:
      case 2: return 3;
      default: return 0;
    }
  }

  Widget _buildCarouselItem(int index, int pos, WatchHistoryItem item, int totalCount) {
    final r = Responsive(context);
    
    double scale = 1.0;
    double translateX = 0.0;
    double opacity = 1.0;

    final double offset1 = r.w(80).clamp(60.0, 110.0);
    final double offset2 = r.w(140).clamp(100.0, 190.0);

    if (pos == 0) {
      scale = 1.0;
      translateX = 0.0;
      opacity = 1.0;
    } else if (pos == -1) {
      scale = 0.85;
      translateX = -offset1;
      opacity = 0.7;
    } else if (pos == 1) {
      scale = 0.85;
      translateX = offset1;
      opacity = 0.7;
    } else if (pos == -2) {
      scale = 0.75;
      translateX = -offset2;
      opacity = 0.4;
    } else if (pos == 2) {
      scale = 0.75;
      translateX = offset2;
      opacity = 0.4;
    }

    return AnimatedPositioned(
      key: ValueKey<int>(index),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      child: Center(
        child: Opacity(
          opacity: opacity,
          child: AnimatedTransform(
            transform: Matrix4.identity()
              ..translate(translateX, 0.0, 0.0)
              ..scale(scale, scale, 1.0),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            child: AnimatedBuilder(
              animation: _wiggleController,
              builder: (context, child) {
                double rotation = 0.0;
                if (_isDeleteMode) {
                  rotation = (_wiggleController.value - 0.5) * 0.03;
                }
                return Transform.rotate(
                  angle: rotation,
                  child: child,
                );
              },
              child: _ContinueWatchingCard(
                item: item,
                index: index,
                isDeleteMode: _isDeleteMode,
                onDelete: () {
                  ref.read(watchHistoryProvider.notifier).removeItem(
                    item.tmdbId, 
                    season: item.season, 
                    episode: item.episode
                  );
                },
                onLongPress: _enterDeleteMode,
                onTap: () {
                  if (_isDeleteMode) {
                    _exitDeleteMode();
                  } else {
                    final currentPos = _positions[index];
                    if (currentPos == 0) {
                      _resumePlayback(item);
                    } else if (currentPos < 0) {
                      _step(1, totalCount);
                    } else {
                      _step(-1, totalCount);
                    }
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueWatchingCard extends ConsumerWidget {
  final WatchHistoryItem item;
  final int index;
  final bool isDeleteMode;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;
  final VoidCallback onTap;

  const _ContinueWatchingCard({
    required this.item, 
    required this.index,
    required this.isDeleteMode,
    required this.onDelete,
    required this.onLongPress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = Responsive(context);
    final cardWidth = r.w(180).clamp(140.0, 240.0);
    final cardHeight = r.h(250).clamp(180.0, 320.0);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF1A1A1A),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Thumbnail
              _buildThumbnail(),

              // 2. Premium Gradient 
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.2),
                        Colors.black.withValues(alpha: 0.9),
                      ],
                      stops: const [0.4, 0.7, 1.0],
                    ),
                  ),
                ),
              ),

              // 3. Info overlay
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
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: r.f(12).clamp(10.0, 15.0),
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    if (item.mediaType != 'movie' && item.season != null && item.episode != null)
                      Text(
                        'S${item.season.toString().padLeft(2, '0')} E${item.episode.toString().padLeft(2, '0')}',
                        style: GoogleFonts.inter(
                          color: AppColors.primary,
                          fontSize: r.f(10).clamp(8.0, 12.0),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(height: 6),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 4,
                        child: LinearProgressIndicator(
                          value: item.progress,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 4. Delete Icon (Visible in Delete Mode)
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
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                        ],
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),

              // 5. Play Button (Only if not in delete mode and central)
              if (!isDeleteMode)
                 Center(
                   child: AnimatedOpacity(
                     opacity: 0.8,
                     duration: const Duration(milliseconds: 200),
                     child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.9),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
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
    String? imageUrl;
    if (item.mediaType == 'movie') {
      imageUrl = item.posterUrl ?? item.backdropUrl ?? item.thumbnailUrl;
    } else {
      imageUrl = item.thumbnailUrl ?? item.posterUrl ?? item.backdropUrl;
    }

    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        color: const Color(0xFF222222),
        child: Center(
          child: Icon(Icons.movie_rounded, color: Colors.white.withValues(alpha: 0.1), size: 40),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: const Color(0xFF222222)),
      errorWidget: (_, __, ___) => Container(
        color: const Color(0xFF222222),
        child: const Center(child: Icon(Icons.broken_image_rounded, color: Colors.white24, size: 30)),
      ),
    );
  }
}

class AnimatedTransform extends ImplicitlyAnimatedWidget {
  final Widget child;
  final Matrix4 transform;

  const AnimatedTransform({
    super.key,
    required this.child,
    required this.transform,
    super.duration = const Duration(milliseconds: 300),
    super.curve = Curves.linear,
  });

  @override
  AnimatedWidgetBaseState<AnimatedTransform> createState() => _AnimatedTransformState();
}

class _AnimatedTransformState extends AnimatedWidgetBaseState<AnimatedTransform> {
  Matrix4Tween? _transformTween;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _transformTween = visitor(
      _transformTween,
      widget.transform,
      (dynamic value) => Matrix4Tween(begin: value as Matrix4),
    ) as Matrix4Tween?;
  }

  @override
  Widget build(BuildContext context) {
    return Transform(
      transform: _transformTween?.evaluate(animation) ?? widget.transform,
      alignment: Alignment.center,
      child: widget.child,
    );
  }
}
