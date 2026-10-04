import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';

/// Android App Drawer style fast-page scrubber on the right edge.
/// When user drags vertically:
/// 1. An OverlayEntry is dynamically mounted to the root Navigator Overlay (above ALL scaffolds,
///    bottom navigation bars, and floating support buttons).
/// 2. The entire device screen darkens with a cinematic vignette effect smoothly fading in.
/// 3. The vertical scrubber line gracefully deforms away from the screen edge at the touch point into a liquid curve.
/// 4. A glowing capsule pops out at the peak of the curve displaying the target page number.
/// 5. When the user lifts their finger, it immediately navigates to that page and fades out smoothly.
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
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 220),
    );

    _vignetteFade = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _curveProgress = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutBack,
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
    _removeOverlay();
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        final screenHeight = mediaQuery.size.height;

        final topSafe = mediaQuery.padding.top + 72.0;
        // Padded by 95px above bottom safe area so the scrubber and popped-out pill NEVER
        // intersect, touch, or go behind the bottom navbar or floating support button!
        final bottomSafe = mediaQuery.padding.bottom + 95.0;
        final clampedTouchY = _globalY.clamp(topSafe, screenHeight - bottomSafe);

        return Stack(
          fit: StackFit.expand,
          children: [
            // ── 1. Full-Screen Cinematic Vignette Overlay (above everything) ──
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _vignetteFade,
                  builder: (context, child) {
                    if (_vignetteFade.value <= 0.001) return const SizedBox.shrink();
                    return Opacity(
                      opacity: _vignetteFade.value.clamp(0.0, 1.0),
                      child: child,
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 1.15,
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.85),
                        ],
                        stops: const [0.30, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── 2. Curved Liquid Rail deformed away from screen edge ──────────
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 180,
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
                        isDragging: _isDragging,
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── 3. Popped-out Capsule at the Peak of the Curve ────────────────
            // Positioned at right: 70 (away from screen edge) and clamped safely above bottom navbar
            Positioned(
              right: 70,
              top: (clampedTouchY - 26).clamp(topSafe, screenHeight - bottomSafe - 52),
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
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1B20).withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: AppColors.primary,
                        width: 1.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.55),
                          blurRadius: 24,
                          spreadRadius: 2,
                          offset: const Offset(-2, 2),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.85),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          'PAGE ',
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          '$_highlightedPage',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          ' / ${widget.totalPages}',
                          style: GoogleFonts.inter(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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
    _isDragging = true;
    _globalY = details.globalPosition.dy;
    _updatePageFromY(context);
    _showOverlay(context);
    _animCtrl.forward();
    HapticFeedback.mediumImpact();
    setState(() {});
  }

  void _onDragUpdate(DragUpdateDetails details, BuildContext context) {
    if (!_isDragging || widget.totalPages <= 1) return;
    _globalY = details.globalPosition.dy;
    _updatePageFromY(context);
    _overlayEntry?.markNeedsBuild();
  }

  void _updatePageFromY(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topSafe = mediaQuery.padding.top + 72.0;
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
    _isDragging = false;
    _animCtrl.reverse().then((_) {
      if (!_isDragging) {
        _removeOverlay();
      }
    });
    HapticFeedback.mediumImpact();
    widget.onPageSelected(targetPage);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible || widget.totalPages <= 1) {
      return const SizedBox.shrink();
    }

    final mediaQuery = MediaQuery.of(context);
    final topSafe = mediaQuery.padding.top + 72.0;
    final bottomSafe = mediaQuery.padding.bottom + 95.0;

    return LayoutBuilder(
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
          clipBehavior: Clip.none,
          children: [
            // Resting subtle rail on the right edge when not dragging
            if (!_isDragging)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 24,
                child: CustomPaint(
                  painter: _RestingRailPainter(
                    trackTop: topSafe,
                    trackBottom: screenHeight - bottomSafe,
                    touchY: thumbY,
                    railColor: Colors.white.withValues(alpha: 0.15),
                    activeColor: AppColors.primary.withValues(alpha: 0.8),
                  ),
                ),
              ),

            // Touch gesture target area on the right edge
            Positioned(
              right: 0,
              top: topSafe,
              height: trackHeight,
              width: 44,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (d) => _onDragStart(d, context),
                onVerticalDragUpdate: (d) => _onDragUpdate(d, context),
                onVerticalDragEnd: (_) => _onDragEnd(),
                onVerticalDragCancel: _onDragEnd,
                onTapDown: (d) => _onDragStart(DragStartDetails(globalPosition: d.globalPosition), context),
                onTapUp: (_) => _onDragEnd(),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Custom painter that draws the straight vertical rail and smoothly deforms it
/// into a liquid curved arc that pops out away from the side of the screen at the user's touch point!
class _LiquidCurvedRailPainter extends CustomPainter {
  final double trackTop;
  final double trackBottom;
  final double touchY;
  final double curveProgress;
  final Color railColor;
  final Color activeColor;
  final bool isDragging;

  _LiquidCurvedRailPainter({
    required this.trackTop,
    required this.trackBottom,
    required this.touchY,
    required this.curveProgress,
    required this.railColor,
    required this.activeColor,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rightEdgeX = size.width - 6.0;

    // Normal straight rail line
    if (curveProgress <= 0.001) {
      final basePaint = Paint()
        ..color = railColor
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(rightEdgeX, trackTop),
        Offset(rightEdgeX, trackBottom),
        basePaint,
      );

      final pipPaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(rightEdgeX, touchY.clamp(trackTop, trackBottom)), 4.0, pipPaint);
      return;
    }

    // ── Curved Wave Rail (deformed away from the screen edge at touch point) ─
    final maxDisplacement = 56.0 * curveProgress;
    const curveSpan = 115.0; // Vertical span of the curve above and below touchY

    final clampedTouchY = touchY.clamp(trackTop, trackBottom);
    final topCurveY = (clampedTouchY - curveSpan).clamp(trackTop, trackBottom);
    final bottomCurveY = (clampedTouchY + curveSpan).clamp(trackTop, trackBottom);
    final apexX = rightEdgeX - maxDisplacement;

    final path = Path();
    path.moveTo(rightEdgeX, trackTop);
    path.lineTo(rightEdgeX, topCurveY);

    // Smooth cubic Bezier from straight rail to curved apex away from edge
    path.cubicTo(
      rightEdgeX,
      topCurveY + (clampedTouchY - topCurveY) * 0.45,
      apexX,
      clampedTouchY - (clampedTouchY - topCurveY) * 0.45,
      apexX,
      clampedTouchY,
    );

    // Smooth cubic Bezier from apex back to straight rail
    path.cubicTo(
      apexX,
      clampedTouchY + (bottomCurveY - clampedTouchY) * 0.45,
      rightEdgeX,
      bottomCurveY - (bottomCurveY - clampedTouchY) * 0.45,
      rightEdgeX,
      bottomCurveY,
    );

    path.lineTo(rightEdgeX, trackBottom);

    // Outer glow for the curved line
    final glowPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.45 * curveProgress)
      ..strokeWidth = 9.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawPath(path, glowPaint);

    // Main vibrant neon line
    final curvePaint = Paint()
      ..color = Color.lerp(railColor, activeColor, curveProgress)!
      ..strokeWidth = 3.5 + (1.5 * curveProgress)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, curvePaint);

    // Apex glow behind indicator dot
    final apexGlowPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(apexX, clampedTouchY), 7.0, apexGlowPaint);

    // Apex indicator dot at the peak of the curve
    final apexDotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(apexX, clampedTouchY), 4.5, apexDotPaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidCurvedRailPainter oldDelegate) {
    return oldDelegate.trackTop != trackTop ||
        oldDelegate.trackBottom != trackBottom ||
        oldDelegate.touchY != touchY ||
        oldDelegate.curveProgress != curveProgress ||
        oldDelegate.isDragging != isDragging;
  }
}

/// Resting vertical rail drawn on right edge when not dragging
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
    final rightEdgeX = size.width - 6.0;

    final basePaint = Paint()
      ..color = railColor
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(rightEdgeX, trackTop),
      Offset(rightEdgeX, trackBottom),
      basePaint,
    );

    final pipGlowPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(rightEdgeX, touchY.clamp(trackTop, trackBottom)), 6.0, pipGlowPaint);

    final pipPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(rightEdgeX, touchY.clamp(trackTop, trackBottom)), 3.5, pipPaint);
  }

  @override
  bool shouldRepaint(covariant _RestingRailPainter oldDelegate) {
    return oldDelegate.trackTop != trackTop ||
        oldDelegate.trackBottom != trackBottom ||
        oldDelegate.touchY != touchY;
  }
}
