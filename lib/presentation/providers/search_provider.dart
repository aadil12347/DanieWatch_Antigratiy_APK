import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/manifest_item.dart';
import '../../services/extraction/movie_site_scraper_service.dart';
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
  final Ref ref;
  Timer? _debounce;
  List<ManifestItem> _unfilteredResults = [];

  SearchNotifier(this.ref) : super(const SearchState());

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void search(String query, {bool immediate = false}) {
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

    Future<void> executeSearch() async {
      if (!mounted) return;

      state = state.copyWith(isSearching: true);

      try {
        final localMap = ref.read(localManifestMapProvider);
        // Live search across both Vegamovies and Rogmovies sorted by query relevance (closest match at top)
        final liveResults = await MovieSiteScraperService.instance.searchBothSites(
          query.trim(),
          localMap: localMap,
        );

        if (!mounted) return;

        if (liveResults.isNotEmpty) {
          _unfilteredResults = liveResults;
          state = state.copyWith(
            results: liveResults,
            isSearching: false,
          );
          return;
        }

        // Fallback: local index search if live search had 0 hits or offline
        final sortedItems = await ref.read(sortedManifestItemsProvider.future);
        final q = query.trim().toLowerCase();
        
        final matched = sortedItems.where((item) {
          final titleMatch = item.title.toLowerCase().contains(q);
          final overviewMatch = item.overview?.toLowerCase().contains(q) ?? false;
          return titleMatch || overviewMatch;
        }).toList();

        // Sort fallback matched items by query relevance as well
        matched.sort((a, b) {
          final scoreA = MovieSiteScraperService.instance.computeRelevanceScore(a.title, query);
          final scoreB = MovieSiteScraperService.instance.computeRelevanceScore(b.title, query);
          if (scoreA != scoreB) return scoreB.compareTo(scoreA);
          return (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0);
        });

        if (mounted) {
          _unfilteredResults = matched;
          state = state.copyWith(
            results: _unfilteredResults,
            isSearching: false,
          );
        }
      } catch (e) {
        if (mounted) {
          state = state.copyWith(results: [], isSearching: false);
        }
      }
    }

    if (immediate) {
      executeSearch();
    } else {
      // Trigger search after the user stops typing for 1.5 seconds (1500ms)
      _debounce = Timer(const Duration(milliseconds: 1500), executeSearch);
    }
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
    if (category == null || category == 'Explore' || category == 'Search') {
      state = state.copyWith(
        filters: const SearchFilters(),
        navCategoryOverride: () => null,
      );
    } else {
      const categoryMap = {
        'Search': 'Search',
        'Indian': 'Indian',
        'Dual Audio': 'Dual Audio',
        'Korean': 'Korean',
        'K-Drama': 'Korean',
        'Chinese': 'Chinese',
        'Anime': 'Anime',
        'Action': 'Action',
        'Sci-Fi': 'Sci-Fi',
        'Comedy': 'Comedy',
        'Thriller': 'Thriller',
        'Horror': 'Horror',
        'Romance': 'Romance',
        'Adventure': 'Adventure',
        'Crime': 'Crime',
        'Drama': 'Drama',
        'Mystery': 'Mystery',
        'Fantasy': 'Fantasy',
        'Animation': 'Animation',
        'Bollywood': 'Indian',
        'Hollywood': 'Hollywood',
        'Punjabi': 'Punjabi',
        'Pakistani': 'Pakistani',
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
  return SearchNotifier(ref);
});

final searchExpandedProvider = StateProvider<bool>((ref) => false);
final searchFocusProvider = StateProvider<bool>((ref) => false);
final searchBarOpenProvider = StateProvider<bool>((ref) => false);
