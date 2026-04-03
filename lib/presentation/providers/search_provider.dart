import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/manifest_item.dart';
import '../../data/local/manifest_dao.dart';

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

  const SearchState({
    this.query = '',
    this.results = const [],
    this.isSearching = false,
    this.filters = const SearchFilters(),
  });

  SearchState copyWith({
    String? query,
    List<ManifestSearchResult>? results,
    bool? isSearching,
    SearchFilters? filters,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
      filters: filters ?? this.filters,
    );
  }
}

/// Search provider using FTS
class SearchNotifier extends StateNotifier<SearchState> {
  final ManifestDao _dao = ManifestDao();
  Timer? _debounce;
  List<ManifestSearchResult> _unfilteredResults = [];

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

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;

      state = state.copyWith(isSearching: true);

      try {
        final results = await _dao.searchFts(query);
        if (mounted) {
          _unfilteredResults = results;
          state = state.copyWith(results: _unfilteredResults, isSearching: false);
        }
      } catch (e) {
        if (mounted) {
          state = state.copyWith(results: [], isSearching: false);
        }
      }
    });
  }

  void updateFilters(SearchFilters newFilters) {
    state = state.copyWith(filters: newFilters);
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

  /// Search within a specific list of items (for category-isolated search)
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

      final search = query.toLowerCase();
      final List<ManifestSearchResult> results = items
          .where((item) =>
              item.title.toLowerCase().contains(search) ||
              (item.overview?.toLowerCase().contains(search) ?? false))
          .map((item) => ManifestSearchResult(
                itemId: item.id,
                mediaType: item.mediaType,
                title: item.title,
              ))
          .toList();

      state = state.copyWith(results: results, isSearching: false);
    });
  }
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier();
});

/// Tracks if the global header search is expanded (legacy, kept for app_shell compat)
final searchExpandedProvider = StateProvider<bool>((ref) => false);

/// Tracks if the search field in SearchScreen has active focus
final searchFocusProvider = StateProvider<bool>((ref) => false);
