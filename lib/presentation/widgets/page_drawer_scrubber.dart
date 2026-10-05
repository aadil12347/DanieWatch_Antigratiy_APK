import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
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
  late Animation<double> _curveProgress;

  OverlayEntry? _overlayEntry;
  bool _isDragging = false;
  bool _isAnimatingOut = false;
  bool _hasSlid = false;
  double _touchStartY = 0.0;
  double _scrubberStartY = 0.0;
  double _currentScrubberY = 0.0;
  int _highlightedPage = 1;
  int _lastHapticPage = 1;

  @override
  void initState() {
    super.initState();
    _highlightedPage = widget.currentPage.clamp(1, widget.totalPages);
    _lastHapticPage = _highlightedPage;

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 160),
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
          final clampedTouchY = _currentScrubberY.clamp(topSafe, screenHeight - bottomSafe);

          return Stack(
            fit: StackFit.expand,
            children: [

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
                right: 48,
                top: (clampedTouchY - 24).clamp(topSafe, screenHeight - bottomSafe - 48),
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _curveProgress,
                    builder: (context, _) {
                      if (_curveProgress.value <= 0.001) return const SizedBox.shrink();
                      return Transform.scale(
                        scale: _curveProgress.value,
                        alignment: Alignment.centerRight,
                        child: Opacity(
                          opacity: _curveProgress.value.clamp(0.0, 1.0),
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
                                    color: AppColors.primary.withValues(alpha: 0.25),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                    offset: const Offset(-1, 1),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.60),
                                    blurRadius: 12,
                                    offset: const Offset(0, 3),
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
                      );
                    },
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

  void _handleTouchDown(Offset globalPosition, BuildContext context) {
    if (widget.totalPages <= 1) return;
    _animCtrl.stop();

    final mediaQuery = MediaQuery.of(context);
    final topSafe = mediaQuery.padding.top + 70.0;
    final bottomSafe = mediaQuery.padding.bottom + 95.0;
    final screenHeight = mediaQuery.size.height;
    final trackHeight = (screenHeight - topSafe - bottomSafe).clamp(100.0, screenHeight);

    // Initial position is strictly centered on the current page's thumb handle
    final currentRatio = widget.totalPages > 1
        ? (widget.currentPage - 1) / (widget.totalPages - 1)
        : 0.0;
    final currentThumbY = topSafe + (currentRatio.clamp(0.0, 1.0) * trackHeight);

    setState(() {
      _isDragging = true;
      _isAnimatingOut = false;
      _hasSlid = false;
      _touchStartY = globalPosition.dy;
      _scrubberStartY = currentThumbY;
      _currentScrubberY = currentThumbY;
      _highlightedPage = widget.currentPage.clamp(1, widget.totalPages);
      _lastHapticPage = _highlightedPage;
    });

    _showOverlay(context);
    _animCtrl.forward();
    HapticFeedback.selectionClick();
  }

  void _handleTouchUpdate(Offset globalPosition, BuildContext context) {
    if (!_isDragging || widget.totalPages <= 1) return;
    _updateScrubberPosition(globalPosition.dy, context);
    _overlayEntry?.markNeedsBuild();
  }

  void _updateScrubberPosition(double currentGlobalY, BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topSafe = mediaQuery.padding.top + 70.0;
    final bottomSafe = mediaQuery.padding.bottom + 95.0;
    final screenHeight = mediaQuery.size.height;
    final trackHeight = (screenHeight - topSafe - bottomSafe).clamp(100.0, screenHeight);

    final deltaY = currentGlobalY - _touchStartY;
    if (deltaY.abs() > 8.0) {
      _hasSlid = true;
    }

    if (_hasSlid) {
      final newY = (_scrubberStartY + deltaY * 1.2).clamp(topSafe, topSafe + trackHeight);
      _currentScrubberY = newY;

      final ratio = (newY - topSafe) / trackHeight;
      final page = (1 + ratio * (widget.totalPages - 1)).round().clamp(1, widget.totalPages);

      if (page != _highlightedPage) {
        if (page != _lastHapticPage) {
          HapticFeedback.selectionClick();
          _lastHapticPage = page;
        }
        _highlightedPage = page;
      }
    }
  }

  void _handleTouchEnd() {
    if (!_isDragging) return;
    final targetPage = _highlightedPage;
    final didChangePage = _hasSlid && targetPage != widget.currentPage;

    setState(() {
      _isDragging = false;
      _isAnimatingOut = true;
    });

    if (didChangePage) {
      HapticFeedback.mediumImpact();
      widget.onPageSelected(targetPage);
    }

    _animCtrl.reverse().then((_) {
      if (!_isDragging && mounted) {
        _removeOverlay();
        setState(() {
          _isAnimatingOut = false;
        });
      }
    });
  }

  void _handleTouchCancel() {
    if (!_isDragging) return;
    setState(() {
      _isDragging = false;
      _isAnimatingOut = true;
    });
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
              // Resting visible thumb handle & track line on the right edge ONLY when NOT dragging or animating
              if (!_isDragging && !_isAnimatingOut && _overlayEntry == null)
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
              // Uses RawGestureDetector + _ImmediateScrubberGestureRecognizer to resolve & claim arena on pointer down,
              // preventing TabBarView or CustomScrollView from intercepting or cancelling tap-and-hold!
              Positioned(
                right: 0,
                top: topSafe,
                height: trackHeight,
                width: 48,
                child: RawGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  gestures: <Type, GestureRecognizerFactory>{
                    _ImmediateScrubberGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<_ImmediateScrubberGestureRecognizer>(
                      () => _ImmediateScrubberGestureRecognizer(),
                      (_ImmediateScrubberGestureRecognizer instance) {
                        instance.onStart = (pos) => _handleTouchDown(pos, context);
                        instance.onUpdate = (pos) => _handleTouchUpdate(pos, context);
                        instance.onEnd = () => _handleTouchEnd();
                        instance.onCancel = () => _handleTouchCancel();
                      },
                    ),
                  },
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

/// Immediate gesture recognizer that claims the arena on PointerDownEvent.
/// Prevents parent TabBarView (horizontal) or CustomScrollView (vertical) from
/// stealing the gesture or issuing a cancel during tap-and-hold or scrubbing.
class _ImmediateScrubberGestureRecognizer extends OneSequenceGestureRecognizer {
  _ImmediateScrubberGestureRecognizer();

  void Function(Offset globalPosition)? onStart;
  void Function(Offset globalPosition)? onUpdate;
  void Function()? onEnd;
  void Function()? onCancel;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    onStart?.call(event.position);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onUpdate?.call(event.position);
    } else if (event is PointerUpEvent) {
      stopTrackingPointer(event.pointer);
      onEnd?.call();
    } else if (event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
      onCancel?.call();
    }
  }

  @override
  String get debugDescription => 'ImmediateScrubberGestureRecognizer';

  @override
  void didStopTrackingLastPointer(int pointer) {}
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
    final trackX = size.width - 10.0;

    // Normal straight rail line if curveProgress is near 0
    if (curveProgress <= 0.001) {
      final basePaint = Paint()
        ..color = railColor
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(trackX, trackTop),
        Offset(trackX, trackBottom),
        basePaint,
      );
      return;
    }

    // ── Curved Wave Rail (deformed subtly away from the screen edge at touch point) ─
    final maxDisplacement = 20.0 * curveProgress;
    const curveSpan = 74.0; // Vertical span of the curve above and below touchY

    final clampedTouchY = touchY.clamp(trackTop, trackBottom);
    final topCurveY = (clampedTouchY - curveSpan).clamp(trackTop, trackBottom);
    final bottomCurveY = (clampedTouchY + curveSpan).clamp(trackTop, trackBottom);
    final apexX = trackX - maxDisplacement;

    final path = Path();
    path.moveTo(trackX, trackTop);
    path.lineTo(trackX, topCurveY);

    // Smooth cubic Bezier with natural minor curvature
    path.cubicTo(
      trackX,
      topCurveY + (clampedTouchY - topCurveY) * 0.45,
      apexX,
      clampedTouchY - (clampedTouchY - topCurveY) * 0.45,
      apexX,
      clampedTouchY,
    );

    path.cubicTo(
      apexX,
      clampedTouchY + (bottomCurveY - clampedTouchY) * 0.45,
      trackX,
      bottomCurveY - (bottomCurveY - clampedTouchY) * 0.45,
      trackX,
      bottomCurveY,
    );

    path.lineTo(trackX, trackBottom);

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
        Offset(trackX, topCurveY),
        Offset(apexX, clampedTouchY),
        [
          railColor,
          activeColor,
        ],
      )
      ..strokeWidth = 2.5
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
    // Both rail and thumb handle are centered on the exact same X axis
    final trackX = size.width - 10.0;
    final clampedTouchY = touchY.clamp(trackTop, trackBottom);

    // 1. Sleek vertical track line
    final basePaint = Paint()
      ..color = railColor
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(trackX, trackTop),
      Offset(trackX, trackBottom),
      basePaint,
    );

    // 2. Visible floating handle centered EXACTLY on the track line
    const handleWidth = 8.0;
    const handleHeight = 34.0;
    final handleRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(trackX, clampedTouchY),
        width: handleWidth,
        height: handleHeight,
      ),
      const Radius.circular(4.0),
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

    // Mini grip lines inside thumb (centered on trackX)
    final gripPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final centerY = clampedTouchY;
    canvas.drawLine(Offset(trackX - 2, centerY - 4), Offset(trackX + 2, centerY - 4), gripPaint);
    canvas.drawLine(Offset(trackX - 2, centerY), Offset(trackX + 2, centerY), gripPaint);
    canvas.drawLine(Offset(trackX - 2, centerY + 4), Offset(trackX + 2, centerY + 4), gripPaint);
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
