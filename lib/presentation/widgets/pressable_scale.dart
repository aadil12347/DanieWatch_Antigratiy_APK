import 'package:flutter/material.dart';

/// A reusable wrapper that applies a subtle press-and-hold scale effect.
///
/// On pointer down: animates to [pressedScale] (default 0.97).
/// Stays pinched while the finger is held down.
/// On pointer up / cancel: smoothly animates back to 1.0.
///
/// This mirrors the premium touch feel of [PosterTouchHandler] but without
/// glow effects — suitable for notification cards, episode cards, etc.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final Duration animateDownDuration;
  final Duration animateUpDuration;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
    this.animateDownDuration = const Duration(milliseconds: 120),
    this.animateUpDuration = const Duration(milliseconds: 180),
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  bool _isPressed = false;
  Offset? _startPosition;
  static const double _touchSlop = 10.0;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animateDownDuration,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target, {Duration? duration}) {
    _scaleAnimation = Tween<double>(
      begin: _scaleAnimation.value,
      end: target,
    ).animate(CurvedAnimation(
      parent: _controller..duration = duration ?? widget.animateDownDuration,
      curve: Curves.easeOutCubic,
    ));
    _controller.forward(from: 0.0);
  }

  void _onPointerDown(PointerDownEvent event) {
    _startPosition = event.position;
    _cancelled = false;
    setState(() => _isPressed = true);
    _animateTo(widget.pressedScale, duration: widget.animateDownDuration);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_cancelled) return;
    final distance =
        (event.position - (_startPosition ?? event.position)).distance;
    if (distance > _touchSlop) {
      // User is scrolling — mark cancelled so onTap won't fire,
      // but keep the card pinched until finger lifts
      _cancelled = true;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final wasPressedClean = _isPressed && !_cancelled;
    setState(() => _isPressed = false);
    _animateTo(1.0, duration: widget.animateUpDuration);
    if (wasPressedClean) {
      widget.onTap?.call();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    setState(() => _isPressed = false);
    _animateTo(1.0, duration: widget.animateUpDuration);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
