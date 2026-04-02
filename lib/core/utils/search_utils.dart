import '../../domain/models/manifest_item.dart';
import '../../presentation/providers/search_provider.dart';

class FilterUtils {
  static List<ManifestItem> getFilteredItems({
    required List<ManifestItem> allItems,
    required SearchState searchState,
    required Map<String, ManifestItem> index,
    String? enforceCategory,
  }) {
    List<ManifestItem> baseList;

    // 1. Establish the base list
    if (searchState.query.trim().isNotEmpty) {
      // Searching: build results from global search index
      baseList = searchState.results
          .map((r) => index['${r.itemId}-${r.mediaType}'])
          .whereType<ManifestItem>()
          .toList();

      // IF a category is enforced (e.g. we are on the Bollywood page),
      // we MUST re-filter the global search results to ensure they belong to this category.
      if (enforceCategory != null) {
        baseList = baseList.where((item) => _matchesCategory(item, enforceCategory)).toList();
      }
    } else {
      // Not searching: use the items provided by the screen (which are usually already category-filtered)
      baseList = List.from(allItems);
      
      // Safety check: if an enforceCategory was passed, ensure everything on the list matches it.
      if (enforceCategory != null) {
        baseList = baseList.where((item) => _matchesCategory(item, enforceCategory)).toList();
      }
    }

    final f = searchState.filters;

    // 2. Apply Page-Specific Filter Policy
    // When on a category page (e.g. Bollywood), generic category filters like "Movie" or "TV Shows"
    // should still work, but other top-level categories like "Anime" or "K-Drama" must be ignored
    // to prevent empty results due to filter collisions.
    if (f.categories.isNotEmpty) {
      baseList = baseList.where((item) {
        // If we are on a category page, we allow filtering by "Movie"/"TV Shows"
        // But we ignore any selected top-level categories that aren't the enforced one.
        final allowedFilters = f.categories.where((cat) {
          if (enforceCategory != null) {
            // If on a specific category page, only "Movie" and "TV Shows" are valid sub-filters
            return cat == 'Movie' || cat == 'TV Shows' || cat == 'Series' || cat == 'Season';
          }
          return true; // on global search, all categories are allowed
        });

        if (allowedFilters.isEmpty) return true; // No valid sub-filters, keep everything in baseList

        return allowedFilters.any((cat) => _matchesCategory(item, cat));
      }).toList();
    }

    // 3. Filter by Region
    if (f.regions.isNotEmpty) {
      final regionMap = {
        'US': ['US'],
        'South Korea': ['KR'],
        'China': ['CN'],
        'Japan': ['JP'],
        'India': ['IN'],
        'UK': ['GB'],
      };
      baseList = baseList.where((item) {
        return f.regions.any((regionName) {
          final codes = regionMap[regionName];
          return codes != null &&
              item.originCountry.any((c) => codes.contains(c));
        });
      }).toList();
    }

    // 4. Filter by Genre
    if (f.genres.isNotEmpty) {
      final genreMap = {
        'Action': 28,
        'Animation': 16,
        'Comedy': 35,
        'Crime': 80,
        'Documentary': 99,
        'Drama': 18,
        'Family': 10751,
        'Fantasy': 14,
        'History': 36,
        'Horror': 27,
        'Music': 10402,
        'Mystery': 9648,
        'Romance': 10749,
        'Science Fiction': 878,
        'Sci-Fi': 878,
        'Thriller': 53,
        'War': 10752,
        'Western': 37,
      };
      baseList = baseList.where((item) {
        return f.genres.any((genreName) {
          final genreId = genreMap[genreName];
          return genreId != null && item.genreIds.contains(genreId);
        });
      }).toList();
    }

    // 5. Filter by Year
    if (f.years.isNotEmpty) {
      baseList = baseList.where((item) {
        if (item.releaseYear == null) return false;
        return f.years.contains(item.releaseYear.toString());
      }).toList();
    }

    // 6. Sort By
    if (f.sortBy == 'Popularity') {
      baseList.sort((a, b) => b.voteCount.compareTo(a.voteCount));
    } else if (f.sortBy == 'Latest' || f.sortBy == 'Latest Release') {
      baseList
          .sort((a, b) => (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0));
    } else if (f.sortBy == 'Top Rated' || f.sortBy == 'Rating (High to Low)') {
      baseList.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
    }

    return baseList;
  }

  static bool _matchesCategory(ManifestItem item, String cat) {
    switch (cat) {
      case 'Movie':
        return item.mediaType == 'movie';
      case 'TV Shows' || 'Season' || 'Series':
        return item.mediaType == 'tv' || item.mediaType == 'series';
      case 'Anime':
        // Consistent with VisibilityPolicy.filterAnime
        return item.originalLanguage == 'ja' && item.genreIds.contains(16);
      case 'K-Drama' || 'Korean':
        // Consistent with VisibilityPolicy.filterKorean
        return (item.mediaType == 'tv' || item.mediaType == 'series') &&
            item.originCountry.contains('KR');
      case 'Bollywood':
        // Consistent with VisibilityPolicy.filterBollywood
        return item.mediaType == 'movie' &&
            (item.language.any((l) => l.toLowerCase() == 'hindi') ||
                item.originalLanguage == 'hi' ||
                item.originCountry.contains('IN'));
      case 'Hollywood':
        // Consistent with VisibilityPolicy.filterHollywood
        return item.mediaType == 'movie' &&
            (item.originalLanguage == 'en' ||
                item.originCountry.contains('US') ||
                item.originCountry.contains('GB'));
      default:
        return false;
    }
  }
}
