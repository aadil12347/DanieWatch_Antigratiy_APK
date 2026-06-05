import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/manifest_item.dart';
import '../../data/clients/tmdb_client.dart';
import 'manifest_provider.dart';

/// Comprehensive filter state
class SearchFilters {
  final Set<String> categories;
  final Set<String> regions;
  final Set<String> originalLanguages;
  final Set<String> genres;
  final Set<String> years;
  final String sortBy;

  const SearchFilters({
    this.categories = const {},
    this.regions = const {},
    this.originalLanguages = const {},
    this.genres = const {},
    this.years = const {},
    this.sortBy = 'Popularity',
  });

  bool get hasActiveFilters =>
      categories.isNotEmpty ||
      regions.isNotEmpty ||
      originalLanguages.isNotEmpty ||
      genres.isNotEmpty ||
      years.isNotEmpty ||
      sortBy != 'Popularity';

  SearchFilters copyWith({
    Set<String>? categories,
    Set<String>? regions,
    Set<String>? originalLanguages,
    Set<String>? genres,
    Set<String>? years,
    String? sortBy,
  }) {
    return SearchFilters(
      categories: categories ?? this.categories,
      regions: regions ?? this.regions,
      originalLanguages: originalLanguages ?? this.originalLanguages,
      genres: genres ?? this.genres,
      years: years ?? this.years,
      sortBy: sortBy ?? this.sortBy,
    );
  }
}

/// Search state including filters
class SearchState {
  final String query;
  final List<ManifestItem> results;
  final bool isSearching;
  final SearchFilters filters;
  /// Category set via navbar navigation (should NOT appear as filter chip)
  final String? navCategory;

  const SearchState({
    this.query = '',
    this.results = const [],
    this.isSearching = false,
    this.filters = const SearchFilters(),
    this.navCategory,
  });

  SearchState copyWith({
    String? query,
    List<ManifestItem>? results,
    bool? isSearching,
    SearchFilters? filters,
    String? Function()? navCategoryOverride,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
      filters: filters ?? this.filters,
      navCategory: navCategoryOverride != null
          ? navCategoryOverride()
          : this.navCategory,
    );
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  Timer? _debounce;
  List<ManifestItem> _unfilteredResults = [];

  SearchNotifier() : super(const SearchState());

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void search(String query) {
    _debounce?.cancel();

    // Instant clear for empty/whitespace query
    if (query.trim().isEmpty) {
      _unfilteredResults = [];
      state = state.copyWith(
        query: '',
        results: [],
        isSearching: false,
      );
      return;
    }

    state = state.copyWith(query: query);

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;

      state = state.copyWith(isSearching: true);

      try {
        final rawResults = await TmdbClient.instance.searchMulti(query);
        final mappedResults = rawResults.map((item) {
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
            releaseDate: releaseDate,
          );
        }).toList();

        if (mounted) {
          _unfilteredResults = mappedResults;
          state = state.copyWith(
              results: _unfilteredResults, isSearching: false);
        }
      } catch (e) {
        if (mounted) {
          state = state.copyWith(results: [], isSearching: false);
        }
      }
    });
  }

  void updateFilters(SearchFilters newFilters) {
    final oldCategories = state.filters.categories;
    state = state.copyWith(filters: newFilters);

    if (state.query.trim().isNotEmpty &&
        newFilters.categories != oldCategories) {
      search(state.query);
    }
  }

  void setNavCategory(String? category) {
    if (category == null || category == 'Explore') {
      state = state.copyWith(
        filters: const SearchFilters(),
        navCategoryOverride: () => null,
      );
    } else {
      const categoryMap = {
        'Korean': 'Korean',
        'Anime': 'Anime',
        'Indian': 'Indian',
        'Bollywood': 'Indian',
        'Hollywood': 'Hollywood',
        'Chinese': 'Chinese',
        'Punjabi': 'Punjabi',
      };
      final filterCat = categoryMap[category] ?? category;
      state = state.copyWith(
        filters: SearchFilters(categories: {filterCat}),
        navCategoryOverride: () => filterCat,
      );
    }

    if (state.query.trim().isNotEmpty) {
      search(state.query);
    }
  }

  void clearFilters() {
    updateFilters(const SearchFilters());
  }

  void clear() {
    _debounce?.cancel();
    _unfilteredResults = [];
    state = const SearchState();
  }

  void clearAll() {
    _debounce?.cancel();
    _unfilteredResults = [];
    state = const SearchState(
      query: '',
      results: [],
      isSearching: false,
      filters: SearchFilters(),
    );
  }

  void searchInList(String query, List<ManifestItem> items) {
    _debounce?.cancel();
    state = state.copyWith(query: query);

    if (query.trim().isEmpty) {
      state = state.copyWith(results: [], isSearching: false);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      state = state.copyWith(isSearching: true);

      final q = query.toLowerCase();
      final results = items.where((item) => item.title.toLowerCase().contains(q)).toList();

      state = state.copyWith(results: results, isSearching: false);
    });
  }
}

final searchProvider =
    StateNotifierProvider.family<SearchNotifier, SearchState, String>((ref, contextId) {
  return SearchNotifier();
});

final searchExpandedProvider = StateProvider<bool>((ref) => false);
final searchFocusProvider = StateProvider<bool>((ref) => false);
final searchBarOpenProvider = StateProvider<bool>((ref) => false);
