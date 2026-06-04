import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// A custom [Decoration] that draws an animated glowing underline
/// using the app's primary red colour (AppColors.primary).
///
/// The glow is achieved by applying a [MaskFilter.blur] to the
/// underline paint, creating a soft halo around the line. The
/// thickness and inset can be tweaked via the constructor.
class UnderlineGlowIndicator extends Decoration {
  const UnderlineGlowIndicator({this.thickness = 4.0, this.inset = 4.0});

  /// Height of the underline line.
  final double thickness;

  /// Distance from the bottom edge of the tab to the line.
  final double inset;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _GlowPainter(this, onChanged);
}

class _GlowPainter extends BoxPainter {
  _GlowPainter(this.decoration, VoidCallback? onChanged) : super(onChanged);

  final UnderlineGlowIndicator decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final Rect rect = offset & configuration.size!;
    
    // Create a subtle glow layer
    final Paint glowPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.6)
      ..strokeWidth = decoration.thickness * 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Create the crisp inner line layer
    final Paint linePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = decoration.thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Draw a horizontal line near the bottom of the tab.
    final double y = rect.bottom - decoration.inset;
    
    // Added a tiny padding so round caps don't bleed too far out of label
    final double padding = 2.0;
    final Offset startPoint = Offset(rect.left + padding, y);
    final Offset endPoint = Offset(rect.right - padding, y);

    canvas.save();
    // Clip exactly at the bottom bound of the solid line so no blur bleeds down.
    canvas.clipRect(Rect.fromLTRB(
      rect.left - 20,
      rect.top - 20,
      rect.right + 20,
      y + (decoration.thickness / 2),
    ));

    // Shift glow slightly up to emphasize the upward bloom
    final Offset glowStart = Offset(rect.left + padding, y - 2.0);
    final Offset glowEnd = Offset(rect.right - padding, y - 2.0);
    canvas.drawLine(glowStart, glowEnd, glowPaint);
    canvas.restore();

    canvas.drawLine(startPoint, endPoint, linePaint);
  }
}
