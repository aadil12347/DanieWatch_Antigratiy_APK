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

    if (searchState.query.trim().isNotEmpty) {
      baseList = searchState.results
          .map((r) => index['${r.itemId}-${r.mediaType}'])
          .whereType<ManifestItem>()
          .toList();

      if (enforceCategory != null) {
        baseList = baseList.where((item) => _matchesCategory(item, enforceCategory)).toList();
      }
    } else {
      baseList = List.from(allItems);
      if (enforceCategory != null) {
        baseList = baseList.where((item) => _matchesCategory(item, enforceCategory)).toList();
      }
    }

    final f = searchState.filters;

    // Filter by Categories
    if (f.categories.isNotEmpty) {
      baseList = baseList.where((item) {
        return f.categories.any((cat) => _matchesCategory(item, cat));
      }).toList();
    }

    // Filter by Region
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

    // Filter by Genre
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

    // Filter by Year
    if (f.years.isNotEmpty) {
      baseList = baseList.where((item) {
        if (item.releaseYear == null) return false;
        return f.years.contains(item.releaseYear.toString());
      }).toList();
    }

    // Sort By
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
    if (cat == 'Movie' || cat == 'Bollywood' || cat == 'Hollywood') {
      if (item.mediaType != 'movie') return false;
      if (cat == 'Movie') return true;
      if (cat == 'Bollywood') return (item.originalLanguage == 'hi' || item.originCountry.contains('IN'));
      if (cat == 'Hollywood') return (item.originalLanguage == 'en' || item.originCountry.contains('US'));
    }
    if ((cat == 'TV Shows' || cat == 'Season' || cat == 'Series' || cat == 'K-Drama' || cat == 'Korean') && item.mediaType == 'tv') {
      if (cat == 'TV Shows' || cat == 'Season' || cat == 'Series') return true;
      if ((cat == 'K-Drama' || cat == 'Korean') && item.originCountry.contains('KR')) return true;
    }
    if (cat == 'Anime' && item.mediaType == 'anime') return true;
    return false;
  }
}
