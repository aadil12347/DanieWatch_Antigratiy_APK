import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/manifest_item.dart';
import '../../domain/policies/visibility_policy.dart';
import '../../offline/sync_engine.dart';
import '../../data/local/category_storage.dart';
import '../../data/repositories/posting_record_repository.dart';
import '../../data/repositories/github_top_content_repository.dart';

/// Apply posting-record priority sort to any list of ManifestItems.
/// This is the SINGLE source of truth for sort order across all tabs.
Future<List<ManifestItem>> _applyPostingRecordSort(List<ManifestItem> items) async {
  final priorityMap = await PostingRecordRepository.instance.buildPriorityMap();
  items.sort((a, b) {
    final yearA = a.releaseYear ?? 0;
    final yearB = b.releaseYear ?? 0;
    // 1. Year DESC (2026 before 2025)
    if (yearB != yearA) return yearB.compareTo(yearA);
    // 2. Within same year: posting_record items first (latest batch on top)
    final keyA = '${a.id}-${a.mediaType}';
    final keyB = '${b.id}-${b.mediaType}';
    final prA = priorityMap[keyA];
    final prB = priorityMap[keyB];
    final inPrA = prA != null;
    final inPrB = prB != null;
    if (inPrA && !inPrB) return -1;
    if (!inPrA && inPrB) return 1;
    if (inPrA && inPrB) return prA.compareTo(prB);
    // 3. Neither in PR: sort by ID DESC
    return b.id.compareTo(a.id);
  });
  return items;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Fixed-Slot Merge Algorithm
// ═══════════════════════════════════════════════════════════════════════════════
/// Merges GitHub-curated items (with fixed positions) into TMDB items.
///
/// Rules:
/// 1. GitHub ALWAYS wins position — file "3_normal_movie_X" → slot 3
/// 2. No duplicates — if a movie exists in both GitHub AND TMDB, only show GitHub version
/// 3. Fixed slots — exactly [totalSlots] items output
///
/// Returns a list of exactly [totalSlots] items (or fewer if not enough data).
List<ManifestItem> _mergeWithFixedSlots({
  required Map<int, ManifestItem> githubItems,
  required List<ManifestItem> tmdbItems,
  required int totalSlots,
}) {
  // Step 1: Create fixed slots array (null = empty)
  final slots = List<ManifestItem?>.filled(totalSlots, null);

  // Step 2: Place GitHub items at their exact positions (1-indexed → 0-indexed)
  for (final entry in githubItems.entries) {
    final slotIndex = entry.key - 1; // Convert 1-indexed to 0-indexed
    if (slotIndex >= 0 && slotIndex < totalSlots) {
      slots[slotIndex] = entry.value;
    }
  }

  // Step 3: Build exclusion set of TMDB IDs that are already placed by GitHub
  final githubTmdbIds = githubItems.values.map((item) => item.id).toSet();

  // Step 4: Filter TMDB items to remove duplicates
  final tmdbFiltered = tmdbItems
      .where((item) => !githubTmdbIds.contains(item.id))
      .toList();

  // Step 5: Fill remaining empty slots with TMDB items (in order)
  int tmdbIndex = 0;
  for (int i = 0; i < totalSlots; i++) {
    if (slots[i] == null && tmdbIndex < tmdbFiltered.length) {
      slots[i] = tmdbFiltered[tmdbIndex++];
    }
  }

  // Step 6: Return non-null items (preserving slot order)
  return slots.whereType<ManifestItem>().toList();
}

/// Provides the Manifest from local cache + background sync.
class ManifestNotifier extends AsyncNotifier<Manifest?> {
  StreamSubscription<Manifest>? _sub;

  @override
  Future<Manifest?> build() async {
    _sub = ManifestSyncEngine.instance.onManifestUpdated.listen((manifest) {
      state = AsyncValue.data(manifest);
    });
    ref.onDispose(() => _sub?.cancel());

    final cached = await ManifestSyncEngine.instance.readCache();

    if (cached == null) {
      final result = await ManifestSyncEngine.instance.sync();
      if (result.error != null) {
        throw Exception('Failed to load catalog: ${result.error}');
      }
      return ManifestSyncEngine.instance.readCache();
    } else {
      ManifestSyncEngine.instance.sync().then((result) {
        if (result.error != null) {}
      });
      return cached;
    }
  }

  Future<void> refresh() async {
    final result = await ManifestSyncEngine.instance.sync();
    if (result.error != null) {
      throw Exception('Failed to refresh: ${result.error}');
    }
  }
}

final manifestProvider = AsyncNotifierProvider<ManifestNotifier, Manifest?>(
    () => ManifestNotifier());

/// Provides the visibility index for quick lookups
final manifestIndexProvider = Provider<Map<String, ManifestItem>>((ref) {
  final manifest = ref.watch(manifestProvider).valueOrNull;
  if (manifest == null) return {};
  return VisibilityPolicy.buildIndex(manifest.items);
});

/// Provides all manifest items from index.json (for Explore page)
final globalItemsProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(manifestProvider);
  final items = await CategoryStorage.instance.loadCategory(CategoryStorage.indexFile);
  return _applyPostingRecordSort(items);
});

