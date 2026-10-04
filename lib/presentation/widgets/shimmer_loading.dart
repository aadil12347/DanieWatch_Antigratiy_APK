import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';

/// A single shimmer placeholder box.
/// Uses a simple static colored box by default for performance.
/// When [animate] is true, wraps in Shimmer (use sparingly — each creates
/// its own AnimationController).
class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final bool animate;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 10,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );

    if (!animate) return box;

    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.surfaceElevated,
      child: box,
    );
  }
}

/// Wraps multiple children in a single Shimmer animation controller.
/// Much more efficient than wrapping each child individually.
class ShimmerGroup extends StatelessWidget {
  final Widget child;
  const ShimmerGroup({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.surfaceElevated,
      child: child,
    );
  }
}

/// A grid of shimmer placeholders (for loading states).
class ShimmerGrid extends StatelessWidget {
  const ShimmerGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ShimmerGroup(
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.55,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: 9,
          itemBuilder: (_, __) => Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}
