import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/manifest_item.dart';
import '../../core/utils/search_utils.dart';
import '../../data/clients/tmdb_client.dart';
import '../../data/clients/omdb_client.dart';
import '../../data/services/database_sync_service.dart';
import '../../data/repositories/posting_record_repository.dart';
import '../../services/extraction/movie_site_scraper_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Local Database Synchronizer & Loader Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Triggers remote index.json synchronization from GitHub on startup.
/// Runs independently — does NOT block manifest loading or splash navigation.
/// On success, invalidates localManifestItemsProvider so the UI refreshes
/// with the latest sorted data from the newly downloaded index.
final databaseSyncProvider = FutureProvider<bool>((ref) async {
  dev.log('[DatabaseSyncProvider] Starting background database sync...');

  // Only sync main index (3rd party index DEACTIVATED)
  final mainSuccess = await DatabaseSyncService.instance.syncIndex();

  dev.log('[DatabaseSyncProvider] Sync finished. Main=$mainSuccess');

  if (mainSuccess) {
    // Refresh all manifest-derived providers with new data
    ref.invalidate(localManifestItemsProvider);
  }
  return mainSuccess;
});

/// Exposes all ManifestItems loaded from the locally cached database file.
/// On first launch, loads from bundled seed index for instant content.
/// Does NOT block on network sync — the sync runs in background and will
/// invalidate this provider when a new index is ready.
final localManifestItemsProvider = FutureProvider<List<ManifestItem>>((ref) async {
  // Load main index only (3rd party index DEACTIVATED)
  final items = await DatabaseSyncService.instance.loadLocalIndex();

  dev.log('[localManifestItemsProvider] Loaded ${items.length} items from local database.');
  return items;
});

/// Exposes an O(1) lookup map of all items: ID -> ManifestItem
final localManifestMapProvider = Provider<Map<String, ManifestItem>>((ref) {
  final itemsAsync = ref.watch(localManifestItemsProvider);
  final items = itemsAsync.valueOrNull ?? [];
  return {for (var item in items) item.id.toString(): item};
});

/// Exposes the list of ManifestItems sorted by release date, priority, and ID.
final sortedManifestItemsProvider = FutureProvider<List<ManifestItem>>((ref) async {
  final items = await ref.watch(localManifestItemsProvider.future);
  
  // Load posting record priorities
  final priorityMap = await PostingRecordRepository.instance.buildPriorityMap();
  
  final sorted = List<ManifestItem>.from(items);
  sorted.sort((a, b) {
    // 1. Compare release dates DESC (newest first)
    final dateA = a.releaseDate ?? '';
    final dateB = b.releaseDate ?? '';
    final dateCompare = dateB.compareTo(dateA);
    if (dateCompare != 0) return dateCompare;

    // 2. Compare posting priority ASC (lower values = higher priority)
    final keyA = '${a.id}-${a.mediaType}';
    final keyB = '${b.id}-${b.mediaType}';
    final prioA = priorityMap[keyA] ?? 999999;
    final prioB = priorityMap[keyB] ?? 999999;
    final prioCompare = prioA.compareTo(prioB);
    if (prioCompare != 0) return prioCompare;

    // 3. Fallback: ID DESC
    return b.id.compareTo(a.id);
  });
  
  return sorted;
});

// ═══════════════════════════════════════════════════════════════════════════════
// Dynamic Poster Loading Provider (TMDB -> OMDb Fallback)
// ═══════════════════════════════════════════════════════════════════════════════

