import 'package:flutter/material.dart';
import '../../core/services/poster_color_service.dart';
import '../../core/theme/app_theme.dart';

/// A cinematic animated gradient background driven by a [PosterColorPalette].
///
/// Smoothly transitions between palettes using [ColorTween] animations.
/// Designed to sit behind content as a Stack layer.
class AnimatedPosterGradient extends StatefulWidget {
  final PosterColorPalette palette;
  final Duration duration;
  final double opacity;
  /// If true, the gradient covers the full height. If false, it fades out
  /// at roughly 45% height (for home page use).
  final bool fullHeight;

  const AnimatedPosterGradient({
    super.key,
    required this.palette,
    this.duration = const Duration(milliseconds: 800),
    this.opacity = 1.0,
    this.fullHeight = true,
  });

  @override
  State<AnimatedPosterGradient> createState() => _AnimatedPosterGradientState();
}

class _AnimatedPosterGradientState extends State<AnimatedPosterGradient>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late ColorTween _dominantTween;
  late ColorTween _accentTween;
  late ColorTween _mutedTween;
  late Animation<double> _curvedAnimation;

  PosterColorPalette _currentPalette = PosterColorPalette.fallback;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _curvedAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _currentPalette = widget.palette;
    _dominantTween = ColorTween(
      begin: widget.palette.dominant,
      end: widget.palette.dominant,
    );
    _accentTween = ColorTween(
      begin: widget.palette.accent,
      end: widget.palette.accent,
    );
    _mutedTween = ColorTween(
      begin: widget.palette.muted,
      end: widget.palette.muted,
    );
  }

  @override
  void didUpdateWidget(AnimatedPosterGradient oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.palette != widget.palette) {
      _dominantTween = ColorTween(
        begin: _dominantTween.evaluate(_curvedAnimation) ?? _currentPalette.dominant,
        end: widget.palette.dominant,
      );
      _accentTween = ColorTween(
        begin: _accentTween.evaluate(_curvedAnimation) ?? _currentPalette.accent,
        end: widget.palette.accent,
      );
      _mutedTween = ColorTween(
        begin: _mutedTween.evaluate(_curvedAnimation) ?? _currentPalette.muted,
        end: widget.palette.muted,
      );
      _currentPalette = widget.palette;
      _controller.forward(from: 0.0);
    }

    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curvedAnimation,
      builder: (context, _) {
        final dominant = _dominantTween.evaluate(_curvedAnimation) ??
            _currentPalette.dominant;
        final accent = _accentTween.evaluate(_curvedAnimation) ??
            _currentPalette.accent;
        final muted = _mutedTween.evaluate(_curvedAnimation) ??
            _currentPalette.muted;

        return AnimatedOpacity(
          duration: const Duration(milliseconds: 400),
          opacity: widget.opacity,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: widget.fullHeight
                    ? Alignment.bottomCenter
                    : const Alignment(0.0, 0.4),
                colors: [
                  dominant.withValues(alpha: 0.7),
                  accent.withValues(alpha: 0.4),
                  muted.withValues(alpha: 0.2),
                  AppColors.background,
                ],
                stops: widget.fullHeight
                    ? const [0.0, 0.3, 0.6, 1.0]
                    : const [0.0, 0.25, 0.5, 1.0],
              ),
            ),
          ),
        );
      },
    );
  }
}
