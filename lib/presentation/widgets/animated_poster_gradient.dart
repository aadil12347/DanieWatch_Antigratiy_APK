import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/services/poster_color_service.dart';

/// Cinematic 3-color animated gradient with subtle breathing movement.
class AnimatedPosterGradient extends StatefulWidget {
  final PosterColorPalette palette;
  final Duration duration;
  final double opacity;

  const AnimatedPosterGradient({
    super.key,
    required this.palette,
    this.duration = const Duration(milliseconds: 800),
    this.opacity = 1.0,
  });

  @override
  State<AnimatedPosterGradient> createState() => _AnimatedPosterGradientState();
}

class _AnimatedPosterGradientState extends State<AnimatedPosterGradient>
    with TickerProviderStateMixin {
  late AnimationController _colorController;
  late Animation<double> _colorCurve;
  late AnimationController _breatheController;

  late ColorTween _primaryTween;
  late ColorTween _secondaryTween;
  late ColorTween _tertiaryTween;

  PosterColorPalette _currentPalette = PosterColorPalette.fallback;

  @override
  void initState() {
    super.initState();

    _colorController = AnimationController(vsync: this, duration: widget.duration);
    _colorCurve = CurvedAnimation(parent: _colorController, curve: Curves.easeInOut);

    _currentPalette = widget.palette;
    _primaryTween = ColorTween(begin: widget.palette.primary, end: widget.palette.primary);
    _secondaryTween = ColorTween(begin: widget.palette.secondary, end: widget.palette.secondary);
    _tertiaryTween = ColorTween(begin: widget.palette.tertiary, end: widget.palette.tertiary);

    // Slow breathing animation — makes gradient feel alive
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(AnimatedPosterGradient oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.palette != widget.palette) {
      _primaryTween = ColorTween(
        begin: _primaryTween.evaluate(_colorCurve) ?? _currentPalette.primary,
        end: widget.palette.primary,
      );
      _secondaryTween = ColorTween(
        begin: _secondaryTween.evaluate(_colorCurve) ?? _currentPalette.secondary,
        end: widget.palette.secondary,
      );
      _tertiaryTween = ColorTween(
        begin: _tertiaryTween.evaluate(_colorCurve) ?? _currentPalette.tertiary,
        end: widget.palette.tertiary,
      );
      _currentPalette = widget.palette;
      _colorController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _colorController.dispose();
    _breatheController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_colorCurve, _breatheController]),
      builder: (context, _) {
        final p = _primaryTween.evaluate(_colorCurve) ?? _currentPalette.primary;
        final s = _secondaryTween.evaluate(_colorCurve) ?? _currentPalette.secondary;
        final t = _tertiaryTween.evaluate(_colorCurve) ?? _currentPalette.tertiary;

        // Breathing — subtle alignment shift
        final b = _breatheController.value;
        final beginX = -0.3 + (b * 0.2);
        final beginY = -1.0 + (b * 0.15);

        return Opacity(
          opacity: widget.opacity,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(beginX, beginY),
                end: Alignment(-beginX * 0.4, 1.0 - (b * 0.1)),
                colors: [p, s, t, const Color(0xFF0A0A0A)],
                stops: const [0.0, 0.3, 0.6, 1.0],
              ),
            ),
          ),
        );
      },
    );
  }
}
