import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'liquid_glass.dart';

/// iOS-style liquid glass button with press animation and haptic feedback.
///
/// Extends the [LiquidGlass] container with:
/// - Scale-down press animation (0.96x)
/// - Haptic feedback on tap
/// - Animated inner glow pulse on press
/// - Configurable accent color tint
class LiquidGlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;
  final GlassIntensity intensity;
  final Color? accentColor;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final bool isCircular;
  final bool enableHaptic;

  const LiquidGlassButton({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = 16,
    this.intensity = GlassIntensity.medium,
    this.accentColor,
    this.padding,
    this.width,
    this.height,
    this.isCircular = false,
    this.enableHaptic = true,
  });

  /// Convenience constructor for text-label buttons.
  factory LiquidGlassButton.label({
    Key? key,
    required String label,
    VoidCallback? onTap,
    double borderRadius = 16,
    GlassIntensity intensity = GlassIntensity.medium,
    Color? accentColor,
    EdgeInsetsGeometry? padding,
    double? width,
    double? height,
    IconData? icon,
  }) {
    return LiquidGlassButton(
      key: key,
      onTap: onTap,
      borderRadius: borderRadius,
      intensity: intensity,
      accentColor: accentColor,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      width: width,
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: accentColor ?? Colors.white, size: 18),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  State<LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _pressController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _pressController.reverse();
    if (widget.enableHaptic) {
      HapticFeedback.lightImpact();
    }
    widget.onTap?.call();
  }

  void _onTapCancel() {
    _pressController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _pressController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: LiquidGlass(
              borderRadius: widget.borderRadius,
              intensity: widget.intensity,
              tintColor: accent != null
                  ? Color.lerp(accent, accent, _glowAnimation.value)
                  : null,
              tintOpacity: accent != null
                  ? 0.08 + (_glowAnimation.value * 0.12)
                  : 0.08,
              enableAnimatedBorder: true,
              enableTouchRipple: false,
              padding: widget.padding,
              width: widget.width,
              height: widget.height,
              isCircular: widget.isCircular,
              child: child!,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Small liquid glass icon button (circular, like iOS SF Symbol buttons).
class LiquidGlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? iconColor;
  final Color? accentColor;
  final GlassIntensity intensity;
  final Widget? badge;

  const LiquidGlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 40,
    this.iconColor,
    this.accentColor,
    this.intensity = GlassIntensity.medium,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        LiquidGlassButton(
          onTap: onTap,
          borderRadius: size / 2,
          intensity: intensity,
          accentColor: accentColor,
          isCircular: true,
          padding: EdgeInsets.zero,
          width: size,
          height: size,
          child: Center(
            child: Icon(
              icon,
              color: iconColor ?? Colors.white,
              size: size * 0.45,
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            right: -4,
            top: -4,
            child: badge!,
          ),
      ],
    );
  }
}