/// Dynamically resolves a poster image URL for an item.
/// ID can be a TMDB ID, a ULID, or an IMDb ID starting with "tt".
final posterUrlProvider = FutureProvider.family<String?, String>((ref, idAndType) async {
  final parts = idAndType.split('_');
  final id = parts[0];
  final type = parts.length > 1 ? parts[1] : 'movie';

  // 0. Check live scraped service itemMap first for instant poster rendering
  final scrapedItem = MovieSiteScraperService.instance.itemMap[id];
  if (scrapedItem != null) {
    if (scrapedItem.posterUrl != null && scrapedItem.posterUrl!.isNotEmpty) {
      return scrapedItem.posterUrl;
    }
    if (scrapedItem.tmdbPosterPath != null && scrapedItem.tmdbPosterPath!.isNotEmpty) {
      return TmdbClient.posterUrl(scrapedItem.tmdbPosterPath);
    }
  }

  // 1. If ID starts with 'tt' (IMDb ID in place of TMDB ID)
  if (id.startsWith('tt')) {
    return await OmdbClient.instance.getPoster(id);
  }

  // 2. If ID is numeric, query TMDB details for the poster_path
  final tmdbId = int.tryParse(id);
  if (tmdbId != null && tmdbId > 0) {
    try {
      final isTv = type == 'tv' || type == 'series';
      final details = isTv
          ? await TmdbClient.instance.getTvDetails(tmdbId)
          : await TmdbClient.instance.getMovieDetails(tmdbId);
      final posterPath = details?['poster_path']?.toString();
      if (posterPath != null && posterPath.isNotEmpty) {
        return TmdbClient.posterUrl(posterPath);
      }
    } catch (_) {
      // Failed to query TMDB
    }
  }

  // 3. Fallback: If TMDB lookup fails/returns empty, check if we have a valid IMDb ID in local index
  final map = ref.read(localManifestMapProvider);
  final item = map[id];
  if (item != null && item.imdbId != null && item.imdbId!.startsWith('tt')) {
    return await OmdbClient.instance.getPoster(item.imdbId!);
  }

  return null;
});

// ═══════════════════════════════════════════════════════════════════════════════
// Home Screen Providers (Local-Cache Powered)
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

/// Shared helper: build a hybrid Top N list from database curated picks + TMDB trending.
/// [folder] is 'Top 5' or 'Top 10'.
/// [maxSlots] is 5 or 10.
/// [excludeIds] is a set of tmdb_ids to exclude (for cross-section dedup).
/// TMDB trending items are cross-checked against localMap — only items present
/// in the local database index are used as fillers (ensures all items are playable).
/// Falls back to sorted manifest items to guarantee exactly [maxSlots] items.
Future<List<ManifestItem>> _buildHybridTopList({
  required String folder,
  required int maxSlots,
  required Map<String, ManifestItem> localMap,
  required List<Map<String, dynamic>> trendingPool,
  required Set<int> excludeIds,
  required List<ManifestItem> sortedItems,
}) async {
  // 1. Load curated picks from cache: {position: tmdb_id}
  final curatedPicks = await DatabaseSyncService.instance.loadTopPicks(folder);
  dev.log('[HybridTop] $folder: ${curatedPicks.length} curated picks loaded');

  // 2. Build the result array with curated items at their fixed positions
  final List<ManifestItem?> slots = List.filled(maxSlots, null);
  final Set<int> usedIds = {...excludeIds};

  for (final entry in curatedPicks.entries) {
    final pos = entry.key; // 1-indexed
    final tmdbId = entry.value;
    if (pos < 1 || pos > maxSlots) continue;
    if (usedIds.contains(tmdbId)) continue; // skip duplicates

    // Only use curated pick if it exists in local manifest (playable content)
    final localItem = localMap[tmdbId.toString()];
    if (localItem != null) {
      slots[pos - 1] = localItem.copyWith(isTrending: true, trendingRank: pos);
      usedIds.add(tmdbId);
    }
    // If not in local index, skip — slot will be filled below
  }

  // 3. Fill remaining empty slots from TMDB trending (daily+weekly)
  //    ONLY use trending items that also exist in the local index (cross-check)
  int trendingIdx = 0;
  for (int i = 0; i < maxSlots; i++) {
    if (slots[i] != null) continue;

    // Find next trending item that exists in local manifest
    while (trendingIdx < trendingPool.length) {
      final trendingItem = trendingPool[trendingIdx];
      trendingIdx++;
      final tId = trendingItem['id'];
      if (tId is! int || tId <= 0) continue;
      if (usedIds.contains(tId)) continue;

      // Cross-check: only use if present in local index
      final localItem = localMap[tId.toString()];
      if (localItem != null) {
        slots[i] = localItem.copyWith(isTrending: true, trendingRank: i + 1);
        usedIds.add(tId);
        break;
      }
    }
  }

  // 4. Final fallback: fill any remaining empty slots from sorted manifest
  //    Guarantees exactly [maxSlots] items are always returned
  int sortedIdx = 0;
  for (int i = 0; i < maxSlots; i++) {
    if (slots[i] != null) continue;

    while (sortedIdx < sortedItems.length) {
      final item = sortedItems[sortedIdx];
      sortedIdx++;
      if (usedIds.contains(item.id)) continue;

      slots[i] = item.copyWith(isTrending: true, trendingRank: i + 1);
      usedIds.add(item.id);
      break;
    }
  }

  // 5. Return non-null items in order
  return slots.whereType<ManifestItem>().toList();
}

