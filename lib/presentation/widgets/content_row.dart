import 'package:flutter/material.dart';
import '../../domain/models/manifest_item.dart';
import 'movie_card.dart';

/// Horizontal scrolling content row used on home screen.
class ContentRow extends StatelessWidget {
  final List<ManifestItem> items;

  const ContentRow({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return MovieCard(
            item: items[index],
            width: 130,
            height: 200,
          );
        },
      ),
    );
  }
}