/// Synonym for globalItemsProvider for backward compatibility
final allItemsProvider = Provider<List<ManifestItem>>((ref) {
  return ref.watch(globalItemsProvider).valueOrNull ?? [];
});

/// Provides trending items (from index.json) — used as TMDB fallback source
final trendingProvider = FutureProvider<List<ManifestItem>>((ref) async {
  final items = await ref.watch(globalItemsProvider.future);
  return VisibilityPolicy.getTrending(items, limit: 10);
});

/// Provides popular items (from index.json)
final popularProvider = FutureProvider<List<ManifestItem>>((ref) async {
  final items = await ref.watch(globalItemsProvider.future);
  return VisibilityPolicy.getPopular(items, limit: 20);
});

/// Provides top rated items (from index.json)
final topRatedProvider = FutureProvider<List<ManifestItem>>((ref) async {
  final items = await ref.watch(globalItemsProvider.future);
  return VisibilityPolicy.getTopRated(items, limit: 20);
});

/// Provides recently added items
final recentlyAddedProvider = Provider<List<ManifestItem>>((ref) {
  final items = ref.watch(allItemsProvider);
  return VisibilityPolicy.getRecentlyAdded(items, limit: 20);
});

/// Provides movies only
final moviesProvider = Provider<List<ManifestItem>>((ref) {
  final items = ref.watch(allItemsProvider);
  return VisibilityPolicy.filterMovies(items);
});

/// Provides TV only
final tvShowsProvider = Provider<List<ManifestItem>>((ref) {
  final items = ref.watch(allItemsProvider);
  return VisibilityPolicy.filterTv(items);
});

/// Provides anime only — loads + applies posting-record sort
final animeProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(manifestProvider);
  final items = await CategoryStorage.instance.loadCategory(CategoryStorage.animeFile);
  return _applyPostingRecordSort(items);
});

/// Provides Korean content — loads + applies posting-record sort
final koreanProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(manifestProvider);
  final items = await CategoryStorage.instance.loadCategory(CategoryStorage.koreanFile);
  return _applyPostingRecordSort(items);
});

/// Provides Bollywood/Hindi — loads + applies posting-record sort
final bollywoodProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(manifestProvider);
  final items = await CategoryStorage.instance.loadCategory(CategoryStorage.bollywoodFile);
  return _applyPostingRecordSort(items);
});

/// Provides Hollywood — loads + applies posting-record sort
final hollywoodProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(manifestProvider);
  final items = await CategoryStorage.instance.loadCategory(CategoryStorage.hollywoodFile);
  return _applyPostingRecordSort(items);
});

/// Provides Chinese — loads + applies posting-record sort
final chineseProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(manifestProvider);
  final items = await CategoryStorage.instance.loadCategory(CategoryStorage.chineseFile);
  return _applyPostingRecordSort(items);
});

/// Provides Punjabi — loads + applies posting-record sort
final punjabiProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(manifestProvider);
  final items = await CategoryStorage.instance.loadCategory(CategoryStorage.punjabiFile);
  return _applyPostingRecordSort(items);
});

/// Provides Pakistani — loads + applies posting-record sort
final pakistaniProvider = FutureProvider<List<ManifestItem>>((ref) async {
  ref.watch(manifestProvider);
  final items = await CategoryStorage.instance.loadCategory(CategoryStorage.pakistaniFile);
  return _applyPostingRecordSort(items);
});

