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

  @override
  void initState() {
    super.initState();
    _displayItems = widget.items.take(5).toList();
    // Initialize positions from -2 to 2
    _positions = List.generate(_displayItems.length, (index) => index - 2);
  }

  void _updatePositions(int clickedIndex) {
    final activePos = _positions[clickedIndex];
    if (activePos == 0) {
      // Already active, navigate to details
      final item = _displayItems[clickedIndex];
      context.push('/details/${item.mediaType}/${item.id}');
      return;
    }

    setState(() {
      for (int i = 0; i < _positions.length; i++) {
        _positions[i] = _getNewPos(_positions[i], activePos);
      }
    });
  }

  int _getNewPos(int current, int active) {
    final diff = current - active;
    if (diff.abs() > 2) {
      return -current;
    }
    return diff;
  }

  @override
  Widget build(BuildContext context) {
    if (_displayItems.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 350,
      width: double.infinity,
      child: Center(
        child: Container(
          height: 300,
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: List.generate(_displayItems.length, (index) {
              final pos = _positions[index];
              return _buildCarouselItem(index, pos);
            }).toList()
              ..sort((a, b) {
                // Sort by z-index (absolute value of pos, lower absolute value = higher index)
                // pos 0 is highest, then -1 and 1, then -2 and 2
                final posA = (a.key as ValueKey<int>).value;
                final posB = (b.key as ValueKey<int>).value;
                
                final zA = _getZIndex(_positions[posA]);
                final zB = _getZIndex(_positions[posB]);
                return zA.compareTo(zB);
              }),
          ),
        ),
      ),
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

    // CSS based transformations
    double scale = 1.0;
    double translateX = 0.0;
    double opacity = 1.0;
    double blur = 0.0;

    if (pos == 0) {
      scale = 1.0;
      translateX = 0.0;
      opacity = 1.0;
      blur = 0.0;
    } else if (pos == -1) {
      scale = 0.9;
      translateX = -60.0; // Adjusted from -40% to fixed pixels for a 150px item
      opacity = 0.7;
      blur = 1.0;
    } else if (pos == 1) {
      scale = 0.9;
      translateX = 60.0;
      opacity = 0.7;
      blur = 1.0;
    } else if (pos == -2) {
      scale = 0.8;
      translateX = -105.0; // Adjusted from -70%
      opacity = 0.4;
      blur = 3.0;
    } else if (pos == 2) {
      scale = 0.8;
      translateX = 105.0;
      opacity = 0.4;
      blur = 3.0;
    }

    return AnimatedPositioned(
      key: ValueKey<int>(index),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeIn,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedTransform(
          transform: Matrix4.identity()
            ..translate(translateX)
            ..scale(scale),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeIn,
          child: GestureDetector(
            onTap: () => _updatePositions(index),
            child: AnimatedOpacity(
              opacity: opacity,
              duration: const Duration(milliseconds: 300),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: Container(
                  width: 150,
                  height: 250,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
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
