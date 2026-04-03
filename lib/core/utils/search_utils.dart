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
        baseList = baseList.where((item) {
          // Hide items with NO original metadata from category pages
          final hasMetadata = (item.originalLanguage != null &&
                  item.originalLanguage!.isNotEmpty) ||
              item.originCountry.isNotEmpty;
          if (!hasMetadata) return false;
          return _matchesCategory(item, enforceCategory);
        }).toList();
      }
    } else {
      // Not searching: use the items provided by the screen (which are usually already category-filtered)
      baseList = List.from(allItems);
      
      // Safety check: if an enforceCategory was passed, ensure everything on the list matches it.
      if (enforceCategory != null) {
        baseList = baseList.where((item) {
          // Hide items with NO original metadata from category pages
          final hasMetadata = (item.originalLanguage != null &&
                  item.originalLanguage!.isNotEmpty) ||
              item.originCountry.isNotEmpty;
          if (!hasMetadata) return false;
          return _matchesCategory(item, enforceCategory);
        }).toList();
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

    // 3. Filter by Region (Country)
    if (f.regions.isNotEmpty) {
      final regionMap = {
        'US': ['US'],
        'UK': ['GB', 'UK'],
        'South Korea': ['KR'],
        'China': ['CN'],
        'Japan': ['JP'],
        'India': ['IN'],
        'Turkey': ['TR'],
      };
      baseList = baseList.where((item) {
        return f.regions.any((regionName) {
          final codes = regionMap[regionName];
          if (codes != null) {
            return item.originCountry.any((c) => codes.contains(c));
          }
          return item.originCountry.contains(regionName);
        });
      }).toList();
    }

    // 3.1. Filter by Original Language
    if (f.originalLanguages.isNotEmpty) {
      final langMap = {
        'English': ['en'],
        'Hindi': ['hi'],
        'Korean': ['ko'],
        'Japanese': ['ja'],
        'Chinese': ['zh', 'cn'],
        'Turkish': ['tr'],
        'Punjabi': ['pa'],
      };
      baseList = baseList.where((item) {
        return f.originalLanguages.any((langName) {
          final codes = langMap[langName];
          if (codes != null) {
            return codes.contains(item.originalLanguage);
          }
          return item.originalLanguage == langName;
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

    // 6. Sort By (Default to Latest Release if none specified)
    final sortBy = f.sortBy;
    if (sortBy == 'Latest' || sortBy == 'Latest Release') {
      baseList
          .sort((a, b) => (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0));
    } else if (sortBy == 'Popularity') {
      baseList.sort((a, b) => b.voteCount.compareTo(a.voteCount));
    } else if (sortBy == 'Top Rated' || sortBy == 'Rating (High to Low)') {
      baseList.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
    } else {
      // "Perfect" default sorting: Year desc, then Vote Average desc
      baseList.sort((a, b) {
        final yearCmp = (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0);
        if (yearCmp != 0) return yearCmp;
        return b.voteAverage.compareTo(a.voteAverage);
      });
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
        // Strict Anime: Japanese original language
        return (item.genreIds.contains(16) ||
                item.genres.any((g) => g.toLowerCase() == 'animation')) &&
            item.originalLanguage == 'ja';
      case 'K-Drama' || 'Korean':
        // Strict Korean: KR origin or ko language
        return item.originCountry.contains('KR') ||
            item.originalLanguage == 'ko';
      case 'Bollywood':
        // Strict Bollywood: IN origin or hi language
        return item.originCountry.contains('IN') ||
            item.originalLanguage == 'hi' ||
            item.originalLanguage == 'ur' ||
            item.originalLanguage == 'pa';
      default:
        return false;
    }
  }
}
