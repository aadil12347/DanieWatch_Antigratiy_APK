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
  final double edgeGlow;
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
    this.edgeGlow = 0.0,
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
        return 22;
      case GlassIntensity.ultra:
        return 30;
    }
  }

  Color get _fillColor {
    final tint = widget.tintColor;
    if (tint != null) return tint.withValues(alpha: widget.tintOpacity);
    // Blend white with subtle crimson for Netflix-red glass identity
    switch (widget.intensity) {
      case GlassIntensity.light:
        return Color.lerp(Colors.white.withValues(alpha: 0.04), AppColors.glassTintRed, 0.5)!;
      case GlassIntensity.medium:
        return Color.lerp(Colors.white.withValues(alpha: 0.06), AppColors.glassTintRed, 0.4)!;
      case GlassIntensity.heavy:
        return Color.lerp(Colors.white.withValues(alpha: 0.14), AppColors.glassTintRed, 0.3)!;
      case GlassIntensity.ultra:
        return Color.lerp(Colors.white.withValues(alpha: 0.20), AppColors.glassTintRed, 0.25)!;
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
      behavior: widget.onTap != null ? HitTestBehavior.opaque : HitTestBehavior.translucent,
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
                    edgeGlow: widget.edgeGlow,
                  ),
                  child: Container(
                    padding: widget.padding,
                    child: child,
                  ),
                );
              },
              // Wrap child in RepaintBoundary to isolate child repaints
              // from the glass surface animation repaints
              child: RepaintBoundary(child: widget.child),
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
///
/// PERFORMANCE: Static gradient shaders (caustic, depth, edge glow, border)
/// are cached and only rebuilt when canvas size changes. Only the animated
/// specular highlight shaders are recreated per frame (unavoidable — position changes).
class _LiquidSurfacePainter extends CustomPainter {
  final Color fillColor;
  final double borderRadius;
  final double specularPhase;
  final bool enableSpecular;
  final Offset rippleOrigin;
  final double rippleProgress;
  final bool enableRipple;
  final double edgeGlow;

  // ── Cached static shaders & paints ──
  // These are only rebuilt when size or edgeGlow changes
  static Size _cachedSize = Size.zero;
  static double _cachedEdgeGlow = -1;
  static Color _cachedFillColor = Colors.transparent;
  static Shader? _causticShader;
  static Shader? _depthShader;
  static Shader? _edgeGlowShader;
  // Pre-allocated paint objects
  static final Paint _fillPaint = Paint();
  static final Paint _causticPaint = Paint();
  static final Paint _depthPaint = Paint();
  static final Paint _specPaint1 = Paint();
  static final Paint _specPaint2 = Paint();
  static final Paint _edgeGlowPaint = Paint()
    ..style = PaintingStyle.stroke;
  static final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8;

  _LiquidSurfacePainter({
    required this.fillColor,
    required this.borderRadius,
    required this.specularPhase,
    required this.enableSpecular,
    required this.rippleOrigin,
    required this.rippleProgress,
    required this.enableRipple,
    required this.edgeGlow,
  });

