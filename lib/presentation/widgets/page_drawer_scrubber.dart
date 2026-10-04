import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';

/// Android App Drawer style fast-page scrubber on the right edge.
/// When resting:
/// - Displays a refined vertical hairline track and a glowing neon thumb handle with grip bars.
/// When user touches or drags:
/// 1. An OverlayEntry is mounted to the root Navigator Overlay (above ALL scaffolds,
///    bottom navigation bars, and floating support buttons).
/// 2. The resting rail is immediately hidden to prevent any duplicate/ghost slider.
/// 3. The entire screen smoothly darkens with a cinematic radial vignette emerging from the slider
///    at the user's finger touch point (NO blur filter, preventing screen freeze/caching).
/// 4. The vertical scrubber line deforms slightly away from the screen edge at the touch point
///    into a subtle minor curve.
/// 5. A glowing capsule pops out at the curve displaying the target page number (with zero yellow underlines).
/// 6. When the user lifts their finger, it navigates to that page and fades out smoothly.
class PageDrawerScrubber extends StatefulWidget {
  final int totalPages;
  final int currentPage;
  final ValueChanged<int> onPageSelected;
  final bool isVisible;

  const PageDrawerScrubber({
    super.key,
    required this.totalPages,
    required this.currentPage,
    required this.onPageSelected,
    this.isVisible = true,
  });

  @override
  State<PageDrawerScrubber> createState() => _PageDrawerScrubberState();
}