/// Cached TMDB trending results — daily + weekly merged, shared between Top 5 and Top 10
final _tmdbDailyTrendingProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  dev.log('[TmdbTrending] Fetching daily + weekly trending...');
  final results = await Future.wait([
    TmdbClient.instance.getTrending('all', timeWindow: 'day'),
    TmdbClient.instance.getTrending('all', timeWindow: 'week'),
  ]);
  
  // Merge daily + weekly, daily items first, dedup by id
  final seen = <int>{};
  final merged = <Map<String, dynamic>>[];
  for (final list in results) {
    for (final item in list) {
      final id = item['id'];
      if (id is int && !seen.contains(id)) {
        seen.add(id);
        merged.add(item);
      }
    }
  }
  
  dev.log('[TmdbTrending] Got ${merged.length} trending items (daily + weekly merged)');
  return merged;
});

/// Top picks sync provider — triggers sync during app startup
final topPicksSyncProvider = FutureProvider<bool>((ref) async {
  dev.log('[TopPicksSync] Starting top picks sync...');
  final result = await DatabaseSyncService.instance.syncTopPicks();
  if (result) {
    // Refresh carousel and top10 providers after sync completes
    ref.invalidate(mergedCarouselProvider);
    ref.invalidate(mergedTop10Provider);
  }
  return result;
});

/// Trending content for the Carousel (Top 5: 3 from VegaMovies, 2 from RogMovies)
final mergedCarouselProvider = FutureProvider<List<ManifestItem>>((ref) async {
  final localMap = ref.watch(localManifestMapProvider);
  try {
    final topLists = await MovieSiteScraperService.instance.fetchHomeTopLists(localMap: localMap);
    final top5 = topLists['top5'];
    if (top5 != null && top5.isNotEmpty) {
      dev.log('[mergedCarouselProvider] Built ${top5.length} live Vega/Rog carousel items');
      return top5;
    }
  } catch (e) {
    dev.log('[mergedCarouselProvider] Live fetch error: $e, falling back to local hybrid');
  }

  // Fallback to local hybrid if offline
  final trending = await ref.watch(_tmdbDailyTrendingProvider.future);
  final sorted = await ref.watch(sortedManifestItemsProvider.future);
  return await _buildHybridTopList(
    folder: 'Top 5',
    maxSlots: 5,
    localMap: localMap,
    trendingPool: trending,
    excludeIds: {},
    sortedItems: sorted,
  );
});

/// Top 10 Today list (5 from RogMovies, 5 from VegaMovies, strictly distinct from Top 5)
final mergedTop10Provider = FutureProvider<List<ManifestItem>>((ref) async {
  final localMap = ref.watch(localManifestMapProvider);
  try {
    final topLists = await MovieSiteScraperService.instance.fetchHomeTopLists(localMap: localMap);
    final top10 = topLists['top10'];
    if (top10 != null && top10.isNotEmpty) {
      dev.log('[mergedTop10Provider] Built ${top10.length} live Vega/Rog top 10 items (distinct from Top 5)');
      return top10;
    }
  } catch (e) {
    dev.log('[mergedTop10Provider] Live fetch error: $e, falling back to local hybrid');
  }

  // Fallback to local hybrid if offline
  final trending = await ref.watch(_tmdbDailyTrendingProvider.future);
  final sorted = await ref.watch(sortedManifestItemsProvider.future);
  final top5Items = await ref.watch(mergedCarouselProvider.future);
  final top5Ids = top5Items.map((item) => item.id).toSet();

  return await _buildHybridTopList(
    folder: 'Top 10',
    maxSlots: 10,
    localMap: localMap,
    trendingPool: trending,
    excludeIds: top5Ids,
    sortedItems: sorted,
  );
});

