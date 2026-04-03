import 'package:flutter/material.dart';
import '../../domain/models/manifest_item.dart';
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
    return SizedBox(
      height: 265,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const AlwaysScrollableScrollPhysics(),
        // Extra left padding to make room for the first item's rank number
        padding: EdgeInsets.only(
          left: isRanked ? 48.0 : 16.0,
          right: 16.0,
        ),
        itemCount: items.length,
        // Increased spacing between ranked items for better clarity
        separatorBuilder: (_, __) => SizedBox(width: isRanked ? 42.0 : 12.0),
        itemBuilder: (context, index) {
          return MovieCard(
            item: items[index],
            width: 145,
            height: 265,
            rank: isRanked ? index + 1 : null,
          );
        },
      ),
    );
  }
}
