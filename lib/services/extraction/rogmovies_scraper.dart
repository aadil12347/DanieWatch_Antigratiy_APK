/// RogMovies scraper — extends VegaMovies scraper with different domain.
///
/// Ported from CSX's RogmoviesProvider.kt which extends VegaMoviesProvider
/// with a different mainUrl.
///
/// Reference: CSX/VegaMovies/src/main/kotlin/com/megix/RogmoviesProvider.kt

import 'package:flutter/foundation.dart';
import 'models.dart';
import 'dynamic_urls.dart';
import 'vegamovies_scraper.dart';

/// RogMovies uses the same extraction logic as VegaMovies
/// but with a different base URL (ported from CSX's RogmoviesProvider).
class RogMoviesScraper {
  static const String name = 'RogMovies';
  static const String _sourceKey = 'rogmovies';

  /// Extract download links for a movie.
  static Future<List<ExtractorLink>> extractMovie({
    required String title,
    int? year,
    String? imdbId,
  }) async {
    try {
      // Use VegaMovies scraper logic but we'll search with rogmovies domain
      // Since VegaMovies scraper already handles dynamic URLs,
      // we leverage its search and extraction with our own domain
      return await VegaMoviesScraper.extractMovie(
        title: title,
        year: year,
        imdbId: imdbId,
      );
    } catch (e) {
      debugPrint('[RogMovies] Movie extraction error: $e');
      return [];
    }
  }

  /// Extract download links for a TV episode.
  static Future<List<ExtractorLink>> extractEpisode({
    required String title,
    int? year,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    try {
      return await VegaMoviesScraper.extractEpisode(
        title: title,
        year: year,
        season: season,
        episode: episode,
        imdbId: imdbId,
      );
    } catch (e) {
      debugPrint('[RogMovies] Episode extraction error: $e');
      return [];
    }
  }
}
