import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/manifest_item.dart';
import '../../domain/models/catalog_page.dart';
import '../../offline/sync_engine.dart';
import '../../data/repositories/github_top_content_repository.dart';
import '../../data/local/search_database.dart';
import '../../data/local/manifest_dao.dart';
import 'search_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Core Sync Provider — drives the home screen content
// ═══════════════════════════════════════════════════════════════════════════════

/// Provides the home screen data (carousel + sections) from cache + background sync.
class HomeSectionsNotifier extends AsyncNotifier<HomeSectionsData?> {
  StreamSubscription<HomeSectionsData>? _sub;

  @override
  Future<HomeSectionsData?> build() async {
    _sub = PaginatedSyncEngine.instance.onHomeSectionsUpdated.listen((data) {
      state = AsyncValue.data(data);
    });
    ref.onDispose(() => _sub?.cancel());

    // Read cache first (instant)
    final cached = await PaginatedSyncEngine.instance.readCachedHomeSections();

    if (cached == null) {
      // No cache — must sync. Retry up to 3 times.
      String? lastError;
      for (int attempt = 1; attempt <= 3; attempt++) {
        final result = await PaginatedSyncEngine.instance.sync();
        if (result.error == null) {
          return PaginatedSyncEngine.instance.readCachedHomeSections();
        }
        lastError = result.error;
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
      throw Exception('Failed to load catalog after 3 attempts: $lastError');
    } else {
      // Cache exists — return immediately, refresh in background.
      PaginatedSyncEngine.instance.sync();
      return cached;
    }
  }

  Future<void> refresh() async {
    final result = await PaginatedSyncEngine.instance.sync();
    if (result.error != null) {
      throw Exception('Failed to refresh: ${result.error}');
    }
  }
}

final homeSectionsDataProvider =
    AsyncNotifierProvider<HomeSectionsNotifier, HomeSectionsData?>(
        () => HomeSectionsNotifier());


// ═══════════════════════════════════════════════════════════════════════════════
// Home Screen Providers (derived from HomeSectionsData)
// ═══════════════════════════════════════════════════════════════════════════════

/// Genre-based section data for home screen — same shape as before.
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

/// Carousel items for the hero section.
final carouselProvider = Provider<List<ManifestItem>>((ref) {
  final data = ref.watch(homeSectionsDataProvider).valueOrNull;
  return data?.carousel ?? [];
});

/// Home screen sections list — derived from pre-built home sections data.
final homeSectionsProvider = Provider<AsyncValue<List<ContentSection>>>((ref) {
  final asyncData = ref.watch(homeSectionsDataProvider);
  return asyncData.whenData((data) {
    if (data == null) return <ContentSection>[];
    return data.sections
        .map((s) => ContentSection(
              title: s.title,
              items: s.items,
              isRanked: s.isRanked,
            ))
        .toList();
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// Category Pagination via SQLite Database
// ═══════════════════════════════════════════════════════════════════════════════

/// Provides catalog metadata (version, counts).
final catalogMetaProvider = FutureProvider<CatalogMeta?>((ref) async {
  ref.watch(homeSectionsDataProvider);
  return PaginatedSyncEngine.instance.readCachedMeta();
});

/// State for a paginated category — loaded incrementally from SQLite.
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

/// Maps UI category labels to SQLite SearchDatabase filter.
SearchFilters _getFiltersForCategory(String category) {
  if (category == 'all') {
    return const SearchFilters();
  }
  return SearchFilters(categories: {category});
}

/// Helper to convert ManifestSearchResult to ManifestItem.
ManifestItem _searchResultToManifestItem(ManifestSearchResult result) {
  return ManifestItem(
    id: result.itemId,
    mediaType: result.mediaType,
    title: result.title,
    posterUrl: result.posterUrl,
    releaseYear: result.releaseYear,
    language: result.languages,
    genres: result.genres,
    originalLanguage: result.originalLanguage,
    originCountry: result.originCountry,
  );
}

/// Notifier that manages pagination via SQLite.
/// Fetches items in chunks of 50.
class PaginatedCategoryNotifier extends StateNotifier<AsyncValue<PaginatedCategoryState>> {
  final String category;
  static const int _pageSize = 50;

  PaginatedCategoryNotifier(this.category) : super(const AsyncValue.loading()) {
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    try {
      final filters = _getFiltersForCategory(category);
      // Wait for DB to be ready
      while (!SearchDatabase.instance.isReady) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      final results = await SearchDatabase.instance.search('', filters: filters, limit: _pageSize);
      
      state = AsyncValue.data(PaginatedCategoryState(
        items: results.map(_searchResultToManifestItem).toList(),
        currentPage: 1,
        hasMore: results.length == _pageSize,
      ));
    } catch (e, stack) {
      dev.log('[PaginatedCategory] $category page 1 error: $e', stackTrace: stack);
      state = AsyncValue.error(e, stack);
    }
  }

  /// Load the next page.
  Future<void> loadNextPage() async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.isLoadingMore || !current.hasMore) return;

    final nextPage = current.currentPage + 1;
    final limit = nextPage * _pageSize;

    state = AsyncValue.data(current.copyWith(isLoadingMore: true, errorOverride: () => null));

    try {
      final filters = _getFiltersForCategory(category);
      final results = await SearchDatabase.instance.search('', filters: filters, limit: limit);
      
      final items = results.map(_searchResultToManifestItem).toList();

      if (!mounted) return;

      state = AsyncValue.data(PaginatedCategoryState(
        items: items,
        currentPage: nextPage,
        isLoadingMore: false,
        hasMore: results.length == limit,
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

  /// Reset and reload from page 1.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _loadFirstPage();
  }
}

/// Paginated category provider — keyed by category slug.
final paginatedCategoryProvider = StateNotifierProvider.family<
    PaginatedCategoryNotifier, AsyncValue<PaginatedCategoryState>, String>(
  (ref, category) {
    // Re-create when home sections sync completes (new catalog version)
    ref.watch(homeSectionsDataProvider);
    return PaginatedCategoryNotifier(category);
  },
);

/// Maps UI category labels to catalog slugs.
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

// ═══════════════════════════════════════════════════════════════════════════════
// Category-Specific Providers (backward compatibility)
// These derive from the paginated provider, returning currently loaded items.
// ═══════════════════════════════════════════════════════════════════════════════

final globalItemsProvider = FutureProvider<List<ManifestItem>>((ref) async {
  // Return just the first 50 items for global
  while (!SearchDatabase.instance.isReady) {
    await Future.delayed(const Duration(milliseconds: 100));
  }
  final results = await SearchDatabase.instance.search('', limit: 50);
  return results.map(_searchResultToManifestItem).toList();
});

/// Synonym for globalItemsProvider.
final allItemsProvider = Provider<List<ManifestItem>>((ref) {
  return ref.watch(globalItemsProvider).valueOrNull ?? [];
});

/// Trending items — from home sections carousel or TMDB enrichment.
final trendingProvider = Provider<List<ManifestItem>>((ref) {
  final data = ref.watch(homeSectionsDataProvider).valueOrNull;
  if (data == null) return [];
  final trendingSection = data.sections
      .where((s) => s.title.toLowerCase().contains('trending'))
      .toList();
  if (trendingSection.isNotEmpty) return trendingSection.first.items;
  return data.carousel;
});

/// Popular items.
final popularProvider = Provider<List<ManifestItem>>((ref) {
  final data = ref.watch(homeSectionsDataProvider).valueOrNull;
  if (data == null) return [];
  final section = data.sections
      .where((s) => s.title.toLowerCase().contains('popular') ||
                     s.title.toLowerCase().contains('top rated'))
      .toList();
  return section.isNotEmpty ? section.first.items : [];
});

/// Category-specific providers (backward compat — returns all loaded items).
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

// ═══════════════════════════════════════════════════════════════════════════════
// Top 5 / Top 10 — Merged with TMDB (unchanged approach)
// ═══════════════════════════════════════════════════════════════════════════════

/// Fetches GitHub Top 5 curated items.
final githubTop5Provider = FutureProvider<Map<int, ManifestItem>>((ref) async {
  return GitHubTopContentRepository.instance.fetchTop5();
});

/// Fetches GitHub Top 10 curated items.
final githubTop10Provider = FutureProvider<Map<int, ManifestItem>>((ref) async {
  return GitHubTopContentRepository.instance.fetchTop10();
});

/// Fixed-Slot Merge: GitHub items at fixed positions, TMDB fills gaps.
List<ManifestItem> _mergeWithFixedSlots({
  required Map<int, ManifestItem> githubItems,
  required List<ManifestItem> tmdbItems,
  required int totalSlots,
}) {
  final slots = List<ManifestItem?>.filled(totalSlots, null);
  for (final entry in githubItems.entries) {
    final slotIndex = entry.key - 1;
    if (slotIndex >= 0 && slotIndex < totalSlots) {
      slots[slotIndex] = entry.value;
    }
  }
  final githubTmdbIds = githubItems.values.map((item) => item.id).toSet();
  final tmdbFiltered =
      tmdbItems.where((item) => !githubTmdbIds.contains(item.id)).toList();
  int tmdbIndex = 0;
  for (int i = 0; i < totalSlots; i++) {
    if (slots[i] == null && tmdbIndex < tmdbFiltered.length) {
      slots[i] = tmdbFiltered[tmdbIndex++];
    }
  }
  return slots.whereType<ManifestItem>().toList();
}

/// Merged carousel: GitHub Top 5 (fixed) + trending (fill gaps).
final mergedCarouselProvider = FutureProvider<List<ManifestItem>>((ref) async {
  final githubTop5 = await ref.watch(githubTop5Provider.future);
  final trending = ref.watch(trendingProvider);
  return _mergeWithFixedSlots(
    githubItems: githubTop5,
    tmdbItems: trending,
    totalSlots: 5,
  );
});

/// Merged Top 10: GitHub Top 10 (fixed) + trending (fill gaps).
final mergedTop10Provider = FutureProvider<List<ManifestItem>>((ref) async {
  final githubTop10 = await ref.watch(githubTop10Provider.future);
  final trending = ref.watch(trendingProvider);
  return _mergeWithFixedSlots(
    githubItems: githubTop10,
    tmdbItems: trending,
    totalSlots: 10,
  );
});

// ═══════════════════════════════════════════════════════════════════════════════
// BACKWARD COMPATIBILITY — manifestProvider + manifestIndexProvider
// ═══════════════════════════════════════════════════════════════════════════════

final manifestProvider = FutureProvider<_CompatManifest?>((ref) async {
  final data = await ref.watch(homeSectionsDataProvider.future);
  if (data == null) return null;
  final allItems = <ManifestItem>[];
  final seenIds = <String>{};
  for (final item in data.carousel) {
    final key = '${item.id}-${item.mediaType}';
    if (seenIds.add(key)) allItems.add(item);
  }
  for (final section in data.sections) {
    for (final item in section.items) {
      final key = '${item.id}-${item.mediaType}';
      if (seenIds.add(key)) allItems.add(item);
    }
  }
  return _CompatManifest(items: allItems);
});

final manifestIndexProvider = Provider<Map<String, ManifestItem>>((ref) {
  final manifest = ref.watch(manifestProvider).valueOrNull;
  if (manifest == null) return {};
  final index = <String, ManifestItem>{};
  for (final item in manifest.items) {
    index['${item.id}-${item.mediaType}'] = item;
  }
  return index;
});

class _CompatManifest {
  final List<ManifestItem> items;
  const _CompatManifest({required this.items});
}
