import '../models/manifest_item.dart';

/// DB-Only Visibility Policy
///
/// HARD RULE: If an item is not in the manifest, it MUST NEVER be rendered.
/// This applies unconditionally to: feeds, search, details, deep links.
///
/// There is NO admin mode in this app.
/// TMDB API is used ONLY for enriching fields of DB-backed items.
class VisibilityPolicy {
  VisibilityPolicy._();

  /// Build a fast lookup index from the manifest list.
  /// Key: "{id}-{mediaType}"
  static Map<String, ManifestItem> buildIndex(List<ManifestItem> items) {
    final index = <String, ManifestItem>{};
    for (final item in items) {
      index['${item.id}-${item.mediaType}'] = item;
    }
    return index;
  }

  /// Check if a given tmdbId+mediaType exists in the DB manifest.
  static bool isDbBacked(
    int tmdbId,
    String mediaType,
    Map<String, ManifestItem> index,
  ) {
    return index.containsKey('$tmdbId-$mediaType');
  }

  /// Filter a list to only items that are DB-backed.
  static List<ManifestItem> filterRenderable(
    List<ManifestItem> items,
    Map<String, ManifestItem> index,
  ) {
    return items
        .where((item) => isDbBacked(item.id, item.mediaType, index))
        .toList();
  }

  /// Navigation guard: can we open a detail screen for this item?
  static bool canNavigateToDetail(
    int tmdbId,
    String mediaType,
    Map<String, ManifestItem> index,
  ) {
    return isDbBacked(tmdbId, mediaType, index);
  }

  /// Get a DB-backed item from the index, or null if not allowed.
  static ManifestItem? getItem(
    int tmdbId,
    String mediaType,
    Map<String, ManifestItem> index,
  ) {
    return index['$tmdbId-$mediaType'];
  }

  /// Get trending items — prefers TMDB-enriched trending, falls back to year+vote sort
  static List<ManifestItem> getTrending(List<ManifestItem> all,
      {int limit = 10}) {
    // First: items marked as trending by TMDB enrichment
    final tmdbTrending = all.where((item) => item.isTrending).toList();
    if (tmdbTrending.length >= limit) {
      tmdbTrending.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
      return tmdbTrending.take(limit).toList();
    }

    // Fallback: sort by year desc, then vote average desc
    final sorted = List<ManifestItem>.from(all)
      ..sort((a, b) {
        final yearCmp = (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0);
        if (yearCmp != 0) return yearCmp;
        return b.voteAverage.compareTo(a.voteAverage);
      });
    return sorted.take(limit).toList();
  }

  /// Get popular items — prefers TMDB-enriched popular
  static List<ManifestItem> getPopular(List<ManifestItem> all,
      {int limit = 20}) {
    final tmdbPopular = all.where((item) => item.isPopular).toList();
    if (tmdbPopular.isNotEmpty) {
      tmdbPopular.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
      return tmdbPopular.take(limit).toList();
    }
    return getTopRated(all, limit: limit);
  }

  static List<ManifestItem> filterAnime(List<ManifestItem> all) {
    return all
        .where((item) =>
            item.originalLanguage == 'ja' &&
            (item.genreIds.contains(16) ||
                item.genres.any((g) => g.toLowerCase() == 'animation')))
        .toList();
  }

  /// Filter for Korean content: tv type and KR origin
  static List<ManifestItem> filterKorean(List<ManifestItem> all) {
    return all
        .where((item) =>
            (item.mediaType == 'tv' || item.mediaType == 'series') &&
            item.originCountry.contains('KR'))
        .toList();
  }

  /// Filter for Bollywood/Hindi content: movie type and hi language/IN origin
  static List<ManifestItem> filterBollywood(List<ManifestItem> all) {
    return all
        .where((item) =>
            item.mediaType == 'movie' &&
            ((item.language.any((l) => l.toLowerCase() == 'hindi') ||
                item.originalLanguage == 'hi' ||
                item.originCountry.contains('IN'))))
        .toList();
  }

  /// Filter for Hollywood content: movie type and en language/US/GB origin
  static List<ManifestItem> filterHollywood(List<ManifestItem> all) {
    return all
        .where((item) =>
            item.mediaType == 'movie' &&
            (item.originalLanguage == 'en' ||
                item.originCountry.contains('US') ||
                item.originCountry.contains('GB')))
        .toList();
  }

  /// Filter for movies only
  static List<ManifestItem> filterMovies(List<ManifestItem> all) {
    return all.where((item) => item.mediaType == 'movie').toList();
  }

  /// Filter for TV/series only
  static List<ManifestItem> filterTv(List<ManifestItem> all) {
    return all
        .where((item) => item.mediaType == 'tv' || item.mediaType == 'series')
        .toList();
  }

  /// Get items by genre ID (integer) or name (string)
  static List<ManifestItem> filterByGenre(List<ManifestItem> all, dynamic genre) {
    if (genre is int) {
      return all.where((item) => item.genreIds.contains(genre)).toList();
    }
    if (genre is String) {
      final search = genre.toLowerCase();
      return all
          .where((item) => item.genres.any((g) => g.toLowerCase() == search))
          .toList();
    }
    return [];
  }

  /// Get top rated items (by TMDB vote average)
  static List<ManifestItem> getTopRated(List<ManifestItem> all,
      {int limit = 20}) {
    final sorted = List<ManifestItem>.from(all)
      ..sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
    return sorted.take(limit).toList();
  }

  /// Get recently added items (by year)
  static List<ManifestItem> getRecentlyAdded(List<ManifestItem> all,
      {int limit = 20}) {
    final sorted = List<ManifestItem>.from(all)
      ..sort((a, b) => (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0));
    return sorted.take(limit).toList();
  }
}
