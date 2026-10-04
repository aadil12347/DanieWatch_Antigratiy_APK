import '../../domain/models/manifest_item.dart';
import '../../presentation/providers/search_provider.dart';

class FilterUtils {
  static List<ManifestItem> getFilteredItems({
    required List<ManifestItem> allItems,
    required SearchState searchState,
    Map<String, ManifestItem>? index,
    String? enforceCategory,
    bool localSearchOnly = false,
  }) {
    List<ManifestItem> baseList;

    // 1. Establish the base list
    if (searchState.query.trim().isNotEmpty) {
      if (localSearchOnly) {
        final q = searchState.query.trim().toLowerCase();
        baseList = allItems.where((item) {
          final titleMatch = item.title.toLowerCase().contains(q);
          final overviewMatch = item.overview?.toLowerCase().contains(q) ?? false;
          return titleMatch || overviewMatch;
        }).toList();
      } else {
        baseList = List.from(searchState.results);
      }

      // If a category is enforced apply category filter
      if (enforceCategory != null) {
        const categoryPages = {
          'Anime', 'Korean', 'K-Drama', 'Indian', 'Bollywood',
          'Hollywood', 'Chinese', 'Punjabi', 'Pakistani',
        };

        if (categoryPages.contains(enforceCategory)) {
          baseList = baseList.where((item) {
            return _matchesCategory(item, enforceCategory);
          }).toList();
        }
      }

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

    // 6. Sort
    final sortBy = f.sortBy;
    if (sortBy == 'Latest' || sortBy == 'Latest Release') {
      baseList.sort((a, b) {
        // Primary: sort by release_date (ISO string, lexicographic = chronological)
        final dateA = a.releaseDate ?? '';
        final dateB = b.releaseDate ?? '';
        if (dateA.isNotEmpty && dateB.isNotEmpty) {
          return dateB.compareTo(dateA); // DESC
        }
        if (dateA.isNotEmpty) return -1;
        if (dateB.isNotEmpty) return 1;
        return (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0);
      });
    } else if (sortBy == 'Top Rated' || sortBy == 'Rating (High to Low)') {
      baseList.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
    }

    return baseList;
  }

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
    bool hasLang(String name) =>
        item.language.any((l) => l.toLowerCase() == name.toLowerCase());

    final hasOrigLang = item.originalLanguage != null &&
        item.originalLanguage!.isNotEmpty;

    bool fallbackLang(String name) => !hasOrigLang && hasLang(name);

    final tLower = '${item.rawTitle ?? ''} ${item.title} ${item.overview ?? ''}'.toLowerCase();

    switch (cat) {
      case 'Movie':
        return item.mediaType == 'movie';
      case 'TV Shows' || 'Season' || 'Series':
        return item.mediaType == 'tv' || item.mediaType == 'series';
      case 'Anime':
        return item.genreIds.contains(16) ||
            item.genres.any((g) {
              final gl = g.toLowerCase();
              return gl == 'animation' || gl == 'anime';
            }) ||
            tLower.contains('anime') ||
            (item.originCountry.contains('JP') &&
                (item.mediaType == 'tv' || item.mediaType == 'series'));
      case 'K-Drama' || 'Korean':
        return item.originCountry.contains('KR') ||
            ['ko', 'kr', 'korean'].contains(item.originalLanguage?.toLowerCase()) ||
            fallbackLang('Korean') ||
            hasLang('Korean') ||
            tLower.contains('korean') ||
            tLower.contains('k-drama') ||
            tLower.contains('kdrama');
      case 'Indian':
      case 'Bollywood':
        return item.originCountry.contains('IN') ||
            ['hi', 'ta', 'te', 'ml', 'kn', 'bn', 'mr', 'gu', 'bh', 'pa', 'punjabi', 'ur', 'urdu']
                .contains(item.originalLanguage?.toLowerCase()) ||
            fallbackLang('Hindi') ||
            hasLang('Hindi') ||
            fallbackLang('Tamil') ||
            fallbackLang('Telugu') ||
            fallbackLang('Malayalam') ||
            fallbackLang('Kannada') ||
            fallbackLang('Bengali') ||
            fallbackLang('Marathi') ||
            fallbackLang('Gujarati') ||
            fallbackLang('Bhojpuri') ||
            fallbackLang('Punjabi') ||
            fallbackLang('Urdu') ||
            tLower.contains('hindi') ||
            tLower.contains('bollywood') ||
            tLower.contains('tollywood') ||
            tLower.contains('kollywood') ||
            tLower.contains('punjabi') ||
            tLower.contains('indian') ||
            tLower.contains('jiohotstar') ||
            tLower.contains('hotstar') ||
            tLower.contains('zee5') ||
            tLower.contains('sonyliv');
      case 'Dual Audio':
        return tLower.contains('dual audio') ||
            tLower.contains('dual-audio') ||
            tLower.contains('hindi dubbed') ||
            tLower.contains('hindi-dubbed') ||
            tLower.contains('hindi dub') ||
            tLower.contains('org dubbed') ||
            tLower.contains('org. dubbed') ||
            tLower.contains('dubbed') ||
            tLower.contains('multi audio') ||
            tLower.contains('multi-audio') ||
            tLower.contains('hindi-english') ||
            tLower.contains('{hindi') ||
            item.language.length > 1 ||
            item.language.any((l) => [
                  'dual audio',
                  'hindi dubbed',
                  'dubbed',
                  'multi audio',
                ].contains(l.toLowerCase()));
      case 'Hollywood':
        final excludedLangs = {
          'hi', 'hindi',
          'ta', 'tamil',
          'te', 'telugu',
          'ml', 'malayalam',
          'kn', 'kannada',
          'bn', 'bengali',
          'mr', 'marathi',
          'gu', 'gujarati',
          'bh', 'bhojpuri',
          'pa', 'punjabi',
          'ur', 'urdu',
          'ja', 'japanese',
          'ko', 'korean',
          'zh', 'cn', 'chinese', 'mandarin', 'cantonese'
        };
        final excludedCountries = {'IN', 'KR', 'JP', 'PK', 'CN', 'HK', 'TW'};

        if (item.originCountry.any((c) => excludedCountries.contains(c))) return false;

        final origLangLower = item.originalLanguage?.toLowerCase();
        if (origLangLower != null && excludedLangs.contains(origLangLower)) return false;

        final excludedDisplayLangs = {
          'hindi', 'tamil', 'telugu', 'malayalam', 'kannada', 'bengali',
          'marathi', 'gujarati', 'bhojpuri', 'punjabi', 'urdu',
          'japanese', 'korean', 'chinese', 'mandarin', 'cantonese'
        };
        if (item.language.any((l) => excludedDisplayLangs.contains(l.toLowerCase()))) return false;

        final countries = item.originCountry.map((c) => c.toUpperCase()).toSet();
        const hwCountries = {'US', 'GB', 'UK', 'AU', 'CA'};
        final isHwCountry = countries.intersection(hwCountries).isNotEmpty;
        final isEnglish = ['en', 'english'].contains(origLangLower) ||
            hasLang('English') ||
            tLower.contains('english');

        return isHwCountry || isEnglish;
      case 'Chinese':
        return item.originCountry.contains('CN') ||
            item.originCountry.contains('HK') ||
            item.originCountry.contains('TW') ||
            ['zh', 'cn', 'chinese', 'mandarin', 'cantonese']
                .contains(item.originalLanguage?.toLowerCase()) ||
            fallbackLang('Chinese') ||
            hasLang('Chinese') ||
            tLower.contains('chinese') ||
            tLower.contains('c-drama') ||
            tLower.contains('cdrama');
      case 'Punjabi':
        return ['pa', 'punjabi'].contains(item.originalLanguage?.toLowerCase()) ||
            hasLang('Punjabi') ||
            tLower.contains('punjabi');
      case 'Pakistani':
        return item.originCountry.contains('PK') ||
            ['ur', 'urdu'].contains(item.originalLanguage?.toLowerCase()) ||
            fallbackLang('Urdu') ||
            fallbackLang('Pakistani') ||
            hasLang('Urdu') ||
            tLower.contains('pakistani');
      case 'Action':
        return item.genreIds.any((id) => [28, 12, 10759].contains(id)) ||
            item.genres.any((g) => g.toLowerCase().contains('action')) ||
            tLower.contains('action');
      case 'Sci-Fi' || 'Science Fiction':
        return item.genreIds.any((id) => [878, 14, 10765].contains(id)) ||
            item.genres.any((g) {
              final gl = g.toLowerCase();
              return gl.contains('sci-fi') || gl.contains('science fiction');
            }) ||
            tLower.contains('sci-fi') ||
            tLower.contains('science fiction');
      case 'Comedy':
        return item.genreIds.contains(35) ||
            item.genres.any((g) => g.toLowerCase().contains('comedy')) ||
            tLower.contains('comedy');
      case 'Thriller':
        return item.genreIds.contains(53) ||
            item.genres.any((g) => g.toLowerCase().contains('thriller')) ||
            tLower.contains('thriller');
      case 'Horror':
        return item.genreIds.contains(27) ||
            item.genres.any((g) => g.toLowerCase().contains('horror')) ||
            tLower.contains('horror');
      case 'Romance':
        return item.genreIds.contains(10749) ||
            item.genres.any((g) => g.toLowerCase().contains('romance')) ||
            tLower.contains('romance') ||
            tLower.contains('romantic');
      case 'Adventure':
        return item.genreIds.any((id) => [12, 10759].contains(id)) ||
            item.genres.any((g) => g.toLowerCase().contains('adventure')) ||
            tLower.contains('adventure');
      case 'Crime':
        return item.genreIds.contains(80) ||
            item.genres.any((g) => g.toLowerCase().contains('crime')) ||
            tLower.contains('crime');
      case 'Drama':
        return item.genreIds.contains(18) ||
            item.genres.any((g) => g.toLowerCase().contains('drama')) ||
            tLower.contains('drama');
      case 'Mystery':
        return item.genreIds.contains(9648) ||
            item.genres.any((g) => g.toLowerCase().contains('mystery')) ||
            tLower.contains('mystery');
      case 'Fantasy':
        return item.genreIds.any((id) => [14, 10765].contains(id)) ||
            item.genres.any((g) => g.toLowerCase().contains('fantasy')) ||
            tLower.contains('fantasy');
      case 'Animation':
        return item.genreIds.contains(16) ||
            item.genres.any((g) => g.toLowerCase().contains('animation')) ||
            tLower.contains('animation');
      default:
        return false;
    }
  }

  static bool matchesCategorySlug(ManifestItem item, String slug) {
    const slugToCategory = {
      'indian': 'Indian',
      'bollywood': 'Bollywood',
      'dual-audio': 'Dual Audio',
      'dualaudio': 'Dual Audio',
      'korean': 'Korean',
      'k-drama': 'Korean',
      'kdrama': 'Korean',
      'chinese': 'Chinese',
      'anime': 'Anime',
      'hollywood': 'Hollywood',
      'punjabi': 'Punjabi',
      'pakistani': 'Pakistani',
      'action': 'Action',
      'sci-fi': 'Sci-Fi',
      'scifi': 'Sci-Fi',
      'comedy': 'Comedy',
      'thriller': 'Thriller',
      'horror': 'Horror',
      'romance': 'Romance',
      'adventure': 'Adventure',
      'crime': 'Crime',
      'drama': 'Drama',
      'mystery': 'Mystery',
      'fantasy': 'Fantasy',
      'animation': 'Animation',
    };
    final cat = slugToCategory[slug];
    if (cat == null) return true;
    return _matchesCategory(item, cat);
  }
}
