import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps any widget with a water-tap bounce effect on tap.
/// On press: quick dip down then spring up with overshoot,
/// like tapping the surface of water.
///
/// Usage:
/// ```dart
/// LiquidTapEffect(
///   onTap: () => doSomething(),
///   child: MyButton(),
/// )
/// ```
class LiquidTapEffect extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enableHaptic;
  final double intensity; // 0.0 - 1.0, controls bounce strength

  const LiquidTapEffect({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enableHaptic = true,
    this.intensity = 1.0,
  });

  @override
  State<LiquidTapEffect> createState() => _LiquidTapEffectState();
}

class _LiquidTapEffectState extends State<LiquidTapEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap() {
    _ctrl.forward(from: 0);
    if (widget.enableHaptic) {
      HapticFeedback.lightImpact();
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap != null ? _onTap : null,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = _ctrl.value;
          // Water-tap: sin(3π*t) with decay gives dip → spring → settle
          final bounce = t > 0
              ? 1.0 +
                  math.sin(t * math.pi * 3) *
                      (1.0 - t) *
                      0.18 *
                      widget.intensity
              : 1.0;
          return Transform.scale(
            scale: bounce,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
