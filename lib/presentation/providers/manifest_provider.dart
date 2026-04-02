import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/manifest_item.dart';
import '../../domain/policies/visibility_policy.dart';
import '../../offline/sync_engine.dart';

/// Provides the Manifest from local cache + background sync.
class ManifestNotifier extends AsyncNotifier<Manifest?> {
  StreamSubscription<Manifest>? _sub;

  @override
  Future<Manifest?> build() async {
    // 1. Listen for updates BEFORE reading cache
    _sub = ManifestSyncEngine.instance.onManifestUpdated.listen((manifest) {
      state = AsyncValue.data(manifest);
    });
    ref.onDispose(() => _sub?.cancel());

    // 2. Read from SQLite immediately to have some initial state
    final cached = await ManifestSyncEngine.instance.readCache();

    // 3. Mandatory Background Sync — do not block the UI if we have cache
    if (cached == null) {
      // Must wait for first sync if nothing is cached
      final result = await ManifestSyncEngine.instance.sync();
      if (result.error != null) {
        throw Exception('Failed to load catalog: ${result.error}');
      }
      return ManifestSyncEngine.instance.readCache();
    } else {
      // Return cached immediately, then sync in background
      ManifestSyncEngine.instance.sync().then((result) {
        if (result.error != null) {
          // Log sync background error but don't disrupt current view
        }
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

/// Provides all manifest items
final allItemsProvider = Provider<List<ManifestItem>>((ref) {
  return ref.watch(manifestProvider).valueOrNull?.items ?? [];
});

/// Provides trending items
final trendingProvider = Provider<List<ManifestItem>>((ref) {
  final items = ref.watch(allItemsProvider);
  return VisibilityPolicy.getTrending(items, limit: 10);
});

/// Provides popular items (TMDB enriched)
final popularProvider = Provider<List<ManifestItem>>((ref) {
  final items = ref.watch(allItemsProvider);
  return VisibilityPolicy.getPopular(items, limit: 20);
});

/// Provides top rated items
final topRatedProvider = Provider<List<ManifestItem>>((ref) {
  final items = ref.watch(allItemsProvider);
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

/// Provides anime only
final animeProvider = Provider<List<ManifestItem>>((ref) {
  final items = ref.watch(allItemsProvider);
  return VisibilityPolicy.filterAnime(items);
});

/// Provides Korean content only
final koreanProvider = Provider<List<ManifestItem>>((ref) {
  final items = ref.watch(allItemsProvider);
  return VisibilityPolicy.filterKorean(items);
});

/// Provides Bollywood/Hindi content
final bollywoodProvider = Provider<List<ManifestItem>>((ref) {
  final items = ref.watch(allItemsProvider);
  return VisibilityPolicy.filterBollywood(items);
});

/// Provides Hollywood/English content
final hollywoodProvider = Provider<List<ManifestItem>>((ref) {
  final items = ref.watch(allItemsProvider);
  return VisibilityPolicy.filterHollywood(items);
});

/// Genre-based section data for home screen
class ContentSection {
  final String title;
  final List<ManifestItem> items;
  const ContentSection({required this.title, required this.items});
}

/// Provides organized content sections for the home screen
final homeSectionsProvider = Provider<List<ContentSection>>((ref) {
  final all = ref.watch(allItemsProvider);
  if (all.isEmpty) return [];

  final sections = <ContentSection>[];

  // Trending (TMDB enriched or year-based fallback)
  final trending = VisibilityPolicy.getTrending(all, limit: 10);
  if (trending.isNotEmpty) {
    sections.add(ContentSection(title: 'Trending Now', items: trending));
  }

  // Popular (TMDB enriched)
  final popular = VisibilityPolicy.getPopular(all, limit: 20);
  if (popular.isNotEmpty) {
    sections.add(ContentSection(title: 'Popular', items: popular));
  }

  // Recently Added (by year)
  final recentlyAdded = VisibilityPolicy.getRecentlyAdded(all, limit: 20);
  if (recentlyAdded.isNotEmpty) {
    sections.add(ContentSection(title: 'Recently Added', items: recentlyAdded));
  }

  // Bollywood (Hindi language from index.json)
  final bollywood = VisibilityPolicy.filterBollywood(all);
  if (bollywood.length >= 3) {
    sections.add(ContentSection(
        title: 'Bollywood', items: bollywood.take(20).toList()));
  }

  // Hollywood (English language)
  final hollywood = VisibilityPolicy.filterHollywood(all);
  if (hollywood.length >= 3) {
    sections.add(ContentSection(
        title: 'Hollywood', items: hollywood.take(20).toList()));
  }

  // Top Rated
  final topRated = VisibilityPolicy.getTopRated(all, limit: 20);
  if (topRated.isNotEmpty) {
    sections.add(ContentSection(title: 'Top Rated', items: topRated));
  }

  // Anime (needs TMDB enrichment for genre_ids + original_language)
  final anime = VisibilityPolicy.filterAnime(all);
  if (anime.isNotEmpty) {
    sections
        .add(ContentSection(title: 'Anime', items: anime.take(20).toList()));
  }

  // Korean (needs TMDB enrichment for original_language/origin_country)
  final korean = VisibilityPolicy.filterKorean(all);
  if (korean.isNotEmpty) {
    sections
        .add(ContentSection(title: 'Korean', items: korean.take(20).toList()));
  }

  // Genre-based sections (only for TMDB-enriched items with genre_ids)
  final genreMap = {
    28: 'Action',
    35: 'Comedy',
    18: 'Drama',
    27: 'Horror',
    878: 'Sci-Fi',
    10749: 'Romance',
    53: 'Thriller',
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
