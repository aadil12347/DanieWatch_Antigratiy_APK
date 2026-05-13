import 'dart:async';
import 'package:flutter/material.dart';

/// Gesture states for the premium poster interaction system.
enum PosterTouchState {
  /// No interaction — card at rest.
  idle,
  /// Finger is down, waiting to determine intent (< 200ms, < 8px movement).
  pressing,
  /// User moved finger > 8px — scrolling/swiping, cancel all effects.
  dragging,
  /// User held finger stationary > 200ms — "lift" the card.
  longHolding,
}

/// Premium touch interaction handler modeled after Netflix/Apple TV+/Spotify.
///
/// Wraps a child widget and provides:
/// - Scale-down (0.97) on press
/// - Single smooth glow that fades in on touch and fades out on release
/// - NO haptic feedback (visual-only subtle effects)
/// - Clean tap navigation (only fires on stationary taps < 200ms OR on long-hold release)
/// - Scroll-aware cancellation
class PosterTouchHandler extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onLongHold;
  final Color? glowColor;
  final BorderRadius borderRadius;

  const PosterTouchHandler({
    super.key,
    required this.child,
    this.onTap,
    this.onLongHold,
    this.glowColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
  });

  @override
  State<PosterTouchHandler> createState() => PosterTouchHandlerState();
}

class PosterTouchHandlerState extends State<PosterTouchHandler>
    with TickerProviderStateMixin {
  PosterTouchState _state = PosterTouchState.idle;

  Offset? _startPosition;
  Timer? _longPressTimer;
  DateTime? _pointerDownTime;

  // Scale animation
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  // Single glow animation — one smooth fade in/out
  late AnimationController _glowController;

  // The scale values for each state
  static const double _pressScale = 0.97;
  static const double _normalScale = 1.0;

  // Movement threshold
  static const double _touchSlop = 8.0;

  // Time before transitioning to long-hold
  static const Duration _longPressDelay = Duration(milliseconds: 200);
  static const Duration _tapThreshold = Duration(seconds: 1);

  double _targetScale = _normalScale;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: _normalScale, end: _normalScale)
        .animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutCubic,
    ));

    // Single glow controller: fades in fast, fades out smoothly
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180), // fade-in
      reverseDuration: const Duration(milliseconds: 600), // fade-out — slow smooth vanish
    );
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _scaleController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  void _animateScale(double target, {Duration? duration}) {
    if (_targetScale == target) return;
    _targetScale = target;

    _scaleAnimation = Tween<double>(
      begin: _scaleAnimation.value,
      end: target,
    ).animate(CurvedAnimation(
      parent: _scaleController..duration = duration ?? const Duration(milliseconds: 150),
      curve: target > _normalScale ? Curves.easeOutBack : Curves.easeOutCubic,
    ));
    _scaleController.forward(from: 0.0);
  }

  void _showGlow() {
    _glowController.forward();
  }

  void _hideGlow() {
    _glowController.reverse();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_isScrolling) return;

    _startPosition = event.position;
    _pointerDownTime = DateTime.now();
    setState(() => _state = PosterTouchState.pressing);

    // Subtle press-down — NO haptic
    _animateScale(_pressScale);
    _showGlow();

    // Start long-press timer
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDelay, () {
      if (_state == PosterTouchState.pressing && mounted) {
        setState(() => _state = PosterTouchState.longHolding);
        widget.onLongHold?.call(true);
      }
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_state == PosterTouchState.idle || _state == PosterTouchState.dragging) return;

    final distance = (event.position - (_startPosition ?? event.position)).distance;
    if (distance > _touchSlop) {
      _longPressTimer?.cancel();
      if (_state == PosterTouchState.longHolding) {
        widget.onLongHold?.call(false);
      }
      setState(() => _state = PosterTouchState.dragging);
      _animateScale(_normalScale);
      // Keep glow on while finger is still on the card
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _longPressTimer?.cancel();

    final previousState = _state;
    final holdDuration = _pointerDownTime != null
        ? DateTime.now().difference(_pointerDownTime!)
        : Duration.zero;
    _pointerDownTime = null;

    setState(() => _state = PosterTouchState.idle);
    _animateScale(_normalScale);
    _hideGlow();

    switch (previousState) {
      case PosterTouchState.pressing:
        // Quick tap — navigate
        widget.onTap?.call();
        break;
      case PosterTouchState.longHolding:
        // Long hold release — only navigate if held < 1 second
        widget.onLongHold?.call(false);
        if (holdDuration < _tapThreshold) {
          widget.onTap?.call();
        }
        break;
      case PosterTouchState.dragging:
        // Was scrolling — do nothing
        break;
      case PosterTouchState.idle:
        break;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _longPressTimer?.cancel();
    if (_state == PosterTouchState.longHolding) {
      widget.onLongHold?.call(false);
    }
    setState(() => _state = PosterTouchState.idle);
    _animateScale(_normalScale);
    _hideGlow();
  }

  /// Called by parent scroll containers to cancel active touch states.
  void cancelTouch() {
    _longPressTimer?.cancel();
    if (_state == PosterTouchState.longHolding) {
      widget.onLongHold?.call(false);
    }
    if (_state != PosterTouchState.idle) {
      setState(() => _state = PosterTouchState.idle);
      _animateScale(_normalScale);
      _hideGlow();
    }
  }

  /// Track parent scroll state to avoid activating press during scroll.
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _isScrolling = true;
      cancelTouch();
    } else if (notification is ScrollEndNotification) {
      _isScrolling = false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final glowColor = widget.glowColor ?? Colors.white;

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: AnimatedBuilder(
          animation: Listenable.merge([_scaleAnimation, _glowController]),
          builder: (context, child) {
            final glowOpacity = _glowController.value;
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                decoration: glowOpacity > 0.01
                    ? BoxDecoration(
                        borderRadius: widget.borderRadius,
                        boxShadow: [
                          BoxShadow(
                            color: glowColor.withValues(alpha: 0.70 * glowOpacity),
                            blurRadius: 28,
                            spreadRadius: 4,
                          ),
                          BoxShadow(
                            color: glowColor.withValues(alpha: 0.35 * glowOpacity),
                            blurRadius: 32,
                            spreadRadius: 6,
                          ),
                        ],
                      )
                    : null,
                child: RepaintBoundary(child: child),
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}
