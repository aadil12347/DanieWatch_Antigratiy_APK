import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../domain/models/manifest_item.dart';
import '../providers/detail_provider.dart';

class StackedCarousel extends ConsumerStatefulWidget {
  final List<ManifestItem> items;
  const StackedCarousel({super.key, required this.items});

  @override
  ConsumerState<StackedCarousel> createState() => _StackedCarouselState();
}

class _StackedCarouselState extends ConsumerState<StackedCarousel> {
  late List<int> _positions;
  late List<ManifestItem> _displayItems;
  int _activeIndex = 0;
  Timer? _autoPlayTimer;

  @override
  void initState() {
    super.initState();
    _displayItems = widget.items.take(5).toList();
    // Center items around 0 based on count
    final maxDist = _displayItems.length ~/ 2;
    _positions = List.generate(_displayItems.length, (index) => index - maxDist);
    _updateActiveIndex();
    _startAutoPlay();
  }

  @override
  void didUpdateWidget(StackedCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items != oldWidget.items) {
      final newItems = widget.items.take(5).toList();
      final oldIds = _displayItems.map((e) => e.id).join(',');
      final newIds = newItems.map((e) => e.id).join(',');
      
      if (oldIds != newIds) {
        setState(() {
          _displayItems = newItems;
          final maxDist = _displayItems.length ~/ 2;
          _positions = List.generate(_displayItems.length, (index) => index - maxDist);
          _updateActiveIndex();
        });
      }
    }
  }

  @override
  void dispose() {
    _stopAutoPlay();
    super.dispose();
  }

  void _startAutoPlay() {
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _step(-1); // Shift to next (active 1 becomes active 0)
    });
  }

  void _stopAutoPlay() {
    _autoPlayTimer?.cancel();
  }

  void _resetAutoPlay() {
    _stopAutoPlay();
    _startAutoPlay();
  }

  void _updateActiveIndex() {
    _activeIndex = _positions.indexOf(0);
    // Safety check: if 0 is not found (shouldn't happen), use first item
    if (_activeIndex == -1 && _displayItems.isNotEmpty) {
      _activeIndex = 0;
    }
  }

  /// Implements JS: getPos = (current, active) => { diff = current - active; if (abs(diff) > maxDist) return -current; return diff; }
  void _rotate(int activePos) {
    if (_displayItems.isEmpty) return;
    
    setState(() {
      final maxDist = _displayItems.length ~/ 2;
      for (int i = 0; i < _positions.length; i++) {
        final current = _positions[i];
        final diff = current - activePos;
        
        if (diff.abs() > maxDist) {
          _positions[i] = -current;
        } else {
          _positions[i] = diff;
        }
      }
      _updateActiveIndex();
    });
  }

  void _step(int direction) {
    // direction -1 = next, 1 = previous
    // To move to "next", we act as if we clicked the item at pos 1
    setState(() {
      for (int i = 0; i < _positions.length; i++) {
        int current = _positions[i];
        int nextPos = current + direction;
        
        // Handle wrapping logic from JS: if nextPos > 2 return -2
        if (nextPos > 2) nextPos = -2;
        if (nextPos < -2) nextPos = 2;
        
        _positions[i] = nextPos;
      }
      _updateActiveIndex();
    });
  }

  void _handleTap(int index) {
    _resetAutoPlay();
    final clickedPos = _positions[index];
    if (clickedPos == 0) {
      final item = _displayItems[index];
      context.push('/details/${item.mediaType}/${item.id}');
    } else if (clickedPos > 0) {
      _step(-1); // Always move only one step towards the right
    } else if (clickedPos < 0) {
      _step(1); // Always move only one step towards the left
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_displayItems.isEmpty) return const SizedBox.shrink();

    final r = Responsive(context);
    final carouselHeight = r.h(320).clamp(240.0, 420.0);

    // Safety check for activeIndex
    final activeIndex = _activeIndex >= 0 && _activeIndex < _displayItems.length 
        ? _activeIndex 
        : 0;
    final activeItem = _displayItems[activeIndex];

    return Column(
      children: [
        GestureDetector(
          onHorizontalDragEnd: (details) {
            _resetAutoPlay();
            if (details.primaryVelocity == null) return;
            if (details.primaryVelocity! < 0) {
              _step(-1); // Swipe left = next
            } else if (details.primaryVelocity! > 0) {
              _step(1); // Swipe right = previous
            }
          },
          child: SizedBox(
            height: carouselHeight,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: List.generate(_displayItems.length, (index) {
                final pos = _positions[index];
                return _buildCarouselItem(index, pos);
              }).toList()
                ..sort((a, b) {
                  final idxA = (a.key as ValueKey<int>).value;
                  final idxB = (b.key as ValueKey<int>).value;
                  final zA = _getZIndex(_positions[idxA]);
                  final zB = _getZIndex(_positions[idxB]);
                  return zA.compareTo(zB);
                }),
            ),
          ),
        ),
        SizedBox(height: r.h(24)),
        // Active Item Info Display — always fetch TMDB logo
        Container(
          height: r.h(60),
          padding: EdgeInsets.symmetric(horizontal: r.w(32)),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.2),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: _TmdbLogoInfo(
              key: ValueKey('active_info_${activeItem.id}'),
              item: activeItem,
            ),
          ),
        ),
      ],
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

  Widget _buildCarouselItem(int index, int pos) {
    final item = _displayItems[index];
    final r = Responsive(context);

    double scale = 1.0;
    double translateX = 0.0;
    double opacity = 1.0;

    final double cardWidth = r.w(170).clamp(120.0, 220.0);
    final double cardHeight = r.h(280).clamp(210.0, 360.0);
    final double offset1 = r.w(75).clamp(55.0, 100.0);
    final double offset2 = r.w(130).clamp(95.0, 170.0);

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
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedTransform(
          transform: Matrix4.identity()
            ..translate(translateX)
            ..scale(scale),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: GestureDetector(
            onTap: () => _handleTap(index),
            behavior: HitTestBehavior.opaque,
            child: AnimatedOpacity(
              opacity: opacity,
              duration: const Duration(milliseconds: 250),
              child: Container(
                  width: cardWidth,
                  height: cardHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CachedNetworkImage(
                    imageUrl: item.effectivePosterUrl ?? '',
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: AppColors.surfaceElevated),
                    errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fetches and displays TMDB logo for the active carousel item.
/// Falls back to text title if no logo is available.
class _TmdbLogoInfo extends ConsumerWidget {
  final ManifestItem item;

  const _TmdbLogoInfo({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = Responsive(context);
    final logoAsync = ref.watch(tmdbLogoProvider(
      TmdbLogoParams(tmdbId: item.id, mediaType: item.mediaType),
    ));

    return Container(
      width: r.w(250).clamp(180.0, 320.0),
      alignment: Alignment.topCenter,
      child: logoAsync.when(
        data: (logoUrl) {
          if (logoUrl != null && logoUrl.isNotEmpty) {
            return CachedNetworkImage(
              imageUrl: logoUrl,
              height: r.h(40).clamp(30.0, 52.0),
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => _buildActiveTitle(context, item.title),
            );
          }
          return _buildActiveTitle(context, item.title);
        },
        loading: () => _buildActiveTitle(context, item.title),
        error: (_, __) => _buildActiveTitle(context, item.title),
      ),
    );
  }

  Widget _buildActiveTitle(BuildContext context, String title) {
    final r = Responsive(context);
    return Text(
      title,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: r.f(22).clamp(16.0, 28.0),
        fontWeight: FontWeight.w900,
        height: 1.2,
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
  AnimatedWidgetBaseState<AnimatedTransform> createState() =>
      _AnimatedTransformState();
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
