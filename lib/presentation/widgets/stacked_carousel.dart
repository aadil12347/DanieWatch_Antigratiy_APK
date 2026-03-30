import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models/manifest_item.dart';

class StackedCarousel extends StatefulWidget {
  final List<ManifestItem> items;
  const StackedCarousel({super.key, required this.items});

  @override
  State<StackedCarousel> createState() => _StackedCarouselState();
}

class _StackedCarouselState extends State<StackedCarousel> {
  late List<int> _positions;
  late List<ManifestItem> _displayItems;
  int _activeIndex = 0;
  Timer? _autoPlayTimer;

  @override
  void initState() {
    super.initState();
    _displayItems = widget.items.take(5).toList();
    _positions = List.generate(_displayItems.length, (index) => index - 2);
    _updateActiveIndex();
    _startAutoPlay();
  }

  @override
  void dispose() {
    _stopAutoPlay();
    super.dispose();
  }

  void _startAutoPlay() {
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _step(-1);
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
  }

  void _step(int direction) {
    setState(() {
      for (int i = 0; i < _positions.length; i++) {
        int current = _positions[i];
        int nextPos = current + direction;
        
        // Handle wrapping logic from JS: if diff.abs() > 2 return -current
        // This effectively means 3 becomes -2 and -3 becomes 2
        if (nextPos > 2) nextPos = -2;
        if (nextPos < -2) nextPos = 2;
        
        _positions[i] = nextPos;
      }
      _updateActiveIndex();
    });
  }

  void _handleTap(int index) {
    _resetAutoPlay();
    final pos = _positions[index];
    if (pos == 0) {
      final item = _displayItems[index];
      context.push('/details/${item.mediaType}/${item.id}');
    } else if (pos > 0) {
      // Right side, move everything left (decrement)
      _step(-1);
    } else if (pos < 0) {
      // Left side, move everything right (increment)
      _step(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_displayItems.isEmpty) return const SizedBox.shrink();

    final activeItem = _displayItems[_activeIndex];

    return Column(
      children: [
        GestureDetector(
          onHorizontalDragEnd: (details) {
            _resetAutoPlay();
            if (details.primaryVelocity == null) return;
            if (details.primaryVelocity! < 0) {
              // Swipe Left -> Rotate Right (decrement)
              _step(-1);
            } else if (details.primaryVelocity! > 0) {
              // Swipe Right -> Rotate Left (increment)
              _step(1);
            }
          },
          child: SizedBox(
            height: 320,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: List.generate(_displayItems.length, (index) {
                final pos = _positions[index];
                return _buildCarouselItem(index, pos);
              }).toList()
                ..sort((a, b) {
                  final posA = (a.key as ValueKey<int>).value;
                  final posB = (b.key as ValueKey<int>).value;
                  final zA = _getZIndex(_positions[posA]);
                  final zB = _getZIndex(_positions[posB]);
                  return zA.compareTo(zB);
                }),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Active Item Info Display
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
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
            child: _buildActiveInfo(activeItem),
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

  Widget _buildActiveInfo(ManifestItem item) {
    final logoUrl = item.logoUrl;
    
    return Container(
      key: ValueKey('active_info_${item.id}'),
      width: 250,
      alignment: Alignment.topCenter,
      child: (logoUrl != null && logoUrl.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: logoUrl,
              height: 40,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => _buildActiveTitle(item.title),
            )
          : _buildActiveTitle(item.title),
    );
  }

  Widget _buildActiveTitle(String title) {
    return Text(
      title,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w900,
        height: 1.2,
      ),
    );
  }

  Widget _buildCarouselItem(int index, int pos) {
    final item = _displayItems[index];

    // CSS based transformations - Slightly bigger sizes
    double scale = 1.0;
    double translateX = 0.0;
    double opacity = 1.0;
    double blur = 0.0;

    const double cardWidth = 170.0;
    const double cardHeight = 280.0;

    if (pos == 0) {
      scale = 1.0;
      translateX = 0.0;
      opacity = 1.0;
      blur = 0.0;
    } else if (pos == -1) {
      scale = 0.85;
      translateX = -75.0; 
      opacity = 0.7;
      blur = 1.0;
    } else if (pos == 1) {
      scale = 0.85;
      translateX = 75.0;
      opacity = 0.7;
      blur = 1.0;
    } else if (pos == -2) {
      scale = 0.75;
      translateX = -130.0;
      opacity = 0.4;
      blur = 3.0;
    } else if (pos == 2) {
      scale = 0.75;
      translateX = 130.0;
      opacity = 0.4;
      blur = 3.0;
    }

    return AnimatedPositioned(
      key: ValueKey<int>(index),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedTransform(
          transform: Matrix4.identity()
            ..translate(translateX)
            ..scale(scale),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          child: GestureDetector(
            onTap: () => _handleTap(index),
            behavior: HitTestBehavior.opaque,
            child: AnimatedOpacity(
              opacity: opacity,
              duration: const Duration(milliseconds: 350),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
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
                    imageUrl: item.posterUrl ?? '',
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: AppColors.surfaceElevated),
                    errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                  ),
                ),
              ),
            ),
          ),
        ),
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
