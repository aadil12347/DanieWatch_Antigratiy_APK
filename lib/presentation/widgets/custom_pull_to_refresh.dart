import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

/// Premium pull-to-refresh widget with:
/// - No page content movement (static page)
/// - Overlay-based indicator (renders ABOVE everything including the top navbar)
/// - Stretchy elastic pull feel
/// - Spring-back animation on release
/// - Pulsing/rotating loader during refresh
/// - Haptic feedback at trigger threshold
class CustomPullToRefresh extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final double triggerThreshold;

  const CustomPullToRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.triggerThreshold = 100.0,
  });

  @override
  State<CustomPullToRefresh> createState() => _CustomPullToRefreshState();
}

class _CustomPullToRefreshState extends State<CustomPullToRefresh>
    with TickerProviderStateMixin {
  double _dragOffset = 0.0;
  bool _isRefreshing = false;
  bool _hasTriggeredHaptic = false;
  OverlayEntry? _overlayEntry;

  late AnimationController _springController;
  late AnimationController _rotationController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _springController.addListener(_onSpringUpdate);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _springController.dispose();
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onSpringUpdate() {
    if (!_isRefreshing) {
      _dragOffset = _springController.value * _dragOffset;
      if (_springController.isCompleted) {
        _dragOffset = 0;
        _removeOverlay();
      }
    }
    _updateOverlay();
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(
      builder: (context) => _buildIndicatorOverlay(),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _updateOverlay() {
    _overlayEntry?.markNeedsBuild();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_isRefreshing) return false;

    if (notification is ScrollUpdateNotification) {
      if (notification.metrics.axis == Axis.vertical) {
        if (notification.metrics.pixels < 0) {
          // Native overscroll (BouncingScrollPhysics)
          final rawOffset = -notification.metrics.pixels;
          _dragOffset = _applyFriction(rawOffset);
          _showOverlay();
          _updateOverlay();
          _checkHaptic();
        } else if (_dragOffset > 0 && !_isRefreshing) {
          _dragOffset = 0;
          _updateOverlay();
        }
      }
    } else if (notification is OverscrollNotification &&
        notification.overscroll < 0) {
      // Clamp physics fallback
      _dragOffset += (-notification.overscroll) * 0.5;
      _dragOffset = _applyFriction(_dragOffset);
      _showOverlay();
      _updateOverlay();
      _checkHaptic();
    } else if (notification is ScrollEndNotification ||
        notification is UserScrollNotification) {
      if (notification is UserScrollNotification &&
          notification.direction != ScrollDirection.idle) {
        return false;
      }

      if (!_isRefreshing && _dragOffset > 0) {
        if (_dragOffset >= widget.triggerThreshold) {
          _triggerRefresh();
        } else {
          _animateToZero();
        }
      }
    }
    return false;
  }

  double _applyFriction(double rawOffset) {
    // Rubber-band friction: decelerates as you pull further
    final maxPull = widget.triggerThreshold * 2.5;
    final t = (rawOffset / maxPull).clamp(0.0, 1.0);
    return maxPull * (1 - math.pow(1 - t, 2));
  }

  void _checkHaptic() {
    if (_dragOffset >= widget.triggerThreshold && !_hasTriggeredHaptic) {
      _hasTriggeredHaptic = true;
      HapticFeedback.mediumImpact();
    } else if (_dragOffset < widget.triggerThreshold) {
      _hasTriggeredHaptic = false;
    }
  }

  void _triggerRefresh() async {
    _isRefreshing = true;

    // Animate to the fixed "refreshing" height
    _springController.stop();

    // Start the spinning and pulsing animations
    _rotationController.repeat();
    _pulseController.repeat(reverse: true);
    _updateOverlay();

    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        _isRefreshing = false;
        _hasTriggeredHaptic = false;
        _rotationController.stop();
        _pulseController.stop();
        _animateToZero();
      }
    }
  }

  void _animateToZero() {
    final startOffset = _dragOffset;
    final animation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _springController,
        curve: Curves.elasticOut,
      ),
    );

    void listener() {
      _dragOffset = startOffset * animation.value;
      if (_springController.isCompleted) {
        _dragOffset = 0;
        _removeOverlay();
        _springController.removeListener(listener);
      }
      _updateOverlay();
    }

    _springController.removeListener(_onSpringUpdate);
    _springController.addListener(listener);
    _springController.forward(from: 0);
  }

  Widget _buildIndicatorOverlay() {
    final progress = (_dragOffset / widget.triggerThreshold).clamp(0.0, 1.0);
    final displayHeight = _dragOffset.clamp(0.0, widget.triggerThreshold * 1.5);
    final isReady = _dragOffset >= widget.triggerThreshold;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge([_rotationController, _pulseController]),
          builder: (context, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Stretchy background shape
                CustomPaint(
                  size: Size(MediaQuery.of(context).size.width, displayHeight),
                  painter: _StretchyPainter(
                    progress: progress,
                    color: AppColors.primary.withValues(alpha: 0.08 * progress),
                  ),
                ),
                // The indicator circle
                if (displayHeight > 10)
                  Transform.translate(
                    offset: Offset(0, -(displayHeight * 0.3).clamp(0.0, 50.0)),
                    child: _buildIndicatorCircle(progress, isReady),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildIndicatorCircle(double progress, bool isReady) {
    final scale = Curves.easeOutBack.transform(progress.clamp(0.0, 1.0));
    final pulseScale =
        _isRefreshing ? 1.0 + (_pulseController.value * 0.1) : 1.0;

    return Transform.scale(
      scale: scale * pulseScale,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary
                  .withValues(alpha: isReady || _isRefreshing ? 0.4 : 0.1),
              blurRadius: isReady || _isRefreshing ? 20 : 8,
              spreadRadius: isReady || _isRefreshing ? 2 : 0,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: AppColors.primary
                .withValues(alpha: isReady || _isRefreshing ? 0.6 : 0.2),
            width: 2,
          ),
        ),
        child: _isRefreshing
            ? _buildRefreshingContent()
            : _buildPullContent(progress, isReady),
      ),
    );
  }

  Widget _buildPullContent(double progress, bool isReady) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Progress arc
        SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 2.5,
            backgroundColor: AppColors.textMuted.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(
              isReady
                  ? AppColors.primary
                  : AppColors.textMuted.withValues(alpha: 0.5),
            ),
          ),
        ),
        // Arrow icon that rotates to indicate readiness
        Transform.rotate(
          angle: progress * 2 * math.pi,
          child: Icon(
            isReady
                ? Icons.arrow_downward_rounded
                : Icons.arrow_downward_rounded,
            color: isReady ? AppColors.primary : AppColors.textMuted,
            size: 18,
          ),
        ),
      ],
    );
  }

  Widget _buildRefreshingContent() {
    return Transform.rotate(
      angle: _rotationController.value * 2 * math.pi,
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppColors.primary,
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: widget.child,
    );
  }
}

/// Custom painter for the stretchy elastic background shape
class _StretchyPainter extends CustomPainter {
  final double progress;
  final Color color;

  _StretchyPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height * 0.6);
    // Bezier curve for stretchy effect
    path.quadraticBezierTo(
      size.width / 2,
      size.height * 1.2,
      0,
      size.height * 0.6,
    );
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_StretchyPainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}
