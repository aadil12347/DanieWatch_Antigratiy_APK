import 'package:flutter/material.dart';
import '../../domain/models/manifest_item.dart';
import '../../core/utils/responsive.dart';
import 'movie_card.dart';

/// Horizontal scrolling content row used on home screen.
class ContentRow extends StatelessWidget {
  final List<ManifestItem> items;
  final bool isRanked;

  const ContentRow({
    super.key,
    required this.items,
    this.isRanked = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);
    final rowHeight = r.h(265).clamp(200.0, 340.0);
    final cardWidth = r.w(145).clamp(110.0, 190.0);
    final leftPad = isRanked ? r.w(48).clamp(36.0, 64.0) : r.w(16).clamp(12.0, 24.0);
    final rightPad = r.w(16).clamp(12.0, 24.0);
    final spacing = isRanked ? r.w(42).clamp(30.0, 56.0) : r.w(12).clamp(8.0, 18.0);

    return SizedBox(
      height: rowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          left: leftPad,
          right: rightPad,
        ),
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: spacing),
        itemBuilder: (context, index) {
          return MovieCard(
            item: items[index],
            width: cardWidth,
            height: rowHeight,
            rank: isRanked ? index + 1 : null,
          );
        },
      ),
    );
  }
}
