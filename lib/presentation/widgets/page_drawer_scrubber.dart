import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';

/// Android App Drawer style fast-page scrubber on the right edge.
/// When user drags vertically, a curved pop-out bubble emerges from the right screen edge,
/// dynamically tracking the finger and highlighting the target page.
/// When the user lifts their finger, it navigates directly to that selected page.
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
  late Animation<double> _bubbleScale;
  late Animation<double> _bubbleFade;

  bool _isDragging = false;
  double _currentY = 0.0;
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

    _bubbleScale = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );

    _bubbleFade = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
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
    _animCtrl.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details, double trackHeight) {
    if (widget.totalPages <= 1) return;
    setState(() {
      _isDragging = true;
      _updateDrag(details.localPosition.dy, trackHeight);
    });
    _animCtrl.forward();
    HapticFeedback.mediumImpact();
  }

  void _onDragUpdate(DragUpdateDetails details, double trackHeight) {
    if (!_isDragging || widget.totalPages <= 1) return;
    _updateDrag(details.localPosition.dy, trackHeight);
  }

  void _updateDrag(double localY, double trackHeight) {
    if (trackHeight <= 0) return;
    final clampedY = localY.clamp(0.0, trackHeight);
    final ratio = clampedY / trackHeight;
    final page = (1 + ratio * (widget.totalPages - 1)).round().clamp(1, widget.totalPages);

    if (page != _highlightedPage) {
      if (page != _lastHapticPage) {
        HapticFeedback.selectionClick();
        _lastHapticPage = page;
      }
    }

    setState(() {
      _currentY = clampedY;
      _highlightedPage = page;
    });
  }

  void _onDragEnd() {
    if (!_isDragging) return;
    final targetPage = _highlightedPage;
    setState(() {
      _isDragging = false;
    });
    _animCtrl.reverse();
    HapticFeedback.mediumImpact();
    widget.onPageSelected(targetPage);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible || widget.totalPages <= 1) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Vertical track height with comfortable safe-area padding
        final verticalMargin = 32.0;
        final trackHeight = constraints.maxHeight - (verticalMargin * 2);
        if (trackHeight <= 50) return const SizedBox.shrink();

        // Calculate thumb vertical center
        final currentRatio = widget.totalPages > 1
            ? ((_isDragging ? _highlightedPage : widget.currentPage) - 1) /
                (widget.totalPages - 1)
            : 0.0;
        final thumbY = verticalMargin + (currentRatio.clamp(0.0, 1.0) * trackHeight);

        // Clamp bubble Y so it never goes off-screen
        const bubbleHeight = 64.0;
        final bubbleTop = (thumbY - (bubbleHeight / 2))
            .clamp(verticalMargin, constraints.maxHeight - verticalMargin - bubbleHeight);

        return SizedBox(
          width: 140, // Allows popout curved bubble to project left
          height: constraints.maxHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Touch Scrubber Strip on Right Edge ──────────────────────────
              Positioned(
                right: 0,
                top: verticalMargin,
                bottom: verticalMargin,
                width: 34,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (d) => _onDragStart(d, trackHeight),
                  onVerticalDragUpdate: (d) => _onDragUpdate(d, trackHeight),
                  onVerticalDragEnd: (_) => _onDragEnd(),
                  onVerticalDragCancel: _onDragEnd,
                  onTapDown: (d) {
                    _onDragStart(
                      DragStartDetails(localPosition: d.localPosition),
                      trackHeight,
                    );
                  },
                  onTapUp: (_) => _onDragEnd(),
                  child: Center(
                    child: Container(
                      width: _isDragging ? 6 : 4,
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: _isDragging ? 0.22 : 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          // Scrubber track thumb
                          Positioned(
                            top: (thumbY - verticalMargin - 12).clamp(0.0, trackHeight - 24),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              width: _isDragging ? 8 : 6,
                              height: 24,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.65),
                                    blurRadius: _isDragging ? 12 : 6,
                                    spreadRadius: _isDragging ? 2 : 0.5,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Pop-out Curved Bubble with Target Page ──────────────────────
              Positioned(
                right: 28,
                top: bubbleTop,
                child: AnimatedBuilder(
                  animation: _animCtrl,
                  builder: (context, child) {
                    if (_animCtrl.value == 0) return const SizedBox.shrink();
                    return Transform.scale(
                      scale: _bubbleScale.value,
                      alignment: Alignment.centerRight,
                      child: Opacity(
                        opacity: _bubbleFade.value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: CustomPaint(
                    painter: _DrawerBubbleCurvedPainter(
                      color: const Color(0xFF1B1B20),
                      borderColor: AppColors.primary.withValues(alpha: 0.8),
                      glowColor: AppColors.primary.withValues(alpha: 0.4),
                    ),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 22, 8),
                      constraints: const BoxConstraints(minWidth: 96, maxHeight: bubbleHeight),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'PAGE',
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '$_highlightedPage',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '/${widget.totalPages}',
                                style: GoogleFonts.inter(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Custom painter that creates the Android Drawer curved wave / teardrop popout.
/// Curves smoothly out from the right edge with a pointer arrow toward the user's finger.
class _DrawerBubbleCurvedPainter extends CustomPainter {
  final Color color;
  final Color borderColor;
  final Color glowColor;

  _DrawerBubbleCurvedPainter({
    required this.color,
    required this.borderColor,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = 16.0; // Corner radius of bubble
    final pointerWidth = 14.0;
    final bubbleW = w - pointerWidth;
    final centerY = h / 2;

    // Path for rounded rectangle bubble with smoothly curved pointer on the right
    final path = Path();
    path.moveTo(r, 0);
    path.lineTo(bubbleW - r, 0);
    path.quadraticBezierTo(bubbleW, 0, bubbleW, r);
    path.lineTo(bubbleW, centerY - 10);
    // Smooth bezier curve tapering into right edge point
    path.quadraticBezierTo(bubbleW + 2, centerY - 4, w, centerY);
    path.quadraticBezierTo(bubbleW + 2, centerY + 4, bubbleW, centerY + 10);
    path.lineTo(bubbleW, h - r);
    path.quadraticBezierTo(bubbleW, h, bubbleW - r, h);
    path.lineTo(r, h);
    path.quadraticBezierTo(0, h, 0, h - r);
    path.lineTo(0, r);
    path.quadraticBezierTo(0, 0, r, 0);
    path.close();

    // 1. Draw glowing drop shadow
    final shadowPaint = Paint()
      ..color = glowColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawPath(path, shadowPaint);

    final darkShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(path.shift(const Offset(0, 4)), darkShadowPaint);

    // 2. Fill body
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // 3. Draw border outline
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _DrawerBubbleCurvedPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.glowColor != glowColor;
  }
}
