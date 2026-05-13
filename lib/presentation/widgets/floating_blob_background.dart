import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';

/// Animated floating gradient blobs that sit behind glass surfaces
/// to create the "liquid" refractive feel of iOS liquid glass.
///
/// Renders 3-4 slowly-drifting radial gradient circles that blend
/// with the dark background, creating subtle color movement visible
/// through the frosted glass layer above.
class FloatingBlobBackground extends StatefulWidget {
  /// Primary colors for the blobs. Defaults to brand colors.
  final List<Color>? colors;

  /// How many blobs to render (2-5).
  final int blobCount;

  /// Overall opacity multiplier for all blobs.
  final double opacity;

  /// Size factor relative to container (0.3 = 30% of container width).
  final double blobSizeFactor;

  const FloatingBlobBackground({
    super.key,
    this.colors,
    this.blobCount = 3,
    this.opacity = 0.35,
    this.blobSizeFactor = 0.5,
  });

  @override
  State<FloatingBlobBackground> createState() => _FloatingBlobBackgroundState();
}

class _FloatingBlobBackgroundState extends State<FloatingBlobBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_BlobConfig> _blobs;
  final _random = math.Random(42);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _blobs = List.generate(widget.blobCount, (i) => _generateBlob(i));
  }

  _BlobConfig _generateBlob(int index) {
    final defaultColors = [
      AppColors.primary,
      AppColors.primary.withValues(alpha: 0.7),
      AppColors.secondary,
      const Color(0xFF6C63FF), // Purple accent
      const Color(0xFF00BFA5), // Teal accent
    ];
    final colors = widget.colors ?? defaultColors;
    return _BlobConfig(
      color: colors[index % colors.length],
      // Stagger phase offsets so blobs don't move in sync
      phaseX: _random.nextDouble() * math.pi * 2,
      phaseY: _random.nextDouble() * math.pi * 2,
      // Different drift speeds
      speedX: 0.3 + _random.nextDouble() * 0.4,
      speedY: 0.2 + _random.nextDouble() * 0.5,
      // Random starting positions (0.0 to 1.0 relative)
      centerX: 0.2 + _random.nextDouble() * 0.6,
      centerY: 0.2 + _random.nextDouble() * 0.6,
      // Random drift amplitude
      amplitudeX: 0.08 + _random.nextDouble() * 0.15,
      amplitudeY: 0.08 + _random.nextDouble() * 0.12,
      // Slightly different sizes
      sizeFactor: widget.blobSizeFactor * (0.7 + _random.nextDouble() * 0.6),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _BlobPainter(
              blobs: _blobs,
              progress: _controller.value,
              opacity: widget.opacity,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _BlobConfig {
  final Color color;
  final double phaseX;
  final double phaseY;
  final double speedX;
  final double speedY;
  final double centerX;
  final double centerY;
  final double amplitudeX;
  final double amplitudeY;
  final double sizeFactor;

  // Pre-computed gradient color stops (cached per blob)
  List<Color>? _gradientColors;
  double _cachedOpacity = -1;

  _BlobConfig({
    required this.color,
    required this.phaseX,
    required this.phaseY,
    required this.speedX,
    required this.speedY,
    required this.centerX,
    required this.centerY,
    required this.amplitudeX,
    required this.amplitudeY,
    required this.sizeFactor,
  });

  /// Returns cached gradient colors, only rebuilding when opacity changes.
  List<Color> getGradientColors(double opacity) {
    if (_cachedOpacity != opacity || _gradientColors == null) {
      _cachedOpacity = opacity;
      _gradientColors = [
        color.withValues(alpha: opacity),
        color.withValues(alpha: opacity * 0.5),
        color.withValues(alpha: opacity * 0.15),
        Colors.transparent,
      ];
    }
    return _gradientColors!;
  }
}

/// PERFORMANCE: Pre-allocates Paint objects and caches gradient color
/// lists per blob. Only the shader Rect (center position) changes per
/// frame — the gradient colors/stops are reused from cache.
class _BlobPainter extends CustomPainter {
  final List<_BlobConfig> blobs;
  final double progress;
  final double opacity;

  // Pre-allocated paints — one per blob (max 5)
  static final List<Paint> _paints = List.generate(5, (_) => Paint());
  static const _stops = [0.0, 0.3, 0.6, 1.0];

  _BlobPainter({
    required this.blobs,
    required this.progress,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * 2 * math.pi;

    for (int i = 0; i < blobs.length; i++) {
      final blob = blobs[i];

      // Calculate animated position
      final cx = size.width *
          (blob.centerX +
              math.sin(t * blob.speedX + blob.phaseX) * blob.amplitudeX);
      final cy = size.height *
          (blob.centerY +
              math.cos(t * blob.speedY + blob.phaseY) * blob.amplitudeY);

      final radius = size.shortestSide * blob.sizeFactor;
      final center = Offset(cx, cy);

      // Reuse pre-allocated paint, only update shader with new position
      final paint = _paints[i];
      paint.shader = RadialGradient(
        colors: blob.getGradientColors(opacity),
        stops: _stops,
      ).createShader(
        Rect.fromCircle(center: center, radius: radius),
      );

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) =>
      progress != old.progress || opacity != old.opacity;
}

/// A compact inline blob background for small surfaces like the navbar.
/// Uses fewer blobs and smaller amplitudes for subtle effect.
class CompactBlobBackground extends StatelessWidget {
  final List<Color>? colors;
  final double opacity;

  const CompactBlobBackground({
    super.key,
    this.colors,
    this.opacity = 0.2,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingBlobBackground(
      colors: colors ??
          [
            AppColors.primary.withValues(alpha: 0.6),
            AppColors.secondary.withValues(alpha: 0.4),
          ],
      blobCount: 2,
      opacity: opacity,
      blobSizeFactor: 0.7,
    );
  }
}
