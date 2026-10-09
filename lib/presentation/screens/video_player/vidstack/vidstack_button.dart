import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'vidstack_theme.dart';

/// Vidstack Spring-Scale Interactive Icon Button.
/// Matches Vidstack's tactile micro-animation and touch physics.
class VidstackButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool isActive;
  final bool isCircle;
  final double size;
  final Color? backgroundColor;
  final Color? activeBackgroundColor;
  final Border? border;
  final EdgeInsetsGeometry padding;
  final bool triggerOnTapDown;

  const VidstackButton({
    super.key,
    required this.child,
    required this.onTap,
    this.tooltip,
    this.isActive = false,
    this.isCircle = false,
    this.size = 38.0,
    this.backgroundColor,
    this.activeBackgroundColor,
    this.border,
    this.padding = EdgeInsets.zero,
    this.triggerOnTapDown = false,
  });

  @override
  State<VidstackButton> createState() => _VidstackButtonState();
}

class _VidstackButtonState extends State<VidstackButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.14).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    if (widget.onTap == null) return;
    _controller.forward(from: 0.0);
    if (widget.triggerOnTapDown) {
      widget.onTap?.call();
    }
  }

  void _handleTapUp(TapUpDetails _) {
    if (widget.onTap == null) return;
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _controller.reverse();
    });
    if (!widget.triggerOnTapDown) {
      widget.onTap?.call();
    }
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBg = widget.isActive
        ? (widget.activeBackgroundColor ?? VidstackTheme.brandSubtle)
        : (widget.backgroundColor ?? Colors.transparent);

    final effectiveBorder = widget.border ??
        (widget.isActive
            ? Border.all(color: VidstackTheme.brand.withValues(alpha: 0.45), width: 1.0)
            : null);

    Widget content = AnimatedContainer(
      duration: VidstackTheme.fastAnim,
      curve: Curves.easeOutCubic,
      width: widget.size,
      height: widget.size,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: effectiveBg,
        shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: widget.isCircle ? null : BorderRadius.circular(VidstackTheme.buttonRadius),
        border: effectiveBorder,
      ),
      alignment: Alignment.center,
      child: widget.child,
    );

    if (widget.tooltip != null) {
      content = Tooltip(
        message: widget.tooltip!,
        preferBelow: false,
        decoration: BoxDecoration(
          color: VidstackTheme.surfaceElevate,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: VidstackTheme.borderSubtle),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        child: content,
      );
    }

    final scaledContent = AnimatedScale(
      scale: widget.isActive ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      child: ScaleTransition(
        scale: _scale,
        child: content,
      ),
    );

    // If triggerOnTapDown is enabled, bypass gesture arena delays and cancellations completely
    // using a raw pointer Listener so every single repeated click (even 10+ clicks per second)
    // executes instantaneously at 0ms latency without dropping any taps.
    if (widget.triggerOnTapDown) {
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          if (widget.onTap == null) return;
          _controller.forward(from: 0.0);
          widget.onTap?.call();
        },
        onPointerUp: (_) {
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) _controller.reverse();
          });
        },
        onPointerCancel: (_) {
          _controller.reverse();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // Absorb gesture in the arena to prevent bubbling to parent overlay toggleControls
          },
          child: scaledContent,
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: scaledContent,
    );
  }
}
