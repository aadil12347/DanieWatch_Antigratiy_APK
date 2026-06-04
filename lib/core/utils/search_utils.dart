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
      // Searching: build results from fuzzy search results (already category-scoped)
      // Preserve the order from the search results (sorted by relevance score)
      final resultMap = <String, double>{};
      for (final r in searchState.results) {
        final key = '${r.itemId}-${r.mediaType}';
        resultMap[key] = r.score;
      }

      baseList = searchState.results
          .map((r) {
            final existing = index['${r.itemId}-${r.mediaType}'];
            if (existing != null) return existing;
            
            // Create a stub ManifestItem for items not yet in memory
            return ManifestItem(
              id: r.itemId,
              mediaType: r.mediaType,
              title: r.title,
              releaseYear: r.releaseYear > 0 ? r.releaseYear : null,
              language: r.languages,
              genres: r.genres,
              originCountry: r.originCountry,
              originalLanguage: r.originalLanguage?.isNotEmpty == true
                  ? r.originalLanguage
                  : (r.languages.isNotEmpty ? r.languages.first : null),
              posterUrl: r.posterUrl,
            );
          })
          .toList();

      // If a category is enforced AND the fuzzy engine didn't already scope
      // (e.g. genre pages that search the whole index), apply category filter
      if (enforceCategory != null) {
        // Check if this is a genre filter (not a category page)
        // Genre pages should search ALL items, not scope by genre
        const categoryPages = {
          'Anime', 'Korean', 'K-Drama', 'Indian', 'Bollywood',
          'Hollywood', 'Chinese', 'Punjabi', 'Pakistani',
        };

        if (categoryPages.contains(enforceCategory)) {
          // Category pages: apply category filter without strict metadata check.
          // Items may have originalLanguage from Algolia even without originCountry.
          baseList = baseList.where((item) {
            return _matchesCategory(item, enforceCategory);
          }).toList();
        }
        // Genre filter pages: don't apply category filter (show all results)
      }

      // Sort by fuzzy relevance score (highest first)
      baseList.sort((a, b) {
        final scoreA = resultMap['${a.id}-${a.mediaType}'] ?? 0.0;
        final scoreB = resultMap['${b.id}-${b.mediaType}'] ?? 0.0;
        return scoreB.compareTo(scoreA);
      });

      // Apply post-search filters (genre, year, region etc.) but skip sorting
      // since we want to preserve relevance order
      return _applyPostFilters(baseList, searchState.filters, enforceCategory);
    } else {
      // Not searching: use the items provided by the screen (already category-filtered)
      baseList = List.from(allItems);
      
      // Safety check: if an enforceCategory was passed, ensure everything matches
      if (enforceCategory != null) {
        baseList = baseList.where((item) {
          return _matchesCategory(item, enforceCategory);
        }).toList();
      }
    }

    final f = searchState.filters;

    // 2. Apply filters and sorting for non-search mode
    baseList = _applyPostFilters(baseList, f, enforceCategory);

    // 6. Sort — only re-sort when user explicitly chose a sort option.
    // Default ('Popularity') preserves the posting-record priority order
    // that was already applied by the provider.
    final sortBy = f.sortBy;
    if (sortBy == 'Latest' || sortBy == 'Latest Release') {
      baseList.sort((a, b) {
        // Primary: sort by release_date (ISO string, lexicographic = chronological)
        final dateA = a.releaseDate ?? '';
        final dateB = b.releaseDate ?? '';
        if (dateA.isNotEmpty && dateB.isNotEmpty) {
          return dateB.compareTo(dateA); // DESC
        }
        // Fallback: items with date come before items without
        if (dateA.isNotEmpty) return -1;
        if (dateB.isNotEmpty) return 1;
        // Final fallback: releaseYear
        return (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0);
      });
    } else if (sortBy == 'Top Rated' || sortBy == 'Rating (High to Low)') {
      baseList.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
    }
    // Default 'Popularity': preserve existing order (posting-record priority)

    return baseList;
  }

  /// Apply post-search filters (categories sub-filter, region, language, genre, year)
  /// without re-sorting (preserves relevance order from fuzzy search)
  static List<ManifestItem> _applyPostFilters(
    List<ManifestItem> items,
    SearchFilters f,
    String? enforceCategory,
  ) {
    var baseList = items;

    // 2. Apply Page-Specific Filter Policy
    if (f.categories.isNotEmpty) {
      baseList = baseList.where((item) {
        final allowedFilters = f.categories.where((cat) {
          if (enforceCategory != null) {
            return cat == 'Movie' || cat == 'TV Shows' || cat == 'Series' || cat == 'Season';
          }
          return true;
        });

        if (allowedFilters.isEmpty) return true;
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
        'Action': [28, 12, 10759],
        'Animation': [16],
        'Comedy': [35],
        'Crime': [80],
        'Documentary': [99],
        'Drama': [18],
        'Family': [10751],
        'Fantasy': [14, 10765],
        'History': [36],
        'Horror': [27],
        'Music': [10402],
        'Mystery': [9648],
        'Romance': [10749],
        'Sci-Fi': [878, 14, 10765],
        'Science Fiction': [878, 14, 10765],
        'Thriller': [53],
        'War': [10752, 10768],
        'Western': [37],
        'Adventure': [12, 10759],
      };
      baseList = baseList.where((item) {
        return f.genres.any((genreName) {
          final ids = genreMap[genreName];
          final matchesId =
              ids != null && ids.any((id) => item.genreIds.contains(id));

          if (matchesId) return true;

          final searchLabel = genreName.toLowerCase();
          return item.genres.any((g) {
            final normalized = g.toLowerCase();
            return normalized.contains(searchLabel) ||
                (searchLabel == 'sci-fi' && (normalized.contains('science fiction') || normalized.contains('fantasy') || normalized.contains('supernatural'))) ||
                (searchLabel == 'science fiction' && (normalized.contains('sci-fi') || normalized.contains('fantasy') || normalized.contains('supernatural'))) ||
                (searchLabel == 'action' && normalized.contains('adventure')) ||
                (searchLabel == 'adventure' && normalized.contains('action'));
          });
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

    return baseList;
  }

  static bool _matchesCategory(ManifestItem item, String cat) {
    // Helper: check if item.language array contains a display-name (case-insensitive)
    // ONLY used as fallback when originalLanguage is empty (to avoid
    // mis-categorizing dubbed content, e.g. Hindi-dubbed Hollywood movies).
    bool hasLang(String name) =>
        item.language.any((l) => l.toLowerCase() == name.toLowerCase());

    // Whether item has TMDB-sourced original language metadata
    final hasOrigLang = item.originalLanguage != null &&
        item.originalLanguage!.isNotEmpty;

    // Fallback display-lang check: only match if originalLanguage is empty
    bool fallbackLang(String name) => !hasOrigLang && hasLang(name);

    switch (cat) {
      case 'Movie':
        return item.mediaType == 'movie';
      case 'TV Shows' || 'Season' || 'Series':
        return item.mediaType == 'tv' || item.mediaType == 'series';
      case 'Anime':
        // Anime = Japanese + Animation genre (not all Japanese content)
        final isJapanese = item.originalLanguage == 'ja' ||
            item.originCountry.contains('JP') ||
            fallbackLang('Japanese');
        if (!isJapanese) return false;
        return item.genreIds.contains(16) ||
            item.genres.any((g) {
              final gl = g.toLowerCase();
              return gl == 'animation' || gl == 'anime';
            });
      case 'K-Drama' || 'Korean':
        return item.originCountry.contains('KR') ||
            item.originalLanguage == 'ko' ||
            fallbackLang('Korean');
      case 'Indian':
      case 'Bollywood':
        return item.originCountry.contains('IN') ||
            ['hi', 'ta', 'te', 'ml', 'kn', 'bn', 'mr', 'gu', 'bh']
                .contains(item.originalLanguage) ||
            fallbackLang('Hindi') ||
            fallbackLang('Tamil') ||
            fallbackLang('Telugu') ||
            fallbackLang('Malayalam') ||
            fallbackLang('Kannada') ||
            fallbackLang('Bengali') ||
            fallbackLang('Marathi') ||
            fallbackLang('Gujarati') ||
            fallbackLang('Bhojpuri');
      case 'Hollywood':
        // Everything NOT in regional categories.
        // Only exclude by originalLanguage and originCountry (TMDB metadata).
        // Do NOT exclude by display language — those are DUB languages,
        // not original languages (e.g. The Godfather dubbed in Hindi = Hollywood).
        final excludedLangs = {'hi', 'ja', 'ko', 'pa', 'ur', 'zh', 'cn', 'ta', 'te', 'ml', 'kn', 'bn', 'mr', 'gu', 'bh'};
        final excludedCountries = {'IN', 'KR', 'JP', 'PK', 'CN', 'HK', 'TW'};
        if (excludedLangs.contains(item.originalLanguage)) return false;
        if (item.originCountry.any((c) => excludedCountries.contains(c))) return false;
        // For items with NO originalLanguage, use display language as fallback
        // to exclude genuinely regional content (not dubs)
        if (!hasOrigLang) {
          final excludedDisplayLangs = {'tamil', 'telugu', 'malayalam', 'kannada', 'bengali', 'marathi', 'japanese', 'korean', 'urdu', 'punjabi'};
          if (item.language.any((l) => excludedDisplayLangs.contains(l.toLowerCase()))) return false;
        }
        return true;
      case 'Chinese':
        return item.originCountry.contains('CN') ||
            item.originCountry.contains('HK') ||
            item.originCountry.contains('TW') ||
            item.originalLanguage == 'zh' ||
            item.originalLanguage == 'cn' ||
            fallbackLang('Chinese');
      case 'Punjabi':
        return item.originalLanguage == 'pa' ||
            fallbackLang('Punjabi');
      case 'Pakistani':
        return item.originCountry.contains('PK') ||
            item.originalLanguage == 'ur' ||
            fallbackLang('Urdu');
      default:
        return false;
    }
  }

  /// Public method to match by catalog slug (used by defense filter in search_screen).
  /// Maps catalog slugs like 'indian', 'korean' to category names.
  static bool matchesCategorySlug(ManifestItem item, String slug) {
    const slugToCategory = {
      'indian': 'Indian',
      'korean': 'Korean',
      'anime': 'Anime',
      'hollywood': 'Hollywood',
      'chinese': 'Chinese',
      'punjabi': 'Punjabi',
      'pakistani': 'Pakistani',
    };
    final cat = slugToCategory[slug];
    if (cat == null) return true; // 'all' → no filter
    return _matchesCategory(item, cat);
  }
}
