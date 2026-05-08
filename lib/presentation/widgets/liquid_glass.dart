import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';

/// Blur intensity presets for liquid glass surfaces.
enum GlassIntensity { light, medium, heavy, ultra }

/// iOS-style Liquid Glass container widget.
///
/// Unlike heavy frosted glass, liquid glass is:
/// - Thin and transparent — content is clearly visible through it
/// - Refraction-like — slight color distortion, not heavy blur
/// - Alive — animated highlights shift across the surface
/// - Responsive — touch creates ripple waves through the glass
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

  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.intensity = GlassIntensity.medium,
    this.tintColor,
    this.tintOpacity = 0.06,
    this.enableAnimatedBorder = true,
    this.enableTouchRipple = true,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.constraints,
    this.isCircular = false,
    this.onTap,
  });

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass>
    with TickerProviderStateMixin {
  late AnimationController _specularController;
  late AnimationController _rippleController;
  late Animation<double> _rippleCurve;
  Offset _rippleOrigin = Offset.zero;

  // Liquid glass uses MUCH less blur than frosted glass
  double get _blurSigma {
    switch (widget.intensity) {
      case GlassIntensity.light:
        return 6;
      case GlassIntensity.medium:
        return 10;
      case GlassIntensity.heavy:
        return 16;
      case GlassIntensity.ultra:
        return 22;
    }
  }

  Color get _fillColor {
    final tint = widget.tintColor;
    if (tint != null) return tint.withValues(alpha: widget.tintOpacity);
    switch (widget.intensity) {
      case GlassIntensity.light:
        return Colors.white.withValues(alpha: 0.04);
      case GlassIntensity.medium:
        return Colors.white.withValues(alpha: 0.06);
      case GlassIntensity.heavy:
        return Colors.white.withValues(alpha: 0.08);
      case GlassIntensity.ultra:
        return Colors.white.withValues(alpha: 0.10);
    }
  }

  @override
  void initState() {
    super.initState();
    _specularController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _rippleCurve = CurvedAnimation(
      parent: _rippleController,
      curve: Curves.easeOutCubic,
    );
    if (widget.enableAnimatedBorder) {
      _specularController.repeat();
    }
  }

  @override
  void dispose() {
    _specularController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  void _triggerRipple(Offset globalPos) {
    if (!widget.enableTouchRipple) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    _rippleOrigin = box.globalToLocal(globalPos);
    _rippleController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final sigma = _blurSigma;
    final fill = _fillColor;
    final radius = widget.isCircular ? 999.0 : widget.borderRadius;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (d) => _triggerRipple(d.globalPosition),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: widget.width,
        height: widget.height,
        constraints: widget.constraints,
        margin: widget.margin,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: AnimatedBuilder(
              animation: Listenable.merge([_specularController, _rippleCurve]),
              builder: (context, child) {
                return CustomPaint(
                  painter: _LiquidSurfacePainter(
                    fillColor: fill,
                    borderRadius: radius,
                    specularPhase: _specularController.value,
                    enableSpecular: widget.enableAnimatedBorder,
                    rippleOrigin: _rippleOrigin,
                    rippleProgress: _rippleCurve.value,
                    enableRipple: widget.enableTouchRipple,
                  ),
                  child: Container(
                    padding: widget.padding,
                    child: child,
                  ),
                );
              },
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the liquid glass surface layers:
/// 1. Ultra-thin tinted fill (like looking through water)
/// 2. Top-edge caustic highlight (light refracting through liquid surface)
/// 3. Animated specular sweep (light moving across the glass)
/// 4. Touch ripple wave (concentric rings spreading from touch point)
class _LiquidSurfacePainter extends CustomPainter {
  final Color fillColor;
  final double borderRadius;
  final double specularPhase;
  final bool enableSpecular;
  final Offset rippleOrigin;
  final double rippleProgress;
  final bool enableRipple;

  _LiquidSurfacePainter({
    required this.fillColor,
    required this.borderRadius,
    required this.specularPhase,
    required this.enableSpecular,
    required this.rippleOrigin,
    required this.rippleProgress,
    required this.enableRipple,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // Layer 1: Ultra-thin fill — like tinted water
    canvas.drawRRect(rrect, Paint()..color = fillColor);

    canvas.save();
    canvas.clipRRect(rrect);

    // Layer 2: Caustic top highlight — light entering the liquid surface
    final causticRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.45);
    canvas.drawRect(
      causticRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0.04),
            Colors.transparent,
          ],
          stops: const [0.0, 0.3, 1.0],
        ).createShader(causticRect),
    );

    // Layer 3: Bottom edge inner shadow — depth of liquid
    final depthRect = Rect.fromLTWH(0, size.height * 0.75, size.width, size.height * 0.25);
    canvas.drawRect(
      depthRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.08),
          ],
        ).createShader(depthRect),
    );

    // Layer 4: Animated specular highlight sweep
    if (enableSpecular) {
      final sweepAngle = specularPhase * 2 * math.pi;
      // Moving highlight spot
      final spotX = size.width * (0.3 + 0.4 * math.sin(sweepAngle));
      final spotY = size.height * (0.2 + 0.15 * math.cos(sweepAngle * 0.7));
      final spotRadius = size.shortestSide * 0.6;

      canvas.drawCircle(
        Offset(spotX, spotY),
        spotRadius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.06),
              Colors.white.withValues(alpha: 0.02),
              Colors.transparent,
            ],
            stops: const [0.0, 0.4, 1.0],
          ).createShader(
            Rect.fromCircle(center: Offset(spotX, spotY), radius: spotRadius),
          ),
      );
    }

    // Layer 5: Touch ripple — concentric liquid waves
    if (enableRipple && rippleProgress > 0 && rippleProgress < 1) {
      final maxR = size.longestSide * 0.8;
      final fadeOut = 1.0 - rippleProgress;

      // Draw 3 concentric ripple rings
      for (int i = 0; i < 3; i++) {
        final ringProgress = (rippleProgress - i * 0.1).clamp(0.0, 1.0);
        if (ringProgress <= 0) continue;

        final ringRadius = maxR * ringProgress;
        final ringOpacity = 0.08 * fadeOut * (1.0 - i * 0.3);

        canvas.drawCircle(
          rippleOrigin,
          ringRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0 - i * 0.5
            ..color = Colors.white.withValues(alpha: ringOpacity.clamp(0.0, 1.0)),
        );
      }

      // Central glow at ripple origin
      if (rippleProgress < 0.5) {
        final glowOpacity = 0.15 * (1.0 - rippleProgress * 2);
        canvas.drawCircle(
          rippleOrigin,
          20 * rippleProgress,
          Paint()
            ..shader = RadialGradient(
              colors: [
                Colors.white.withValues(alpha: glowOpacity),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromCircle(center: rippleOrigin, radius: 20 * rippleProgress + 1),
            ),
        );
      }
    }

    canvas.restore();

    // Layer 6: Liquid glass border — subtle, slightly brighter at top
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    if (enableSpecular) {
      // Animated border with shifting brightness
      final angle = specularPhase * 2 * math.pi;
      borderPaint.shader = SweepGradient(
        center: Alignment.center,
        startAngle: angle,
        endAngle: angle + 2 * math.pi,
        colors: [
          Colors.white.withValues(alpha: 0.20),
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.12),
          Colors.white.withValues(alpha: 0.05),
          Colors.white.withValues(alpha: 0.20),
        ],
        stops: const [0.0, 0.2, 0.4, 0.7, 1.0],
      ).createShader(rect);
    } else {
      borderPaint.color = Colors.white.withValues(alpha: 0.15);
    }

    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidSurfacePainter old) =>
      specularPhase != old.specularPhase ||
      rippleProgress != old.rippleProgress ||
      fillColor != old.fillColor;
}
