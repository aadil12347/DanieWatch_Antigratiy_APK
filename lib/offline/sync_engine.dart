import 'dart:async';
import 'dart:developer' as dev;

import '../data/clients/github_catalog_client.dart';
import '../data/clients/tmdb_client.dart';
import '../data/local/manifest_dao.dart';
import '../domain/models/catalog_page.dart';
import '../domain/models/manifest_item.dart';

/// Result of a sync operation
class SyncResult {
  final bool updated;
  final String? newVersion;
  final int itemCount;
  final String? error;

  const SyncResult({
    required this.updated,
    this.newVersion,
    required this.itemCount,
    this.error,
  });
}

/// Sync engine for Home Sections and TMDB enrichment.
///
/// On app open:
///   1. Read cached home sections → render instantly
///   2. Background: fetch meta.json → compare version
///   3. If changed: re-fetch home sections
///   4. Enrich visible items with TMDB trending/popular data
///   5. Update SQLite caches, notify listeners
///
/// Note: Actual full catalog sync is handled by SyncService using delta updates.
/// This engine is now just for Home sections + TMDB data.
class PaginatedSyncEngine {
  PaginatedSyncEngine._();
  static final PaginatedSyncEngine instance = PaginatedSyncEngine._();

  final ManifestDao _dao = ManifestDao();
  final GitHubCatalogClient _client = GitHubCatalogClient.instance;

  final _homeSectionsController = StreamController<HomeSectionsData>.broadcast();

  Stream<HomeSectionsData> get onHomeSectionsUpdated => _homeSectionsController.stream;

  // ═══════════════════════════════════════════════════════════════════════════
  // READ CACHE (instant, no network)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Read cached home sections from SQLite (instant).
  Future<HomeSectionsData?> readCachedHomeSections() async {
    return _dao.loadHomeSections();
  }

