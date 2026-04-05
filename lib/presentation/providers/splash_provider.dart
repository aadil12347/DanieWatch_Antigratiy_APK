import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/clients/tmdb_client.dart';

/// Provides a list of unique trending poster URLs from TMDB for the splash screen
final trendingPostersProvider = FutureProvider<List<String>>((ref) async {
  try {
    // Fetch trending movies and TV shows for today
    final results = await Future.wait([
      TmdbClient.instance.getTrending('movie', timeWindow: 'day'),
      TmdbClient.instance.getTrending('tv', timeWindow: 'day'),
    ]);

    final allItems = [...results[0], ...results[1]];
    
    // Shuffle for variety
    allItems.shuffle();

    // Extract poster URLs and filter out nulls/empties
    final posters = allItems
        .map((item) => item['poster_path'] as String?)
        .where((path) => path != null && path.isNotEmpty)
        .map((path) => TmdbClient.posterUrl(path, size: 'w342'))
        .toSet() // Ensure uniqueness
        .toList();

    // If we have very few posters, fallback or fetch more pages (unlikely for trending)
    return posters;
  } catch (e) {
    return []; // Fallback to empty, UI should handle this
  }
});
