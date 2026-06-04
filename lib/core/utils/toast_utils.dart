import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui';

import '../theme/app_theme.dart';

enum ToastType { success, error, info, warning }

class CustomToast {
  static OverlayEntry? _currentEntry;
  static Timer? _autoDismissTimer;

  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 1000),
  }) {
    // 1. Instantly dismiss any existing toast
    dismiss();

    final overlay = Overlay.of(context);
    
    IconData getIcon() {
      if (icon != null) return icon;
      switch (type) {
        case ToastType.success: return Icons.check_circle_outline;
        case ToastType.error: return Icons.error_outline;
        case ToastType.warning: return Icons.warning_amber_rounded;
        case ToastType.info: return Icons.info_outline_rounded;
      }
    }

    Color getColor() {
      switch (type) {
        case ToastType.success: return Colors.green;
        case ToastType.error: return Colors.redAccent;
        case ToastType.warning: return Colors.orangeAccent;
        case ToastType.info: return AppColors.primary;
      }
    }

    _currentEntry = OverlayEntry(
      builder: (context) {
        return _ToastWidget(
          message: message,
          icon: getIcon(),
          color: getColor(),
          duration: duration,
          onDismiss: () {
            _currentEntry?.remove();
            _currentEntry = null;
          },
        );
      },
    );

    overlay.insert(_currentEntry!);
  }

  static void dismiss() {
    if (_currentEntry != null) {
      _currentEntry!.remove();
      _currentEntry = null;
    }
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color color;
  final Duration duration;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.icon,
    required this.color,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  Timer? _timer;

  // Gesture state
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  double _opacity = 1.0;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // End at 12px from safe area top, start at -100
    _slideAnimation = Tween<double>(begin: -100, end: 12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();

    _timer = Timer(widget.duration, () => _dismiss());
  }

  void _dismiss({bool fast = false}) {
    if (mounted) {
      if (_isDragging) return; // Don't auto-dismiss while dragging
      
      // Speed up if "fast" dismissal requested (e.g., when new toast is incoming)
      _controller.duration = Duration(milliseconds: fast ? 150 : 300);
      _controller.reverse().then((_) {
        widget.onDismiss();
      });
    } else {
      widget.onDismiss();
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      _dragOffset += details.delta;

      // Prevent downward movement (dy should be <= 0)
      if (_dragOffset.dy > 0) {
        _dragOffset = Offset(_dragOffset.dx, 0);
      }

      // Calculate opacity and scale based on distance
      final distance = _dragOffset.distance;
      _opacity = (1.0 - (distance / 200)).clamp(0.0, 1.0);
      _scale = (1.0 - (distance / 1000)).clamp(0.8, 1.0);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    final speed = velocity.distance;
    final distance = _dragOffset.distance;

    // Dismiss if swiped fast or dragged far enough
    final isDismissGesture =
        (speed > 500 || distance > 100) && _dragOffset.dy < 50;

    if (isDismissGesture) {
      widget.onDismiss();
    } else {
      // Snap back
      setState(() {
        _dragOffset = Offset.zero;
        _isDragging = false;
        _opacity = 1.0;
        _scale = 1.0;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        return Positioned(
          top: _slideAnimation.value + _dragOffset.dy,
          left: 16 + _dragOffset.dx,
          right: 16 - _dragOffset.dx,
          child: SafeArea(
            child: Opacity(
              opacity: _opacity,
              child: Transform.scale(
                scale: _scale,
                child: Center(child: child),
              ),
            ),
          ),
        );
      },
      child: GestureDetector(
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: IntrinsicWidth(
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.85,
                minHeight: 48,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.icon, color: widget.color, size: 24),
                        const SizedBox(width: 14),
                        Flexible(
                          child: Text(
                            widget.message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
