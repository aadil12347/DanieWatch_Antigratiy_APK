import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/manifest_item.dart';
import '../../core/utils/search_utils.dart';
import '../../data/clients/tmdb_client.dart';
import '../../data/clients/omdb_client.dart';
import '../../data/services/database_sync_service.dart';
import '../../data/repositories/posting_record_repository.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Local Database Synchronizer & Loader Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Triggers remote index.json synchronization from GitHub on startup.
/// Runs independently — does NOT block manifest loading or splash navigation.
/// On success, invalidates localManifestItemsProvider so the UI refreshes
/// with the latest sorted data from the newly downloaded index.
final databaseSyncProvider = FutureProvider<bool>((ref) async {
  dev.log('[DatabaseSyncProvider] Starting background database sync...');

  // Run both syncs in parallel for speed
  final results = await Future.wait([
    DatabaseSyncService.instance.syncIndex(),
    DatabaseSyncService.instance.sync3rdPartyIndex(),
  ]);

  final mainSuccess = results[0];
  final thirdPartySuccess = results[1];

  dev.log('[DatabaseSyncProvider] Sync finished. Main=$mainSuccess, 3rdParty=$thirdPartySuccess');

  if (mainSuccess || thirdPartySuccess) {
    // Refresh all manifest-derived providers with merged data
    ref.invalidate(localManifestItemsProvider);
  }
  return mainSuccess;
});

/// Exposes all ManifestItems loaded from the locally cached database file.
/// Merges main index + 3rd party hosted index, deduplicating by TMDB ID
/// (main index takes priority for duplicate IDs).
/// Loads from cache IMMEDIATELY (even if empty on first launch).
/// Does NOT block on network sync — the sync runs in background and will
/// invalidate this provider when a new index is ready.
final localManifestItemsProvider = FutureProvider<List<ManifestItem>>((ref) async {
  // Load both indexes in parallel
  final results = await Future.wait([
    DatabaseSyncService.instance.loadLocalIndex(),
    DatabaseSyncService.instance.load3rdPartyIndex(),
  ]);

  final mainItems = results[0];
  final thirdPartyItems = results[1];

  // Merge: main index takes priority for duplicate TMDB IDs
  final seenIds = <int>{};
  final merged = <ManifestItem>[];

  for (final item in mainItems) {
    seenIds.add(item.id);
    merged.add(item);
  }

  for (final item in thirdPartyItems) {
    if (!seenIds.contains(item.id)) {
      seenIds.add(item.id);
      merged.add(item);
    }
  }

  dev.log('[localManifestItemsProvider] Loaded ${merged.length} items (${mainItems.length} main + ${thirdPartyItems.length} 3rd party, ${mainItems.length + thirdPartyItems.length - merged.length} dupes removed).');
  return merged;
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

/// Trending content for the Carousel (first 5 sorted items)
final mergedCarouselProvider = FutureProvider<List<ManifestItem>>((ref) async {
  final sorted = await ref.watch(sortedManifestItemsProvider.future);
  return sorted.take(5).toList();
});

/// Top 10 Today list
final mergedTop10Provider = FutureProvider<List<ManifestItem>>((ref) async {
  final sorted = await ref.watch(sortedManifestItemsProvider.future);
  return sorted.take(10).toList();
});

/// Home screen sections compiled locally from the cached database
final homeSectionsProvider = FutureProvider<List<ContentSection>>((ref) async {
  final sorted = await ref.watch(sortedManifestItemsProvider.future);
  final sections = <ContentSection>[];
  
  // 1. Top 10 Today
  final top10 = await ref.watch(mergedTop10Provider.future);
  if (top10.isNotEmpty) {
    sections.add(ContentSection(title: 'Top 10 Today', items: top10, isRanked: true));
  }
  
  // 2. Bollywood / Indian
  final bollywood = _filterCategory(sorted, 'bollywood').take(15).toList();
  if (bollywood.isNotEmpty) {
    sections.add(ContentSection(title: 'Bollywood', items: bollywood));
  }
  
  // 3. Korean
  final korean = _filterCategory(sorted, 'korean').take(15).toList();
  if (korean.isNotEmpty) {
    sections.add(ContentSection(title: 'Korean', items: korean));
  }
  
  // 4. Anime
  final anime = _filterCategory(sorted, 'anime').take(15).toList();
  if (anime.isNotEmpty) {
    sections.add(ContentSection(title: 'Anime', items: anime));
  }
  
  // 5. Hollywood
  final hollywood = _filterCategory(sorted, 'hollywood').take(15).toList();
  if (hollywood.isNotEmpty) {
    sections.add(ContentSection(title: 'Hollywood', items: hollywood));
  }

  // 6. Chinese
  final chinese = _filterCategory(sorted, 'chinese').take(15).toList();
  if (chinese.isNotEmpty) {
    sections.add(ContentSection(title: 'Chinese', items: chinese));
  }

  // 7. Punjabi
  final punjabi = _filterCategory(sorted, 'punjabi').take(15).toList();
  if (punjabi.isNotEmpty) {
    sections.add(ContentSection(title: 'Punjabi', items: punjabi));
  }

  // 8. Pakistani
  final pakistani = _filterCategory(sorted, 'pakistani').take(15).toList();
  if (pakistani.isNotEmpty) {
    sections.add(ContentSection(title: 'Pakistani', items: pakistani));
  }

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
      state = AsyncValue.data(PaginatedCategoryState(
        items: results,
        currentPage: 1,
        hasMore: results.length >= 30, // Page size is 30
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

      state = AsyncValue.data(PaginatedCategoryState(
        items: [...current.items, ...results],
        currentPage: nextPage,
        isLoadingMore: false,
        hasMore: results.length >= 30,
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
    'Indian': 'indian',
    'Bollywood': 'bollywood',
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
