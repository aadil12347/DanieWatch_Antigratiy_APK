import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/manifest_item.dart';
import '../../data/clients/tmdb_client.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Core TMDB Conversion Helper
// ═══════════════════════════════════════════════════════════════════════════════

ManifestItem _tmdbToManifestItem(Map<String, dynamic> item, {bool isTrending = false, bool isPopular = false, int? rank}) {
  final id = (item['id'] as num?)?.toInt() ?? 0;
  final mediaType = item['media_type']?.toString() ?? (item['name'] != null ? 'tv' : 'movie');
  final posterPath = item['poster_path']?.toString();
  final backdropPath = item['backdrop_path']?.toString();
  
  int? releaseYear;
  final releaseDate = (item['release_date'] ?? item['first_air_date'])?.toString();
  if (releaseDate != null && releaseDate.length >= 4) {
    releaseYear = int.tryParse(releaseDate.substring(0, 4));
  }

  return ManifestItem(
    id: id,
    mediaType: mediaType,
    title: (item['title'] ?? item['name'] ?? 'Unknown').toString(),
    posterUrl: posterPath != null ? TmdbClient.posterUrl(posterPath) : null,
    backdropUrl: backdropPath != null ? TmdbClient.backdropUrl(backdropPath) : null,
    voteAverage: (item['vote_average'] as num?)?.toDouble() ?? 0.0,
    voteCount: (item['vote_count'] as num?)?.toInt() ?? 0,
    releaseYear: releaseYear,
    overview: item['overview']?.toString(),
    originalLanguage: item['original_language']?.toString(),
    tmdbPosterPath: posterPath,
    tmdbBackdropPath: backdropPath,
    isTrending: isTrending,
    isPopular: isPopular,
    trendingRank: rank,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Home Screen Providers (TMDB Powered)
// ═══════════════════════════════════════════════════════════════════════════════

class ContentSection {
  final String title;
  final List<ManifestItem> items;
  final bool isRanked;
  const ContentSection({
    required this.title,
    required this.items,
    this.isRanked = false,
  });
}

/// Trending content for the Carousel
final mergedCarouselProvider = FutureProvider<List<ManifestItem>>((ref) async {
  final movies = await TmdbClient.instance.getTrending('movie', timeWindow: 'day');
  final tv = await TmdbClient.instance.getTrending('tv', timeWindow: 'day');
  
  final combined = <Map<String, dynamic>>[];
  int mi = 0, ti = 0;
  while (combined.length < 10 && (mi < movies.length || ti < tv.length)) {
    if (mi < movies.length) combined.add({...movies[mi++], 'media_type': 'movie'});
    if (ti < tv.length) combined.add({...tv[ti++], 'media_type': 'tv'});
  }
  
  return combined.take(5).toList().asMap().entries.map((entry) {
    return _tmdbToManifestItem(entry.value, isTrending: true, rank: entry.key + 1);
  }).toList();
});

/// Trending content for Top 10 Today
final mergedTop10Provider = FutureProvider<List<ManifestItem>>((ref) async {
  final movies = await TmdbClient.instance.getTrending('movie', timeWindow: 'day');
  final tv = await TmdbClient.instance.getTrending('tv', timeWindow: 'day');
  
  final combined = <Map<String, dynamic>>[];
  int mi = 0, ti = 0;
  while (combined.length < 20 && (mi < movies.length || ti < tv.length)) {
    if (mi < movies.length) combined.add({...movies[mi++], 'media_type': 'movie'});
    if (ti < tv.length) combined.add({...tv[ti++], 'media_type': 'tv'});
  }
  
  return combined.take(10).toList().asMap().entries.map((entry) {
    return _tmdbToManifestItem(entry.value, isTrending: true, rank: entry.key + 1);
  }).toList();
});

/// Home screen sections (DynamicTMDB)
final homeSectionsProvider = FutureProvider<List<ContentSection>>((ref) async {
  final sections = <ContentSection>[];
  
  // 1. Top 10 Today
  final top10 = await ref.watch(mergedTop10Provider.future);
  if (top10.isNotEmpty) {
    sections.add(ContentSection(title: 'Top 10 Today', items: top10, isRanked: true));
  }
  
  // 2. Popular
  final popularMovies = await TmdbClient.instance.getPopular('movie');
  final popularTv = await TmdbClient.instance.getPopular('tv');
  final popularCombined = <Map<String, dynamic>>[];
  int mi = 0, ti = 0;
  while (popularCombined.length < 15 && (mi < popularMovies.length || ti < popularTv.length)) {
    if (mi < popularMovies.length) popularCombined.add({...popularMovies[mi++], 'media_type': 'movie'});
    if (ti < popularTv.length) popularCombined.add({...popularTv[ti++], 'media_type': 'tv'});
  }
  if (popularCombined.isNotEmpty) {
    sections.add(ContentSection(
      title: 'Popular',
      items: popularCombined.map((e) => _tmdbToManifestItem(e, isPopular: true)).toList()
    ));
  }

  // 3. Indian
  final indianMovies = await TmdbClient.instance.discoverMovie(withOriginCountry: 'IN');
  if (indianMovies.isNotEmpty) {
    sections.add(ContentSection(
      title: 'Indian',
      items: indianMovies.map((e) => _tmdbToManifestItem({...e, 'media_type': 'movie'})).toList()
    ));
  }

  // 4. Anime
  final animeTv = await TmdbClient.instance.discoverTv(withGenres: '16', withOriginCountry: 'JP');
  if (animeTv.isNotEmpty) {
    sections.add(ContentSection(
      title: 'Anime',
      items: animeTv.map((e) => _tmdbToManifestItem({...e, 'media_type': 'tv'})).toList()
    ));
  }
  
  // 5. Korean
  final koreanTv = await TmdbClient.instance.discoverTv(withOriginCountry: 'KR');
  if (koreanTv.isNotEmpty) {
    sections.add(ContentSection(
      title: 'Korean',
      items: koreanTv.map((e) => _tmdbToManifestItem({...e, 'media_type': 'tv'})).toList()
    ));
  }

  // 6. Top Rated
  final topRatedMovies = await TmdbClient.instance.getTopRated('movie');
  if (topRatedMovies.isNotEmpty) {
    sections.add(ContentSection(
      title: 'Top Rated',
      items: topRatedMovies.take(15).map((e) => _tmdbToManifestItem({...e, 'media_type': 'movie'})).toList()
    ));
  }

  return sections;
});

// ═══════════════════════════════════════════════════════════════════════════════
// Category Pagination via TMDB
// ═══════════════════════════════════════════════════════════════════════════════

class PaginatedCategoryState {
  final List<ManifestItem> items;
  final int currentPage;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  const PaginatedCategoryState({
    this.items = const [],
    this.currentPage = 0,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  PaginatedCategoryState copyWith({
    List<ManifestItem>? items,
    int? currentPage,
    bool? isLoadingMore,
    bool? hasMore,
    String? Function()? errorOverride,
  }) {
    return PaginatedCategoryState(
      items: items ?? this.items,
      currentPage: currentPage ?? this.currentPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: errorOverride != null ? errorOverride() : error,
    );
  }
}

class PaginatedCategoryNotifier extends StateNotifier<AsyncValue<PaginatedCategoryState>> {
  final String category;

  PaginatedCategoryNotifier(this.category) : super(const AsyncValue.loading()) {
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    try {
      final results = await _fetchPage(1);
      state = AsyncValue.data(PaginatedCategoryState(
        items: results,
        currentPage: 1,
        hasMore: results.isNotEmpty,
      ));
    } catch (e, stack) {
      dev.log('[PaginatedCategory] $category page 1 error: $e', stackTrace: stack);
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> loadNextPage() async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.isLoadingMore || !current.hasMore) return;

    final nextPage = current.currentPage + 1;
    state = AsyncValue.data(current.copyWith(isLoadingMore: true, errorOverride: () => null));

    try {
      final results = await _fetchPage(nextPage);

      if (!mounted) return;

      state = AsyncValue.data(PaginatedCategoryState(
        items: [...current.items, ...results],
        currentPage: nextPage,
        isLoadingMore: false,
        hasMore: results.isNotEmpty,
      ));
    } catch (e, stack) {
      dev.log('[PaginatedCategory] $category page $nextPage error: $e', stackTrace: stack);
      if (mounted) {
        state = AsyncValue.data(current.copyWith(
          isLoadingMore: false,
          errorOverride: () => e.toString(),
        ));
      }
    }
  }

  Future<List<ManifestItem>> _fetchPage(int page) async {
    final slug = category.toLowerCase();
    List<Map<String, dynamic>> rawResults = [];
    String type = 'movie';

    if (slug == 'all') {
      rawResults = await TmdbClient.instance.getTrending('all', timeWindow: 'week', page: page);
      type = 'mixed';
    } else if (slug == 'indian' || slug == 'bollywood') {
      rawResults = await TmdbClient.instance.discoverMovie(page: page, withOriginCountry: 'IN');
      type = 'movie';
    } else if (slug == 'hollywood') {
      rawResults = await TmdbClient.instance.discoverMovie(page: page, withOriginCountry: 'US');
      type = 'movie';
    } else if (slug == 'anime') {
      rawResults = await TmdbClient.instance.discoverTv(page: page, withGenres: '16', withOriginCountry: 'JP');
      type = 'tv';
    } else if (slug == 'korean') {
      rawResults = await TmdbClient.instance.discoverTv(page: page, withOriginCountry: 'KR');
      type = 'tv';
    } else if (slug == 'chinese') {
      rawResults = await TmdbClient.instance.discoverTv(page: page, withOriginCountry: 'CN');
      type = 'tv';
    } else if (slug == 'punjabi') {
      rawResults = await TmdbClient.instance.discoverMovie(page: page, withOriginalLanguage: 'pa');
      type = 'movie';
    } else if (slug == 'pakistani') {
      rawResults = await TmdbClient.instance.discoverTv(page: page, withOriginCountry: 'PK');
      type = 'tv';
    } else {
      // Default to trending
      rawResults = await TmdbClient.instance.getTrending('all', timeWindow: 'week', page: page);
      type = 'mixed';
    }

    return rawResults.map((e) {
      final mediaType = type == 'mixed' ? (e['media_type'] ?? 'movie') : type;
      return _tmdbToManifestItem({...e, 'media_type': mediaType});
    }).toList();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _loadFirstPage();
  }
}

final paginatedCategoryProvider = StateNotifierProvider.family<
    PaginatedCategoryNotifier, AsyncValue<PaginatedCategoryState>, String>(
  (ref, category) {
    return PaginatedCategoryNotifier(category);
  },
);

String categoryLabelToSlug(String label) {
  const map = {
    'Explore': 'all',
    'Indian': 'indian',
    'Hollywood': 'hollywood',
    'Anime': 'anime',
    'Korean': 'korean',
    'Chinese': 'chinese',
    'Punjabi': 'punjabi',
    'Pakistani': 'pakistani',
  };
  return map[label] ?? 'all';
}

final globalItemsProvider = Provider<AsyncValue<List<ManifestItem>>>((ref) {
  return ref.watch(paginatedCategoryProvider('all')).whenData((s) => s.items);
});

final allItemsProvider = Provider<List<ManifestItem>>((ref) {
  return ref.watch(globalItemsProvider).valueOrNull ?? [];
});

final indianProvider = Provider<AsyncValue<List<ManifestItem>>>((ref) {
  return ref.watch(paginatedCategoryProvider('indian')).whenData((s) => s.items);
});

final bollywoodProvider = indianProvider;

final koreanProvider = Provider<AsyncValue<List<ManifestItem>>>((ref) {
  return ref.watch(paginatedCategoryProvider('korean')).whenData((s) => s.items);
});

final animeProvider = Provider<AsyncValue<List<ManifestItem>>>((ref) {
  return ref.watch(paginatedCategoryProvider('anime')).whenData((s) => s.items);
});

final hollywoodProvider = Provider<AsyncValue<List<ManifestItem>>>((ref) {
  return ref.watch(paginatedCategoryProvider('hollywood')).whenData((s) => s.items);
});

final chineseProvider = Provider<AsyncValue<List<ManifestItem>>>((ref) {
  return ref.watch(paginatedCategoryProvider('chinese')).whenData((s) => s.items);
});

final punjabiProvider = Provider<AsyncValue<List<ManifestItem>>>((ref) {
  return ref.watch(paginatedCategoryProvider('punjabi')).whenData((s) => s.items);
});

final pakistaniProvider = Provider<AsyncValue<List<ManifestItem>>>((ref) {
  return ref.watch(paginatedCategoryProvider('pakistani')).whenData((s) => s.items);
});