  /// Read cached catalog metadata.
  Future<CatalogMeta?> readCachedMeta() async {
    return _dao.loadCatalogMeta();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC (background, with network)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Main sync: fetch meta → compare version → refresh home sections.
  Future<SyncResult> sync() async {
    try {
      // Step 1: Fetch meta.json (~500 bytes)
      final remoteMeta = await _client.fetchMeta();
      if (remoteMeta == null) {
        return const SyncResult(
          updated: false,
          itemCount: 0,
          error: 'Failed to fetch catalog metadata',
        );
      }

      // Step 2: Compare version
      final cachedVersion = await _dao.getCatalogVersion();
      final versionChanged = cachedVersion != remoteMeta.version;

      if (!versionChanged) {
        dev.log('[SyncEngine] Catalog version unchanged: ${remoteMeta.version}');
        // Still refresh TMDB trending/popular (changes daily)
        _refreshTmdbEnrichment();
        return SyncResult(
          updated: false,
          newVersion: remoteMeta.version,
          itemCount: remoteMeta.totalItems,
        );
      }

      dev.log('[SyncEngine] Catalog version changed: $cachedVersion → ${remoteMeta.version}');

      // Step 3: Save new metadata
      await _dao.saveCatalogMeta(remoteMeta);

      // Step 4: Fetch home sections
      final homeSections = await _client.fetchHomeSections();

      // Step 5: Cache and broadcast home sections
      if (homeSections != null) {
        await _dao.saveHomeSections(homeSections, remoteMeta.version);
        _homeSectionsController.add(homeSections);
        dev.log('[SyncEngine] Home sections cached: ${homeSections.sections.length} sections, ${homeSections.carousel.length} carousel items');
      }

      // Old page caches are no longer used since categories come from SQLite
      await _dao.invalidateAllPages();

      // Step 6: TMDB enrichment for visible items
      _refreshTmdbEnrichment();

      dev.log('[SyncEngine] Sync complete: ${remoteMeta.totalItems} items, version ${remoteMeta.version}');

      return SyncResult(
        updated: true,
        newVersion: remoteMeta.version,
        itemCount: remoteMeta.totalItems,
      );
    } catch (e, stack) {
      dev.log('[SyncEngine] Sync failed: $e', error: e, stackTrace: stack);
      return SyncResult(updated: false, itemCount: 0, error: e.toString());
    }
  }

  // ─── Internal Helpers ───────────────────────────────────────────────────

  /// Refresh TMDB trending/popular enrichment for cached home sections.
  /// Fire-and-forget — doesn't block sync.
  void _refreshTmdbEnrichment() {
    _doTmdbEnrichment().catchError((e) {
      dev.log('[SyncEngine] TMDB enrichment failed: $e');
    });
  }

  Future<void> _doTmdbEnrichment() async {
    try {
      final homeSections = await _dao.loadHomeSections();
      if (homeSections == null) return;

      // Fetch TMDB trending + popular for movies and TV
      final results = await Future.wait([
        TmdbClient.instance.getTrendingPages('movie', 3),
        TmdbClient.instance.getTrendingPages('tv', 3),
        TmdbClient.instance.getPopularPages('movie', 3),
        TmdbClient.instance.getPopularPages('tv', 3),
      ]);

      final trendingMovies = results[0];
      final trendingTv = results[1];
      final popularMovies = results[2];
      final popularTv = results[3];

      // Build TMDB lookup map
      final tmdbMap = <String, Map<String, dynamic>>{};
      final trendingSet = <String>{};
      final popularSet = <String>{};
      final trendingRanks = <String, int>{};

      for (int i = 0; i < trendingMovies.length; i++) {
        final id = trendingMovies[i]['id']?.toString();
        if (id == null) continue;
        final key = '$id-movie';
        tmdbMap[key] = trendingMovies[i];
        trendingSet.add(key);
        trendingRanks[key] = i + 1;
      }
      for (int i = 0; i < trendingTv.length; i++) {
        final id = trendingTv[i]['id']?.toString();
        if (id == null) continue;
        final key = '$id-tv';
        tmdbMap.putIfAbsent(key, () => trendingTv[i]);
        trendingSet.add(key);
        trendingRanks.putIfAbsent(key, () => i + 1);
      }
      for (final m in popularMovies) {
        final id = m['id']?.toString();
        if (id == null) continue;
        tmdbMap.putIfAbsent('$id-movie', () => m);
        popularSet.add('$id-movie');
      }
      for (final m in popularTv) {
        final id = m['id']?.toString();
        if (id == null) continue;
        tmdbMap.putIfAbsent('$id-tv', () => m);
        popularSet.add('$id-tv');
      }

      // Enrich carousel items
      final enrichedCarousel = _enrichItems(
          homeSections.carousel, tmdbMap, trendingSet, popularSet, trendingRanks);

      // Enrich section items
      final enrichedSections = homeSections.sections.map((section) {
        return HomeSection(
          title: section.title,
          items: _enrichItems(
              section.items, tmdbMap, trendingSet, popularSet, trendingRanks),
          isRanked: section.isRanked,
        );
      }).toList();

      final enriched = HomeSectionsData(
        carousel: enrichedCarousel,
        sections: enrichedSections,
      );

      final version = await _dao.getCatalogVersion();
      await _dao.saveHomeSections(enriched, version);
      _homeSectionsController.add(enriched);

      dev.log('[SyncEngine] TMDB enrichment applied to home sections');
    } catch (e) {
      dev.log('[SyncEngine] TMDB enrichment error: $e');
    }
  }

  /// Enrich a list of ManifestItems with TMDB data.
  List<ManifestItem> _enrichItems(
    List<ManifestItem> items,
    Map<String, Map<String, dynamic>> tmdbMap,
    Set<String> trendingSet,
    Set<String> popularSet,
    Map<String, int> trendingRanks,
  ) {
    return items.map((item) {
      final key = '${item.id}-${item.mediaType}';
      final tmdb = tmdbMap[key];
      if (tmdb == null) return item;

      final genreIds = (tmdb['genre_ids'] as List<dynamic>?)
          ?.map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
          .toList();
      final posterPath = tmdb['poster_path']?.toString();
      final backdropPath = tmdb['backdrop_path']?.toString();
      final voteAvg = (tmdb['vote_average'] as num?)?.toDouble();
      final voteCount = (tmdb['vote_count'] as num?)?.toInt();
      final origLang = tmdb['original_language']?.toString();
      final originCountry = (tmdb['origin_country'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList();
      final overview = tmdb['overview']?.toString();

      return item.copyWith(
        genreIds: (genreIds != null && genreIds.isNotEmpty) ? genreIds : null,
        voteAverage: voteAvg != null && voteAvg > 0 ? voteAvg : null,
        voteCount: voteCount != null && voteCount > 0 ? voteCount : null,
        originalLanguage: origLang?.isNotEmpty == true ? origLang : null,
        originCountry: (originCountry != null && originCountry.isNotEmpty) ? originCountry : null,
        overview: (overview != null && overview.isNotEmpty) ? overview : null,
        tmdbPosterPath: posterPath,
        tmdbBackdropPath: backdropPath,
        isTrending: trendingSet.contains(key),
        isPopular: popularSet.contains(key),
        trendingRank: trendingRanks[key],
      );
    }).toList();
  }

  void dispose() {
    _homeSectionsController.close();
  }
}
