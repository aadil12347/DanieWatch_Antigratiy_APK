import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';

/// Liquid glass navbar — no pill, no ripple lines.
/// Active tab gets a white glow behind the icon.
/// Tapped icon does a water-drop bounce (scale wobble).
class LiquidNavBarContent extends StatefulWidget {
  final int currentIndex;
  final double navHeight;
  final double tabWidth;
  final double iconSize;
  final double labelSize;
  final double horizontalPad;
  final ValueChanged<int> onTap;

  const LiquidNavBarContent({
    super.key,
    required this.currentIndex,
    required this.navHeight,
    required this.tabWidth,
    required this.iconSize,
    required this.labelSize,
    required this.horizontalPad,
    required this.onTap,
  });

  @override
  State<LiquidNavBarContent> createState() => _LiquidNavBarContentState();
}

class _LiquidNavBarContentState extends State<LiquidNavBarContent>
    with TickerProviderStateMixin {
  // Per-tab glow controllers
  final List<AnimationController> _glowCtrls = [];
  // Per-tab water-tap bounce controllers
  final List<AnimationController> _bounceCtrls = [];

  static const _icons = [
    Icons.home_outlined,
    Icons.search_outlined,
    Icons.bookmark_outline_rounded,
    Icons.download_outlined,
  ];
  static const _activeIcons = [
    Icons.home_rounded,
    Icons.search_rounded,
    Icons.bookmark_rounded,
    Icons.download_rounded,
  ];
  static const _labels = ['Home', 'Explore', 'Favourite', 'Downloads'];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 4; i++) {
      final glow = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 350),
      );
      if (i == widget.currentIndex) glow.value = 1.0;
      _glowCtrls.add(glow);

      _bounceCtrls.add(AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ));
    }
  }

  @override
  void didUpdateWidget(covariant LiquidNavBarContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _glowCtrls[oldWidget.currentIndex].reverse();
      _glowCtrls[widget.currentIndex].forward();
      _bounceCtrls[widget.currentIndex].forward(from: 0);
    }
  }

  @override
  void dispose() {
    for (final c in _glowCtrls) {
      c.dispose();
    }
    for (final c in _bounceCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _handleTap(int index) {
    HapticFeedback.selectionClick();
    widget.onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.navHeight,
      child: AnimatedBuilder(
        animation: Listenable.merge([..._glowCtrls, ..._bounceCtrls]),
        builder: (context, _) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.horizontalPad),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(4, (i) => _buildTab(i)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTab(int index) {
    final isSelected = widget.currentIndex == index;
    final glowValue = _glowCtrls[index].value;
    final bounceVal = _bounceCtrls[index].value;

    // Water-tap bounce: quick dip down then spring up with overshoot
    // sin(t * 3pi) gives: down → up → settle
    final bounce = bounceVal > 0
        ? 1.0 + math.sin(bounceVal * math.pi * 3) * (1.0 - bounceVal) * 0.12
        : 1.0;

    return Expanded(
      child: GestureDetector(
        onTap: () => _handleTap(index),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: widget.navHeight,
          child: Transform.scale(
            scale: bounce,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon with glow behind it — glow is painted via
                // boxShadow on an empty container, positioned so it
                // doesn't affect layout.
                SizedBox(
                  width: widget.iconSize,
                  height: widget.iconSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      if (glowValue > 0)
                        Positioned.fill(
                          child: Center(
                            child: Container(
                              width: widget.iconSize * 2,
                              height: widget.iconSize * 2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(
                                        alpha: 0.50 * glowValue),
                                    blurRadius: 22 * glowValue,
                                    spreadRadius: 6 * glowValue,
                                  ),
                                  BoxShadow(
                                    color: Colors.white.withValues(
                                        alpha: 0.18 * glowValue),
                                    blurRadius: 38 * glowValue,
                                    spreadRadius: 12 * glowValue,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Icon(
                        isSelected ? _activeIcons[index] : _icons[index],
                        color: isSelected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.45),
                        size: widget.iconSize,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _labels[index],
                  maxLines: 1,
                  style: GoogleFonts.inter(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.40),
                    fontSize: widget.labelSize,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
