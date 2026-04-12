import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../../data/clients/tmdb_client.dart';

/// Provides a list of unique trending poster URLs from TMDB for the splash screen
final trendingPostersProvider = FutureProvider<List<String>>((ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final cachedPostersString = prefs.getString('cached_splash_posters');
    
    if (cachedPostersString != null && cachedPostersString.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(cachedPostersString);
        final cachedPosters = decoded.cast<String>();
        if (cachedPosters.isNotEmpty) {
          return cachedPosters;
        }
      } catch (e) {
        // Fallback to fetch if decode fails
      }
    }

    // If cache missed, fetch first time and save
    final fetchedPosters = await fetchAndCachePosters();
    return fetchedPosters;
  } catch (e) {
    return []; // Fallback to empty, UI should handle this
  }
});

/// Fetches new posters and caches them in SharedPreferences. 
/// Called in background after reaching homepage.
Future<List<String>> fetchAndCachePosters() async {
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

    if (posters.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_splash_posters', jsonEncode(posters));

      // Pre-cache actual images to disk for the next splash launch
      for (final url in posters) {
        try {
          DefaultCacheManager().downloadFile(url).catchError((_) {
            // Ignore pre-cache errors
            return DefaultCacheManager().getFileFromMemory(url);
          });
        } catch (_) {}
      }
    }

    return posters;
  } catch (e) {
    return [];
  }
}
