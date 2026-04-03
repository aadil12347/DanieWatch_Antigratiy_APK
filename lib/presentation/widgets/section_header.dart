import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';

/// Section header with title, used before content rows.
class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  final Color? titleColor;
  final TextStyle? titleStyle;
  final Widget? titleWidget;
  final bool showSeeAll;

  const SectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.titleColor,
    this.titleStyle,
    this.titleWidget,
    this.showSeeAll = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: titleWidget ??
                Text(
                  title,
                  style: titleStyle ??
                      GoogleFonts.lora(
                        color: titleColor ?? AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                      ),
                ),
          ),
          const SizedBox(width: 8),
          if (showSeeAll && onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'See all',
                style: GoogleFonts.inter(
                  color: AppColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TopTenTitle extends StatelessWidget {
  const TopTenTitle({super.key});

  @override
  Widget build(BuildContext context) {
    const double fontSize = 72;
    // Premium font for Top 10
    final baseStyle = GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
    );

    // Gradient outline paint with rounded joins to fix the 'P' artifact
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0xFFE50914), // Netflix-style red
          Color(0x33B81D24), // Dimmer red
        ],
      ).createShader(const Rect.fromLTWH(0, 0, 300, 100));

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Outlined TOP 10 with manual overlapping
          SizedBox(
            height: fontSize + 15,
            width: 245,
            child: Stack(
              children: [
                _Letter('T', 0, baseStyle, outlinePaint),
                _Letter('O', 40, baseStyle, outlinePaint),
                _Letter('P', 96, baseStyle, outlinePaint), // Adjusted offset for perfect P feel
                _Letter('1', 145, baseStyle, outlinePaint),
                _Letter('0', 182, baseStyle, outlinePaint),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // CONTENT TODAY Stack
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SubText('CONTENT'),
              _SubText('TODAY'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _Letter(String char, double left, TextStyle style, Paint foreground) {
    return Positioned(
      left: left,
      top: 0,
      child: Text(
        char,
        style: style.copyWith(foreground: foreground),
      ),
    );
  }

  Widget _SubText(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 8.0,
        height: 1.2,
        color: Colors.white,
      ),
    );
  }
}