// ═══════════════════════════════════════════════════════════════════════════════
// GitHub Top Content Providers (Top 5 Carousel + Top 10 Section)
// ═══════════════════════════════════════════════════════════════════════════════

/// Fetches GitHub Top 5 curated items {position: ManifestItem}
final githubTop5Provider = FutureProvider<Map<int, ManifestItem>>((ref) async {
  return GitHubTopContentRepository.instance.fetchTop5();
});

/// Fetches GitHub Top 10 curated items {position: ManifestItem}
final githubTop10Provider = FutureProvider<Map<int, ManifestItem>>((ref) async {
  return GitHubTopContentRepository.instance.fetchTop10();
});

/// Merged carousel data: GitHub Top 5 (fixed positions) + TMDB trending (fill gaps).
/// Always outputs exactly 5 items with no duplicates.
final mergedCarouselProvider = FutureProvider<List<ManifestItem>>((ref) async {
  // Fetch both data sources in parallel
  final githubTop5 = await ref.watch(githubTop5Provider.future);
  final tmdbTrending = await ref.watch(trendingProvider.future);

  return _mergeWithFixedSlots(
    githubItems: githubTop5,
    tmdbItems: tmdbTrending,
    totalSlots: 5,
  );
});

/// Merged Top 10 data: GitHub Top 10 (fixed positions) + TMDB trending (fill gaps).
/// Always outputs exactly 10 items with no duplicates.
final mergedTop10Provider = FutureProvider<List<ManifestItem>>((ref) async {
  final githubTop10 = await ref.watch(githubTop10Provider.future);
  final tmdbTrending = await ref.watch(trendingProvider.future);

  return _mergeWithFixedSlots(
    githubItems: githubTop10,
    tmdbItems: tmdbTrending,
    totalSlots: 10,
  );
});


/// Genre-based section data for home screen
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

/// Provides organized content sections for the home screen.
/// Top 10 section uses merged GitHub + TMDB data with fixed-slot positioning.
final homeSectionsProvider = FutureProvider<List<ContentSection>>((ref) async {
  final all = await ref.watch(globalItemsProvider.future);
  if (all.isEmpty) return [];

  final sections = <ContentSection>[];

  // 1. Top 10 Today — merged from GitHub Top 10 + TMDB trending (fixed slots)
  final mergedTop10 = await ref.watch(mergedTop10Provider.future);
  if (mergedTop10.isNotEmpty) {
    sections.add(ContentSection(
      title: 'Top 10 Today',
      items: mergedTop10,
      isRanked: true,
    ));
  }

  // 2. Bollywood
  final bollywood = VisibilityPolicy.filterBollywood(all);
  if (bollywood.isNotEmpty) {
    sections.add(ContentSection(
      title: 'Bollywood',
      items: bollywood.take(20).toList(),
    ));
  }

  // 3. Korean
  final korean = VisibilityPolicy.filterKorean(all);
  if (korean.isNotEmpty) {
    sections.add(ContentSection(
      title: 'Korean',
      items: korean.take(20).toList(),
    ));
  }

  // 4. Anime
  final anime = VisibilityPolicy.filterAnime(all);
  if (anime.isNotEmpty) {
    sections.add(ContentSection(
      title: 'Anime',
      items: anime.take(20).toList(),
    ));
  }

  // 5. Top Rated (Popular fallback)
  final topRated = VisibilityPolicy.getTopRated(all, limit: 20);
  if (topRated.isNotEmpty) {
    sections.add(ContentSection(title: 'Top Rated', items: topRated));
  }

  // 6. Genres
  final genreMap = {
    28: 'Action',
    27: 'Horror',
    35: 'Comedy',
    10749: 'Romance',
    18: 'Drama',
    53: 'Thriller',
    878: 'Sci-Fi/Fantasy',
    99: 'Documentary',
  };

  for (final entry in genreMap.entries) {
    final genreItems = VisibilityPolicy.filterByGenre(all, entry.key);
    if (genreItems.length >= 5) {
      sections.add(ContentSection(
        title: entry.value,
        items: genreItems.take(20).toList(),
      ));
    }
  }

  return sections;
});
