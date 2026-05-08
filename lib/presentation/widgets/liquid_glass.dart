import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';

/// Blur intensity presets for liquid glass surfaces.
enum GlassIntensity { light, medium, heavy, ultra }

/// iOS-style Liquid Glass container widget.
///
/// Creates a frosted glass surface with:
/// - Multi-layer backdrop blur
/// - Animated specular border highlight
/// - Inner depth shadow
/// - Optional context-aware tint color
/// - Optional touch-reactive ripple
class LiquidGlass extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final GlassIntensity intensity;
  final Color? tintColor;
  final double tintOpacity;
  final bool enableAnimatedBorder;
  final bool enableTouchRipple;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final bool isCircular;
  final VoidCallback? onTap;
  final BoxShape shape;

  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.intensity = GlassIntensity.medium,
    this.tintColor,
    this.tintOpacity = 0.08,
    this.enableAnimatedBorder = true,
    this.enableTouchRipple = false,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.constraints,
    this.isCircular = false,
    this.onTap,
    this.shape = BoxShape.rectangle,
  });

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass>
    with SingleTickerProviderStateMixin {
  late AnimationController _specularController;
  Offset? _rippleOrigin;
  double _rippleProgress = 0;

  double get _blurSigma {
    switch (widget.intensity) {
      case GlassIntensity.light:
        return 12;
      case GlassIntensity.medium:
        return 20;
      case GlassIntensity.heavy:
        return 30;
      case GlassIntensity.ultra:
        return 40;
    }
  }

  Color get _fillColor {
    final tint = widget.tintColor;
    switch (widget.intensity) {
      case GlassIntensity.light:
        return tint?.withValues(alpha: widget.tintOpacity) ??
            AppColors.glassLight;
      case GlassIntensity.medium:
        return tint?.withValues(alpha: widget.tintOpacity) ??
            AppColors.glassMedium;
      case GlassIntensity.heavy:
        return tint?.withValues(alpha: widget.tintOpacity + 0.04) ??
            AppColors.glassHeavy;
      case GlassIntensity.ultra:
        return tint?.withValues(alpha: widget.tintOpacity + 0.08) ??
            AppColors.glassHeavy;
    }
  }

  @override
  void initState() {
    super.initState();
    _specularController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.enableAnimatedBorder) {
      _specularController.repeat();
    }
  }

  @override
  void didUpdateWidget(LiquidGlass old) {
    super.didUpdateWidget(old);
    if (widget.enableAnimatedBorder && !_specularController.isAnimating) {
      _specularController.repeat();
    } else if (!widget.enableAnimatedBorder && _specularController.isAnimating) {
      _specularController.stop();
    }
  }

  @override
  void dispose() {
    _specularController.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent e) {
    if (!widget.enableTouchRipple) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    setState(() {
      _rippleOrigin = box.globalToLocal(e.position);
      _rippleProgress = 1.0;
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _rippleProgress = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sigma = _blurSigma;
    final fill = _fillColor;
    final radius = widget.isCircular ? 999.0 : widget.borderRadius;
    final borderRadiusGeometry = widget.shape == BoxShape.circle
        ? null
        : BorderRadius.circular(radius);

    Widget glass = AnimatedBuilder(
      animation: _specularController,
      builder: (context, child) {
        // Animated specular border gradient
        final angle = _specularController.value * 2 * math.pi;
        final specularGradient = widget.enableAnimatedBorder
            ? SweepGradient(
                center: Alignment.center,
                startAngle: angle,
                endAngle: angle + 2 * math.pi,
                colors: const [
                  AppColors.glassBorder,
                  AppColors.glassSpecular,
                  AppColors.glassBorder,
                  Colors.transparent,
                  AppColors.glassBorder,
                ],
                stops: const [0.0, 0.15, 0.3, 0.6, 1.0],
              )
            : null;

        return Container(
          width: widget.width,
          height: widget.height,
          constraints: widget.constraints,
          margin: widget.margin,
          child: ClipRRect(
            borderRadius: borderRadiusGeometry ?? BorderRadius.zero,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _LiquidGlassPainter(
                    fillColor: fill,
                    borderRadius: radius,
                    specularGradient: specularGradient,
                    rippleOrigin: _rippleOrigin,
                    rippleProgress: _rippleProgress,
                    isCircle: widget.shape == BoxShape.circle,
                  ),
                  child: Container(
                    padding: widget.padding,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );

    if (widget.enableTouchRipple || widget.onTap != null) {
      glass = Listener(
        onPointerDown: _handlePointerDown,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: glass,
        ),
      );
    }

    return glass;
  }
}

/// Custom painter for the liquid glass effect layers.
class _LiquidGlassPainter extends CustomPainter {
  final Color fillColor;
  final double borderRadius;
  final Gradient? specularGradient;
  final Offset? rippleOrigin;
  final double rippleProgress;
  final bool isCircle;

  _LiquidGlassPainter({
    required this.fillColor,
    required this.borderRadius,
    this.specularGradient,
    this.rippleOrigin,
    this.rippleProgress = 0,
    this.isCircle = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = isCircle
        ? RRect.fromRectAndRadius(rect, Radius.circular(size.width / 2))
        : RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // Layer 1: Semi-transparent fill
    canvas.drawRRect(
      rrect,
      Paint()..color = fillColor,
    );

    // Layer 2: Inner top highlight (depth illusion)
    final highlightRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.5);
    final highlightRRect = isCircle
        ? RRect.fromRectAndRadius(highlightRect, Radius.circular(size.width / 2))
        : RRect.fromRectAndRadius(highlightRect, Radius.circular(borderRadius));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRRect(
      highlightRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(highlightRect),
    );
    canvas.restore();

    // Layer 3: Inner bottom shadow (depth)
    final shadowRect = Rect.fromLTWH(
        0, size.height * 0.7, size.width, size.height * 0.3);
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      shadowRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.06),
          ],
        ).createShader(shadowRect),
    );
    canvas.restore();

    // Layer 4: Specular animated border
    if (specularGradient != null) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..shader = specularGradient!.createShader(rect),
      );
    } else {
      // Static subtle border
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = AppColors.glassBorder,
      );
    }

    // Layer 5: Touch ripple
    if (rippleOrigin != null && rippleProgress > 0) {
      final maxRadius = size.longestSide;
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawCircle(
        rippleOrigin!,
        maxRadius * rippleProgress * 0.6,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.12 * (1 - rippleProgress)),
              Colors.white.withValues(alpha: 0.04 * (1 - rippleProgress)),
              Colors.transparent,
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(
            Rect.fromCircle(
              center: rippleOrigin!,
              radius: maxRadius * rippleProgress * 0.6,
            ),
          ),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassPainter old) =>
      fillColor != old.fillColor ||
      specularGradient != old.specularGradient ||
      rippleProgress != old.rippleProgress ||
      rippleOrigin != old.rippleOrigin;
}
