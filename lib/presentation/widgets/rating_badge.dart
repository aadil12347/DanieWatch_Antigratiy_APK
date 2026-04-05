import 'package:flutter/material.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';

/// Rating badge showing star icon and vote average with color coding.
class RatingBadge extends StatelessWidget {
  final double rating;
  final double? fontSize;

  const RatingBadge({
    super.key,
    required this.rating,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    if (rating <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _ratingColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _ratingColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 14, color: _ratingColor),
          const SizedBox(width: 3),
          Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
              color: _ratingColor,
              fontSize: fontSize ?? 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  Color get _ratingColor {
    if (rating >= 7.0) return AppColors.ratingHigh;
    if (rating >= 5.0) return AppColors.ratingMid;
    return AppColors.ratingLow;
  }
}