/// Home screen sections compiled live from VegaMovies and RogMovies
final homeSectionsProvider = FutureProvider<List<ContentSection>>((ref) async {
  final localMap = ref.watch(localManifestMapProvider);
  final sections = <ContentSection>[];

  // 0. Top 5 Movies (3 from VegaMovies, 2 from RogMovies)
  final top5 = await ref.watch(mergedCarouselProvider.future);
  if (top5.isNotEmpty) {
    sections.add(ContentSection(title: 'Top 5 Movies', items: top5, isRanked: true));
  }

  // 1. Top 10 Today (5 from RogMovies, 5 from VegaMovies, strictly distinct from Top 5)
  final top10 = await ref.watch(mergedTop10Provider.future);
  if (top10.isNotEmpty) {
    sections.add(ContentSection(title: 'Top 10 Today', items: top10, isRanked: true));
  }

  // 2. K-Drama Section (https://vegamovies.gallery/korean-series/)
  try {
    final kdramaItems = await MovieSiteScraperService.instance.fetchCategoryPage('korean', page: 1, localMap: localMap);
    if (kdramaItems.isNotEmpty) {
      sections.add(ContentSection(title: 'K-Drama', items: kdramaItems));
    }
  } catch (e) {
    dev.log('[homeSectionsProvider] KDrama error: $e');
  }

  // 3. Chinese Section (https://vegamovies.gallery/search.html?q=Chinese)
  try {
    final chineseItems = await MovieSiteScraperService.instance.fetchCategoryPage('chinese', page: 1, localMap: localMap);
    if (chineseItems.isNotEmpty) {
      sections.add(ContentSection(title: 'Chinese', items: chineseItems));
    }
  } catch (e) {
    dev.log('[homeSectionsProvider] Chinese error: $e');
  }

  // 4. Anime Section (https://vegamovies.gallery/anime-series/)
  try {
    final animeItems = await MovieSiteScraperService.instance.fetchCategoryPage('anime', page: 1, localMap: localMap);
    if (animeItems.isNotEmpty) {
      sections.add(ContentSection(title: 'Anime', items: animeItems));
    }
  } catch (e) {
    dev.log('[homeSectionsProvider] Anime error: $e');
  }

  // 5. Action Section (VegaMovies Action + RogMovies Action mixed)
  try {
    final actionItems = await MovieSiteScraperService.instance.fetchCategoryPage('action', page: 1, localMap: localMap);
    if (actionItems.isNotEmpty) {
      sections.add(ContentSection(title: 'Action', items: actionItems));
    }
  } catch (e) {
    dev.log('[homeSectionsProvider] Action error: $e');
  }

  // 6. Comedy (mixed VegaMovies + RogMovies)
  try {
    final comedyItems = await MovieSiteScraperService.instance.fetchCategoryPage('comedy', page: 1, localMap: localMap);
    if (comedyItems.isNotEmpty) {
      sections.add(ContentSection(title: 'Comedy', items: comedyItems));
    }
  } catch (e) {}

  // 7. Thriller (mixed VegaMovies + RogMovies)
  try {
    final thrillerItems = await MovieSiteScraperService.instance.fetchCategoryPage('thriller', page: 1, localMap: localMap);
    if (thrillerItems.isNotEmpty) {
      sections.add(ContentSection(title: 'Thriller', items: thrillerItems));
    }
  } catch (e) {}

  // 8. Horror (mixed VegaMovies + RogMovies)
  try {
    final horrorItems = await MovieSiteScraperService.instance.fetchCategoryPage('horror', page: 1, localMap: localMap);
    if (horrorItems.isNotEmpty) {
      sections.add(ContentSection(title: 'Horror', items: horrorItems));
    }
  } catch (e) {}

  // 9. Sci-Fi (mixed VegaMovies + RogMovies)
  try {
    final scifiItems = await MovieSiteScraperService.instance.fetchCategoryPage('sci-fi', page: 1, localMap: localMap);
    if (scifiItems.isNotEmpty) {
      sections.add(ContentSection(title: 'Sci-Fi', items: scifiItems));
    }
  } catch (e) {}

  // 10. Romance (mixed VegaMovies + RogMovies)
  try {
    final romanceItems = await MovieSiteScraperService.instance.fetchCategoryPage('romance', page: 1, localMap: localMap);
    if (romanceItems.isNotEmpty) {
      sections.add(ContentSection(title: 'Romance', items: romanceItems));
    }
  } catch (e) {}

  return sections;
});