  void _rebuildStaticShaders(Size size) {
    if (size == _cachedSize && edgeGlow == _cachedEdgeGlow && fillColor == _cachedFillColor) return;

    _cachedSize = size;
    _cachedEdgeGlow = edgeGlow;
    _cachedFillColor = fillColor;

    // Caustic top highlight
    final causticRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.45);
    _causticShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(Colors.white.withValues(alpha: 0.12), AppColors.glassRedCaustic, 0.3)!,
        Color.lerp(Colors.white.withValues(alpha: 0.04), AppColors.glassRedCaustic, 0.2)!,
        Colors.transparent,
      ],
      stops: const [0.0, 0.3, 1.0],
    ).createShader(causticRect);

    // Bottom depth shadow
    final depthRect = Rect.fromLTWH(0, size.height * 0.75, size.width, size.height * 0.25);
    _depthShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        Colors.black.withValues(alpha: 0.08),
      ],
    ).createShader(depthRect);

    // Edge glow shader
    if (edgeGlow > 0) {
      final rect = Offset.zero & size;
      _edgeGlowShader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(
            Colors.white.withValues(alpha: edgeGlow * 0.45),
            AppColors.glassHighlightRed,
            0.2,
          )!,
          Color.lerp(
            Colors.white.withValues(alpha: edgeGlow * 0.08),
            AppColors.glassBorderRed,
            0.15,
          )!,
          Color.lerp(
            Colors.white.withValues(alpha: edgeGlow * 0.20),
            AppColors.glassHighlightRed,
            0.1,
          )!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    } else {
      _edgeGlowShader = null;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // Rebuild static shaders only if size/config changed
    _rebuildStaticShaders(size);

    // Layer 1: Ultra-thin fill — like tinted water
    _fillPaint.color = fillColor;
    canvas.drawRRect(rrect, _fillPaint);

    canvas.save();
    canvas.clipRRect(rrect);

    // Layer 2: Caustic top highlight (cached shader)
    final causticRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.45);
    _causticPaint.shader = _causticShader;
    canvas.drawRect(causticRect, _causticPaint);

    // Layer 3: Bottom edge inner shadow (cached shader)
    final depthRect = Rect.fromLTWH(0, size.height * 0.75, size.width, size.height * 0.25);
    _depthPaint.shader = _depthShader;
    canvas.drawRect(depthRect, _depthPaint);

    // Layer 4: Animated specular highlight sweep (position-dependent — must rebuild)
    if (enableSpecular) {
      final sweepAngle = specularPhase * 2 * math.pi;
      final spotX = size.width * (0.3 + 0.4 * math.sin(sweepAngle));
      final spotY = size.height * (0.2 + 0.15 * math.cos(sweepAngle * 0.7));
      final spotRadius = size.shortestSide * 0.6;

      _specPaint1.shader = RadialGradient(
        colors: [
          Color.lerp(Colors.white.withValues(alpha: 0.06), AppColors.glassHighlightRed, 0.35)!,
          Color.lerp(Colors.white.withValues(alpha: 0.02), AppColors.glassHighlightRed, 0.2)!,
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(
        Rect.fromCircle(center: Offset(spotX, spotY), radius: spotRadius),
      );
      canvas.drawCircle(Offset(spotX, spotY), spotRadius, _specPaint1);

      // Secondary specular
      final sweepAngle2 = specularPhase * 2 * math.pi * 1.4;
      final spotX2 = size.width * (0.6 + 0.25 * math.cos(sweepAngle2 * 0.8));
      final spotY2 = size.height * (0.5 + 0.2 * math.sin(sweepAngle2));
      final spotRadius2 = size.shortestSide * 0.35;

      _specPaint2.shader = RadialGradient(
        colors: [
          Color.lerp(Colors.white.withValues(alpha: 0.03), AppColors.glassHighlightRed, 0.25)!,
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ).createShader(
        Rect.fromCircle(center: Offset(spotX2, spotY2), radius: spotRadius2),
      );
      canvas.drawCircle(Offset(spotX2, spotY2), spotRadius2, _specPaint2);
    }

    // Layer 5: Touch ripple — concentric liquid waves
    if (enableRipple && rippleProgress > 0 && rippleProgress < 1) {
      final maxR = size.longestSide * 0.8;
      final fadeOut = 1.0 - rippleProgress;

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
            ..color = Color.lerp(
              Colors.white.withValues(alpha: ringOpacity.clamp(0.0, 1.0)),
              AppColors.glassBorderRed,
              0.3,
            )!,
        );
      }

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

    // Layer 6: Edge glow — rim lighting (cached shader)
    if (edgeGlow > 0 && _edgeGlowShader != null) {
      _edgeGlowPaint
        ..strokeWidth = 2.0 + edgeGlow * 6.0
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.0 + edgeGlow * 6.0)
        ..shader = _edgeGlowShader;
      canvas.drawRRect(rrect.deflate(1.0), _edgeGlowPaint);
    }

    // Layer 7: Liquid glass border
    if (enableSpecular) {
      final angle = specularPhase * 2 * math.pi;
      _borderPaint.shader = SweepGradient(
        center: Alignment.center,
        startAngle: angle,
        endAngle: angle + 2 * math.pi,
        colors: [
          Colors.white.withValues(alpha: 0.20),
          Color.lerp(Colors.white.withValues(alpha: 0.35), AppColors.glassBorderRed, 0.4)!,
          Colors.white.withValues(alpha: 0.12),
          Colors.white.withValues(alpha: 0.05),
          Color.lerp(Colors.white.withValues(alpha: 0.20), AppColors.glassBorderRed, 0.25)!,
        ],
        stops: const [0.0, 0.2, 0.4, 0.7, 1.0],
      ).createShader(rect);
    } else {
      _borderPaint
        ..shader = null
        ..color = Colors.white.withValues(alpha: 0.15);
    }

    canvas.drawRRect(rrect, _borderPaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidSurfacePainter old) =>
      specularPhase != old.specularPhase ||
      rippleProgress != old.rippleProgress ||
      fillColor != old.fillColor ||
      edgeGlow != old.edgeGlow;
}
