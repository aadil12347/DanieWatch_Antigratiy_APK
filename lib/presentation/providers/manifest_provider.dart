import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/manifest_item.dart';
import '../../domain/models/catalog_page.dart';
import '../../offline/sync_engine.dart';
import '../../data/repositories/github_top_content_repository.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Core Sync Provider — drives the paginated catalog system
// ═══════════════════════════════════════════════════════════════════════════════

/// Provides the home screen data (carousel + sections) from cache + background sync.
/// This is the primary provider that replaces the old monolithic manifestProvider.
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
// Search Index Provider — for search + visibility checks
// ═══════════════════════════════════════════════════════════════════════════════

/// Provides the lightweight search index (id + title + type + language).
/// Used for: search, visibility checks (navigation guards), explore filtering.
class SearchIndexNotifier extends AsyncNotifier<List<SearchIndexEntry>> {
  StreamSubscription<List<SearchIndexEntry>>? _sub;

  @override
  Future<List<SearchIndexEntry>> build() async {
    _sub = PaginatedSyncEngine.instance.onSearchIndexUpdated.listen((data) {
      state = AsyncValue.data(data);
    });
    ref.onDispose(() => _sub?.cancel());

    // Try cache first
    final cached = await PaginatedSyncEngine.instance.readCachedSearchIndex();
    return cached ?? [];
  }
}

final searchIndexProvider =
    AsyncNotifierProvider<SearchIndexNotifier, List<SearchIndexEntry>>(
        () => SearchIndexNotifier());

/// Fast visibility index — maps "id-type" → true for O(1) lookups.
/// Replaces the old manifestIndexProvider.
final visibilityIndexProvider = Provider<Set<String>>((ref) {
  final entries = ref.watch(searchIndexProvider).valueOrNull ?? [];
  return entries.map((e) => '${e.id}-${e.mediaType}').toSet();
});

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
// Paginated Category Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Query key for paginated catalog requests.
typedef CatalogQuery = ({String category, int page});

/// Fetches a specific page of a category. Uses cache with background refresh.
final catalogPageProvider =
    FutureProvider.family<CatalogPage?, CatalogQuery>((ref, query) async {
  // Watch home sections to re-trigger when sync completes
  ref.watch(homeSectionsDataProvider);
  return PaginatedSyncEngine.instance.fetchPage(query.category, query.page);
});

/// Provides catalog metadata (version, page counts).
final catalogMetaProvider = FutureProvider<CatalogMeta?>((ref) async {
  ref.watch(homeSectionsDataProvider);
  return PaginatedSyncEngine.instance.readCachedMeta();
});

// ═══════════════════════════════════════════════════════════════════════════════
// Category-Specific Providers (backward compatibility)
// These load page 1 of each category for tab views.
// ═══════════════════════════════════════════════════════════════════════════════

/// Helper: load page 1 of a category and return its items.
Future<List<ManifestItem>> _loadCategoryPage1(String category) async {
  final page = await PaginatedSyncEngine.instance.fetchPage(category, 1);
  return page?.items ?? [];
}

final globalItemsProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(homeSectionsDataProvider);
  return _loadCategoryPage1('all');
});

/// Synonym for globalItemsProvider — provides page 1 of global catalog.
final allItemsProvider = Provider<List<ManifestItem>>((ref) {
  return ref.watch(globalItemsProvider).valueOrNull ?? [];
});

/// Trending items — from home sections carousel or TMDB enrichment.
final trendingProvider = Provider<List<ManifestItem>>((ref) {
  final data = ref.watch(homeSectionsDataProvider).valueOrNull;
  if (data == null) return [];
  // Find trending section, or fall back to carousel
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

/// Movies (page 1) — from global items.
final moviesProvider = Provider<List<ManifestItem>>((ref) {
  final items = ref.watch(allItemsProvider);
  return items.where((item) => item.mediaType == 'movie').toList();
});

/// TV shows (page 1) — from global items.
final tvShowsProvider = Provider<List<ManifestItem>>((ref) {
  final items = ref.watch(allItemsProvider);
  return items
      .where((item) => item.mediaType == 'tv' || item.mediaType == 'series')
      .toList();
});

/// Category-specific providers (page 1).
final bollywoodProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(homeSectionsDataProvider);
  return _loadCategoryPage1('bollywood');
});

final koreanProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(homeSectionsDataProvider);
  return _loadCategoryPage1('korean');
});

final animeProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(homeSectionsDataProvider);
  return _loadCategoryPage1('anime');
});

final hollywoodProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(homeSectionsDataProvider);
  return _loadCategoryPage1('hollywood');
});

final chineseProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(homeSectionsDataProvider);
  return _loadCategoryPage1('chinese');
});

final punjabiProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(homeSectionsDataProvider);
  return _loadCategoryPage1('punjabi');
});

final pakistaniProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(homeSectionsDataProvider);
  return _loadCategoryPage1('pakistani');
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
// These are thin wrappers for code that still references the old providers.
// ═══════════════════════════════════════════════════════════════════════════════

/// Backward-compatible manifestProvider — wraps homeSectionsDataProvider.
/// Code that watches manifestProvider will still work.
final manifestProvider = FutureProvider<_CompatManifest?>((ref) async {
  final data = await ref.watch(homeSectionsDataProvider.future);
  if (data == null) return null;
  // Collect all unique items from sections + carousel
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

/// Backward-compatible manifest index — uses search index for full coverage.
final manifestIndexProvider = Provider<Map<String, ManifestItem>>((ref) {
  // Build from whatever items we have loaded
  final manifest = ref.watch(manifestProvider).valueOrNull;
  if (manifest == null) return {};
  final index = <String, ManifestItem>{};
  for (final item in manifest.items) {
    index['${item.id}-${item.mediaType}'] = item;
  }
  return index;
});

/// Minimal manifest wrapper for backward compatibility.
class _CompatManifest {
  final List<ManifestItem> items;
  const _CompatManifest({required this.items});
}