// ═══════════════════════════════════════════════════════════════════════════════
// Category Pagination via Local Database Cache
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
  final Ref ref;

  PaginatedCategoryNotifier(this.category, this.ref) : super(const AsyncValue.loading()) {
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    try {
      final results = await _fetchLocalPage(1);
      final cat = category.toLowerCase().trim();
      const liveCategories = {
        'action', 'korean', 'chinese', 'anime', 'comedy', 'thriller', 'horror', 'sci-fi', 'romance'
      };
      final minPageSize = liveCategories.contains(cat) ? 10 : 30;

      state = AsyncValue.data(PaginatedCategoryState(
        items: results,
        currentPage: 1,
        hasMore: results.length >= minPageSize,
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
      final results = await _fetchLocalPage(nextPage);

      if (!mounted) return;

      final cat = category.toLowerCase().trim();
      const liveCategories = {
        'action', 'korean', 'chinese', 'anime', 'comedy', 'thriller', 'horror', 'sci-fi', 'romance'
      };
      final minPageSize = liveCategories.contains(cat) ? 10 : 30;

      state = AsyncValue.data(PaginatedCategoryState(
        items: [...current.items, ...results],
        currentPage: nextPage,
        isLoadingMore: false,
        hasMore: results.length >= minPageSize,
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

  Future<List<ManifestItem>> _fetchLocalPage(int page) async {
    final cat = category.toLowerCase().trim();
    const liveCategories = {
      'action',
      'korean',
      'chinese',
      'anime',
      'comedy',
      'thriller',
      'horror',
      'sci-fi',
      'romance',
    };
    if (liveCategories.contains(cat)) {
      try {
        final liveItems = await MovieSiteScraperService.instance
            .fetchCategoryPage(cat, page: page);
        if (liveItems.isNotEmpty) {
          return liveItems;
        }
      } catch (e) {
        dev.log('[_fetchLocalPage] Error fetching live $cat page $page: $e');
      }
    }

    final sorted = await ref.read(sortedManifestItemsProvider.future);
    final filtered = _filterCategory(sorted, category);
    
    final int limit = 30;
    final int offset = (page - 1) * limit;
    
    if (offset >= filtered.length) {
      return [];
    }
    
    return filtered.skip(offset).take(limit).toList();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _loadFirstPage();
  }
}

final paginatedCategoryProvider = StateNotifierProvider.family<
    PaginatedCategoryNotifier, AsyncValue<PaginatedCategoryState>, String>(
  (ref, category) {
    return PaginatedCategoryNotifier(category, ref);
  },
);

String categoryLabelToSlug(String label) {
  const map = {
    'Explore': 'all',
    'Action': 'action',
    'Indian': 'indian',
    'Bollywood': 'bollywood',
    'Hollywood': 'hollywood',
    'Anime': 'anime',
    'Korean': 'korean',
    'K-Drama': 'korean',
    'Chinese': 'chinese',
    'Punjabi': 'punjabi',
    'Pakistani': 'pakistani',
    'Comedy': 'comedy',
    'Thriller': 'thriller',
    'Horror': 'horror',
    'Sci-Fi': 'sci-fi',
    'Romance': 'romance',
  };
  return map[label] ?? label.toLowerCase();
}

// ═══════════════════════════════════════════════════════════════════════════════
// Offline Filtering Logic (Equivalent to python generate_catalog.py categories)
// ═══════════════════════════════════════════════════════════════════════════════

List<ManifestItem> _filterCategory(List<ManifestItem> all, String categorySlug) {
  final s = categorySlug.toLowerCase();
  
  if (s == 'all') {
    return all;
  }
  
  return all.where((item) => FilterUtils.matchesCategorySlug(item, s)).toList();
}

// ═══════════════════════════════════════════════════════════════════════════════
// UI Grid Category Aliases
// ═══════════════════════════════════════════════════════════════════════════════

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
