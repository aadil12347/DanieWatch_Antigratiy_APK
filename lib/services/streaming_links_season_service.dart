import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'vcloud_extractor.dart';

/// Parses the streaming links JSON to extract available seasons and episode numbers.
/// Returns a `Map<int, List<int>>` — seasonNumber to sorted list of episode numbers.
class StreamingLinksSeasonService {
  static final StreamingLinksSeasonService _instance =
      StreamingLinksSeasonService._internal();
  factory StreamingLinksSeasonService() => _instance;
  StreamingLinksSeasonService._internal();

  // Cache: tmdbId → season map
  final Map<int, Map<int, List<int>>> _cache = {};

  /// Fetches the streaming JSON and extracts available seasons & episodes.
  /// Returns empty map if no JSON found or no seasons in it.
  Future<Map<int, List<int>>> fetchAvailableSeasons({
    required int tmdbId,
    required String mediaType,
    required String title,
  }) async {
    // Return from cache if available
    if (_cache.containsKey(tmdbId)) {
      return _cache[tmdbId]!;
    }

    // Only series have seasons
    if (mediaType == 'movie') {
      _cache[tmdbId] = {};
      return {};
    }

    try {
      final jsonUrl = await VcloudExtractorService().getStreamJsonUrl(
        tmdbId: tmdbId,
        mediaType: mediaType,
        title: title,
      );

      if (jsonUrl == null) {
        debugPrint('[StreamingSeasons] No streaming JSON found for tmdbId: $tmdbId');
        _cache[tmdbId] = {};
        return {};
      }

      final response = await http
          .get(Uri.parse(jsonUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('[StreamingSeasons] Failed to fetch JSON: ${response.statusCode}');
        _cache[tmdbId] = {};
        return {};
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final result = _parseSeasons(data);

      _cache[tmdbId] = result;
      debugPrint('[StreamingSeasons] Parsed seasons for tmdbId $tmdbId: ${result.keys.map((k) => 'S$k(${result[k]!.length} eps)').join(', ')}');
      return result;
    } catch (e) {
      debugPrint('[StreamingSeasons] Error fetching seasons: $e');
      _cache[tmdbId] = {};
      return {};
    }
  }

  /// Parses the streaming JSON data to extract season→episode map.
  ///
  /// JSON structure:
  /// ```json
  /// {
  ///   "seasons": {
  ///     "01": {
  ///       "480p": [{"episode_title": "Episode 01", "link": "..."}, ...],
  ///       "720p": [...]
  ///     },
  ///     "03": { ... }
  ///   }
  /// }
  /// ```
  Map<int, List<int>> _parseSeasons(Map<String, dynamic> data) {
    final Map<int, List<int>> seasonMap = {};

    final seasons = data['seasons'] as Map<String, dynamic>?;
    if (seasons == null || seasons.isEmpty) {
      return seasonMap;
    }

    for (final seasonKey in seasons.keys) {
      // Season key can be "01", "1", "03", etc.
      final seasonNum = int.tryParse(seasonKey);
      if (seasonNum == null) continue;

      final seasonData = seasons[seasonKey] as Map<String, dynamic>?;
      if (seasonData == null) continue;

      final Set<int> episodeNumbers = {};

      // Iterate all resolution keys (480p, 720p, 1080p, etc.)
      for (final resKey in seasonData.keys) {
        final items = seasonData[resKey] as List<dynamic>?;
        if (items == null) continue;

        for (final item in items) {
          if (item is! Map<String, dynamic>) continue;
          final episodeTitle = item['episode_title']?.toString() ?? '';

          // Extract episode number from title like "Episode 01", "Episode 1", etc.
          final epMatch = RegExp(r'Episode\s*(\d+)', caseSensitive: false)
              .firstMatch(episodeTitle);
          if (epMatch != null) {
            final epNum = int.tryParse(epMatch.group(1)!);
            if (epNum != null) {
              episodeNumbers.add(epNum);
            }
          }
        }
      }

      if (episodeNumbers.isNotEmpty) {
        final sorted = episodeNumbers.toList()..sort();
        seasonMap[seasonNum] = sorted;
      }
    }

    return seasonMap;
  }

  /// Clears cached data for a specific tmdbId.
  void clearCache(int tmdbId) {
    _cache.remove(tmdbId);
  }

  /// Clears all cached data.
  void clearAllCache() {
    _cache.clear();
  }
}
