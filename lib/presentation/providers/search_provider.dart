import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/manifest_item.dart';
import '../../data/local/manifest_dao.dart';
import '../../core/utils/fuzzy_search_engine.dart';
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
  final List<ManifestSearchResult> results;
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
    List<ManifestSearchResult>? results,
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

/// Search provider using hybrid FTS + Fuzzy search engine
class SearchNotifier extends StateNotifier<SearchState> {
  final ManifestDao _dao = ManifestDao();
  final FuzzySearchEngine _fuzzyEngine;
  Timer? _debounce;
  List<ManifestSearchResult> _unfilteredResults = [];

  SearchNotifier(this._fuzzyEngine) : super(const SearchState());

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Determine the active category context from current filters.
  /// Returns the category name for category pages, null for Explore/genre pages.
  String? get _activeCategoryContext {
    final cats = state.filters.categories;
    if (cats.isEmpty) return null;

    // Top-level categories that should scope search
    const categoryPages = {
      'Anime', 'Korean', 'K-Drama', 'Bollywood',
      'Hollywood', 'Chinese', 'Punjabi', 'Pakistani',
    };

    for (final cat in cats) {
      if (categoryPages.contains(cat)) return cat;
    }

    // Sub-filters like "Movie" / "TV Shows" don't scope search
    return null;
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

    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;

      state = state.copyWith(isSearching: true);

      try {
        final categoryFilter = _activeCategoryContext;

        // === Primary: Use fuzzy search engine ===
        List<ManifestSearchResult> results = [];

        if (_fuzzyEngine.isBuilt) {
          final fuzzyResults = _fuzzyEngine.search(
            query,
            categoryFilter: categoryFilter,
            limit: 80,
          );

          results = fuzzyResults
              .map((r) => ManifestSearchResult(
                    itemId: r.itemId,
                    mediaType: r.mediaType,
                    title: r.title,
                    score: r.score,
                  ))
              .toList();
        }

        // === Fallback: FTS4 if fuzzy engine has no results ===
        if (results.isEmpty) {
          final ftsResults = await _dao.searchFts(query);
          results = ftsResults;
        }

        if (mounted) {
          _unfilteredResults = results;
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

    // If the category context changed while a search query is active,
    // re-run the search with the new category scope
    if (state.query.trim().isNotEmpty &&
        newFilters.categories != oldCategories) {
      search(state.query);
    }
  }

  /// Set category via navbar navigation — updates filters but marks
  /// the category as "nav-originated" so filter chips won't display it.
  void setNavCategory(String? category) {
    if (category == null || category == 'Explore') {
      // Clear nav category and reset filters
      state = state.copyWith(
        filters: const SearchFilters(),
        navCategoryOverride: () => null,
      );
    } else {
      // Map navbar labels to filter category values
      const categoryMap = {
        'Korean': 'Korean',
        'Anime': 'Anime',
        'Bollywood': 'Bollywood',
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

    // Re-run search if query is active
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

  /// Resets everything: query, results, AND filters
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

  /// Search within a specific list of items (legacy fallback, uses fuzzy matching)
  void searchInList(String query, List<ManifestItem> items) {
    _debounce?.cancel();
    state = state.copyWith(query: query);

    if (query.trim().isEmpty) {
      state = state.copyWith(results: [], isSearching: false);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      state = state.copyWith(isSearching: true);

      // Build a temporary mini fuzzy engine for this item list
      final miniEngine = FuzzySearchEngine();
      miniEngine.buildIndex(items);
      final fuzzyResults = miniEngine.search(query, limit: 50);

      final List<ManifestSearchResult> results = fuzzyResults
          .map((r) => ManifestSearchResult(
                itemId: r.itemId,
                mediaType: r.mediaType,
                title: r.title,
                score: r.score,
              ))
          .toList();

      state = state.copyWith(results: results, isSearching: false);
    });
  }
}

/// Global fuzzy search engine provider — built from all manifest items
final fuzzySearchEngineProvider = Provider<FuzzySearchEngine>((ref) {
  final engine = FuzzySearchEngine();
  final items = ref.watch(allItemsProvider);
  if (items.isNotEmpty) {
    engine.buildIndex(items);
  }
  return engine;
});

final searchProvider =
    StateNotifierProvider.family<SearchNotifier, SearchState, String>((ref, contextId) {
  final engine = ref.watch(fuzzySearchEngineProvider);
  return SearchNotifier(engine);
});

/// Tracks if the global header search is expanded (legacy, kept for app_shell compat)
final searchExpandedProvider = StateProvider<bool>((ref) => false);

/// Tracks if the search field in SearchScreen has active focus
final searchFocusProvider = StateProvider<bool>((ref) => false);
