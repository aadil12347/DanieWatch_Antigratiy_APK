import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/manifest_dao.dart';

/// Comprehensive filter state
class SearchFilters {
  final List<String> categories;
  final List<String> genres;
  final List<String> periods;
  final String sortBy;

  const SearchFilters({
    this.categories = const [],
    this.genres = const [],
    this.periods = const [],
    this.sortBy = 'Popularity',
  });

  bool get hasActiveFilters =>
      categories.isNotEmpty ||
      genres.isNotEmpty ||
      periods.isNotEmpty ||
      sortBy != 'Popularity';

  SearchFilters copyWith({
    List<String>? categories,
    List<String>? genres,
    List<String>? periods,
    String? sortBy,
  }) {
    return SearchFilters(
      categories: categories ?? this.categories,
      genres: genres ?? this.genres,
      periods: periods ?? this.periods,
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

/// Search provider using FTS and local filtering
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
    
    // Keep pulse of what user is typing
    state = state.copyWith(query: query);

    if (query.trim().isEmpty && !state.filters.hasActiveFilters) {
      _unfilteredResults = [];
      state = state.copyWith(results: [], isSearching: false);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      
      state = state.copyWith(isSearching: true);
      
      try {
        if (query.trim().isNotEmpty) {
           _unfilteredResults = await _dao.searchFts(query);
        } else {
           _unfilteredResults = []; 
        }
        
        _applyFiltersAndSort();
      } catch (e) {
        if (mounted) {
          state = state.copyWith(results: [], isSearching: false);
        }
      }
    });
  }

  void updateFilters(SearchFilters newFilters) {
    state = state.copyWith(filters: newFilters, isSearching: true);
    if (state.query.trim().isEmpty) {
      // In a real app we'd query by filters directly against the DB.
    }
    _applyFiltersAndSort();
  }

  void removeFilterChip(String label) {
    var f = state.filters;
    f = f.copyWith(
      categories: f.categories.where((e) => e != label).toList(),
      genres: f.genres.where((e) => e != label).toList(),
      periods: f.periods.where((e) => e != label).toList(),
    );
    updateFilters(f);
  }

  void clearFilters() {
    updateFilters(const SearchFilters());
  }

  void _applyFiltersAndSort() {
    if (!mounted) return;

    List<ManifestSearchResult> filtered = List.from(_unfilteredResults);
    final f = state.filters;

    // Filter by Category
    if (f.categories.isNotEmpty) {
      filtered = filtered.where((item) {
        if (f.categories.contains('Movie') && item.mediaType == 'movie') return true;
        if (f.categories.contains('Series') && item.mediaType == 'tv') return true;
        return false;
      }).toList();
    }

    // Sort
    if (f.sortBy == 'Latest Release') {
       filtered.sort((a, b) => b.itemId.compareTo(a.itemId));
    } else {
       // Popularity default (no-op as FTS rank is usually default)
    }

    state = state.copyWith(results: filtered, isSearching: false);
  }

  void clear() {
    _debounce?.cancel();
    _unfilteredResults = [];
    state = const SearchState();
  }
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier();
});

/// Tracks if the global header search is expanded
final searchExpandedProvider = StateProvider<bool>((ref) => false);
