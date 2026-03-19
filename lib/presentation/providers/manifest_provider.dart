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

    // 2. Read from SQLite immediately
    final cached = await ManifestSyncEngine.instance.readCache();

    // 3. Background sync
    // If cache is empty, we must await the sync to either get data or fail!
    // Otherwise it silently succeeds with null and we have a blank screen.
    if (cached == null) {
      final result = await ManifestSyncEngine.instance.sync();
      if (result.error != null) {
        throw Exception('Failed to load catalog: ${result.error}');
      }
      return ManifestSyncEngine.instance.readCache(); 
    } else {
      // Background update
      ManifestSyncEngine.instance.sync().then((result) {
        if (result.error != null) {
           // We might log this, but we have cached data so no need to blow up the UI
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

final manifestProvider =
    AsyncNotifierProvider<ManifestNotifier, Manifest?>(() => ManifestNotifier());

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

  final trending = VisibilityPolicy.getTrending(all, limit: 10);
  if (trending.isNotEmpty) {
    sections.add(ContentSection(title: 'Trending Now', items: trending));
  }

  final topRated = VisibilityPolicy.getTopRated(all, limit: 20);
  if (topRated.isNotEmpty) {
    sections.add(ContentSection(title: 'Top Rated', items: topRated));
  }

  final anime = VisibilityPolicy.filterAnime(all);
  if (anime.isNotEmpty) {
    sections.add(ContentSection(title: 'Anime', items: anime.take(20).toList()));
  }

  final korean = VisibilityPolicy.filterKorean(all);
  if (korean.isNotEmpty) {
    sections.add(ContentSection(title: 'Korean', items: korean.take(20).toList()));
  }

  // Genre-based sections
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