class _PageDrawerScrubberState extends State<PageDrawerScrubber>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _vignetteFade;
  late Animation<double> _curveProgress;

  OverlayEntry? _overlayEntry;
  bool _isDragging = false;
  bool _isAnimatingOut = false;
  double _globalY = 0.0;
  int _highlightedPage = 1;
  int _lastHapticPage = 1;

  @override
  void initState() {
    super.initState();
    _highlightedPage = widget.currentPage.clamp(1, widget.totalPages);
    _lastHapticPage = _highlightedPage;

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );

    _vignetteFade = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _curveProgress = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(covariant PageDrawerScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && widget.currentPage != oldWidget.currentPage) {
      _highlightedPage = widget.currentPage.clamp(1, widget.totalPages);
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _animCtrl.dispose();
    super.dispose();
  }

  void _showOverlay(BuildContext context) {
    _animCtrl.stop();
    if (_overlayEntry == null) {
      final overlayState = Overlay.maybeOf(context, rootOverlay: true);
      if (overlayState == null) return;

      _overlayEntry = OverlayEntry(
        builder: (context) {
          final mediaQuery = MediaQuery.of(context);
          final screenHeight = mediaQuery.size.height;

          final topSafe = mediaQuery.padding.top + 70.0;
          // Padded by 95px above bottom safe area so the scrubber and popped-out pill NEVER
          // intersect, touch, or go behind the bottom navbar or floating support button!
          final bottomSafe = mediaQuery.padding.bottom + 95.0;
          final clampedTouchY = _globalY.clamp(topSafe, screenHeight - bottomSafe);
          final normalizedY = screenHeight > 0
              ? ((clampedTouchY / screenHeight) * 2.0 - 1.0).clamp(-1.0, 1.0)
              : 0.0;

          return Stack(
            fit: StackFit.expand,
            children: [
              // ── 1. Full-Screen Cinematic Dark Vignette Emerging from Finger Touch Point ──
              // No BackdropFilter blur is used so the screen is never frozen or raster-cached!
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _vignetteFade,
                    builder: (context, _) {
                      if (_vignetteFade.value <= 0.001) return const SizedBox.shrink();
                      return Opacity(
                        opacity: _vignetteFade.value.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(1.0, normalizedY),
                              radius: 1.5,
                              colors: [
                                Colors.black.withValues(alpha: 0.20),
                                Colors.black.withValues(alpha: 0.65),
                                Colors.black.withValues(alpha: 0.88),
                              ],
                              stops: const [0.0, 0.45, 1.0],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── 2. Subtle Minor Curved Liquid Rail at Touch Point ─────────────
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 140,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _curveProgress,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _LiquidCurvedRailPainter(
                          trackTop: topSafe,
                          trackBottom: screenHeight - bottomSafe,
                          touchY: clampedTouchY,
                          curveProgress: _curveProgress.value,
                          railColor: Colors.white.withValues(alpha: 0.22),
                          activeColor: AppColors.primary,
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── 3. Popped-out Capsule at the Peak of the Curve ────────────────
              // Wrapped in Material to eliminate default yellow double underlines
              Positioned(
                right: 50,
                top: (clampedTouchY - 24).clamp(topSafe, screenHeight - bottomSafe - 48),
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _curveProgress,
                    builder: (context, child) {
                      if (_curveProgress.value <= 0.001) return const SizedBox.shrink();
                      return Transform.scale(
                        scale: _curveProgress.value,
                        alignment: Alignment.centerRight,
                        child: Opacity(
                          opacity: _curveProgress.value.clamp(0.0, 1.0),
                          child: child,
                        ),
                      );
                    },
                    child: Material(
                      type: MaterialType.transparency,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141419).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.85),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 18,
                              spreadRadius: 1,
                              offset: const Offset(-2, 2),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.85),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                'PAGE',
                                style: GoogleFonts.inter(
                                  color: AppColors.primary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$_highlightedPage',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            Text(
                              ' / ${widget.totalPages}',
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );

      overlayState.insert(_overlayEntry!);
    } else {
      _overlayEntry?.markNeedsBuild();
    }
  }

  void _removeOverlay() {
    if (_overlayEntry != null) {
      if (_overlayEntry!.mounted) {
        _overlayEntry!.remove();
      }
      _overlayEntry = null;
    }
  }

  void _onDragStart(DragStartDetails details, BuildContext context) {
    if (widget.totalPages <= 1) return;
    setState(() {
      _isDragging = true;
      _isAnimatingOut = false;
      _globalY = details.globalPosition.dy;
    });
    _updatePageFromY(context);
    _showOverlay(context);
    _animCtrl.forward(from: 0.0);
    HapticFeedback.mediumImpact();
  }

  void _onDragUpdate(DragUpdateDetails details, BuildContext context) {
    if (!_isDragging || widget.totalPages <= 1) return;
    _globalY = details.globalPosition.dy;
    _updatePageFromY(context);
    _overlayEntry?.markNeedsBuild();
  }

  void _updatePageFromY(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topSafe = mediaQuery.padding.top + 70.0;
    final bottomSafe = mediaQuery.padding.bottom + 95.0;
    final screenHeight = mediaQuery.size.height;
    final trackHeight = (screenHeight - topSafe - bottomSafe).clamp(100.0, screenHeight);

    final clampedY = (_globalY - topSafe).clamp(0.0, trackHeight);
    final ratio = clampedY / trackHeight;
    final page = (1 + ratio * (widget.totalPages - 1)).round().clamp(1, widget.totalPages);

    if (page != _highlightedPage) {
      if (page != _lastHapticPage) {
        HapticFeedback.selectionClick();
        _lastHapticPage = page;
      }
      _highlightedPage = page;
    }
  }

  void _onDragEnd() {
    if (!_isDragging) return;
    final targetPage = _highlightedPage;
    setState(() {
      _isDragging = false;
      _isAnimatingOut = true;
    });
    HapticFeedback.mediumImpact();
    widget.onPageSelected(targetPage);

    _animCtrl.reverse().then((_) {
      if (!_isDragging && mounted) {
        _removeOverlay();
        setState(() {
          _isAnimatingOut = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible || widget.totalPages <= 1) {
      return const SizedBox.shrink();
    }

    final mediaQuery = MediaQuery.of(context);
    final topSafe = mediaQuery.padding.top + 70.0;
    final bottomSafe = mediaQuery.padding.bottom + 95.0;

    return SizedBox(
      width: 48,
      height: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenHeight = constraints.maxHeight;
          final trackHeight = (screenHeight - topSafe - bottomSafe).clamp(100.0, screenHeight);

          // Thumb position along the track
          final currentRatio = widget.totalPages > 1
              ? ((_isDragging ? _highlightedPage : widget.currentPage) - 1) /
                  (widget.totalPages - 1)
              : 0.0;
          final thumbY = topSafe + (currentRatio.clamp(0.0, 1.0) * trackHeight);

          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              // Resting visible thumb handle & track line on the right edge ONLY when NOT dragging
              if (!_isDragging && !_isAnimatingOut)
                CustomPaint(
                  size: Size(48, screenHeight),
                  painter: _RestingRailPainter(
                    trackTop: topSafe,
                    trackBottom: screenHeight - bottomSafe,
                    touchY: thumbY,
                    railColor: Colors.white.withValues(alpha: 0.22),
                    activeColor: AppColors.primary,
                  ),
                ),

              // Touch gesture target area (48px wide along right edge)
              Positioned(
                right: 0,
                top: topSafe,
                height: trackHeight,
                width: 48,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (d) => _onDragStart(d, context),
                  onVerticalDragUpdate: (d) => _onDragUpdate(d, context),
                  onVerticalDragEnd: (_) => _onDragEnd(),
                  onVerticalDragCancel: _onDragEnd,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Custom painter that draws the straight vertical rail and smoothly deforms it
/// into a minor, subtle curved arc that bows gently away from the side of the screen at the user's touch point.
class _LiquidCurvedRailPainter extends CustomPainter {
  final double trackTop;
  final double trackBottom;
  final double touchY;
  final double curveProgress;
  final Color railColor;
  final Color activeColor;

  _LiquidCurvedRailPainter({
    required this.trackTop,
    required this.trackBottom,
    required this.touchY,
    required this.curveProgress,
    required this.railColor,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rightEdgeX = size.width - 4.0;

    // Normal straight rail line if curveProgress is near 0
    if (curveProgress <= 0.001) {
      final basePaint = Paint()
        ..color = railColor
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(rightEdgeX, trackTop),
        Offset(rightEdgeX, trackBottom),
        basePaint,
      );
      return;
    }

    // ── Curved Wave Rail (deformed subtly away from the screen edge at touch point) ─
    // Subtle, gentle minor curve: 18px maximum displacement
    final maxDisplacement = 18.0 * curveProgress;
    const curveSpan = 72.0; // Vertical span of the curve above and below touchY

    final clampedTouchY = touchY.clamp(trackTop, trackBottom);
    final topCurveY = (clampedTouchY - curveSpan).clamp(trackTop, trackBottom);
    final bottomCurveY = (clampedTouchY + curveSpan).clamp(trackTop, trackBottom);
    final apexX = rightEdgeX - maxDisplacement;

    final path = Path();
    path.moveTo(rightEdgeX, trackTop);
    path.lineTo(rightEdgeX, topCurveY);

    // Smooth cubic Bezier with natural minor curvature
    path.cubicTo(
      rightEdgeX,
      topCurveY + (clampedTouchY - topCurveY) * 0.45,
      apexX,
      clampedTouchY - (clampedTouchY - topCurveY) * 0.45,
      apexX,
      clampedTouchY,
    );

    path.cubicTo(
      apexX,
      clampedTouchY + (bottomCurveY - clampedTouchY) * 0.45,
      rightEdgeX,
      bottomCurveY - (bottomCurveY - clampedTouchY) * 0.45,
      rightEdgeX,
      bottomCurveY,
    );

    path.lineTo(rightEdgeX, trackBottom);

    // 1. Soft atmospheric glow behind the curve
    final glowPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.28 * curveProgress)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(path, glowPaint);

    // 2. Vibrant neon curve line
    final curvePaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(rightEdgeX, topCurveY),
        Offset(apexX, clampedTouchY),
        [
          railColor,
          activeColor,
        ],
      )
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, curvePaint);

    // 3. Concentric glowing apex rings
    final outerRingPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(apexX, clampedTouchY), 6.5, outerRingPaint);

    final innerRingPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(apexX, clampedTouchY), 4.0, innerRingPaint);

    final centerDotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(apexX, clampedTouchY), 2.0, centerDotPaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidCurvedRailPainter oldDelegate) {
    return oldDelegate.trackTop != trackTop ||
        oldDelegate.trackBottom != trackBottom ||
        oldDelegate.touchY != touchY ||
        oldDelegate.curveProgress != curveProgress;
  }
}

/// Resting vertical rail and handle drawn on right edge when not dragging
class _RestingRailPainter extends CustomPainter {
  final double trackTop;
  final double trackBottom;
  final double touchY;
  final Color railColor;
  final Color activeColor;

  _RestingRailPainter({
    required this.trackTop,
    required this.trackBottom,
    required this.touchY,
    required this.railColor,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rightEdgeX = size.width - 4.0;
    final clampedTouchY = touchY.clamp(trackTop, trackBottom);

    // 1. Sleek vertical track line
    final basePaint = Paint()
      ..color = railColor
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(rightEdgeX, trackTop),
      Offset(rightEdgeX, trackBottom),
      basePaint,
    );

    // 2. Visible floating handle on the track
    const handleWidth = 9.0;
    const handleHeight = 32.0;
    final handleRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(rightEdgeX - 2.0, clampedTouchY),
        width: handleWidth,
        height: handleHeight,
      ),
      const Radius.circular(4.5),
    );

    // Glow aura behind thumb
    final thumbGlowPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(handleRect, thumbGlowPaint);

    // Solid dark handle body
    final thumbBodyPaint = Paint()
      ..color = const Color(0xFF1E1E26)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(handleRect, thumbBodyPaint);

    // Neon accent border
    final thumbBorderPaint = Paint()
      ..color = activeColor
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(handleRect, thumbBorderPaint);

    // Mini grip lines inside thumb
    final gripPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final centerY = clampedTouchY;
    final centerX = rightEdgeX - 2.0;
    canvas.drawLine(Offset(centerX - 2, centerY - 3), Offset(centerX + 2, centerY - 3), gripPaint);
    canvas.drawLine(Offset(centerX - 2, centerY), Offset(centerX + 2, centerY), gripPaint);
    canvas.drawLine(Offset(centerX - 2, centerY + 3), Offset(centerX + 2, centerY + 3), gripPaint);
  }

  @override
  bool shouldRepaint(covariant _RestingRailPainter oldDelegate) {
    return oldDelegate.trackTop != trackTop ||
        oldDelegate.trackBottom != trackBottom ||
        oldDelegate.touchY != touchY ||
        oldDelegate.railColor != railColor ||
        oldDelegate.activeColor != activeColor;
  }
}
