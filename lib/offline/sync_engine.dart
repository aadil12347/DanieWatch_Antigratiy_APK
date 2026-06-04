import 'dart:async';
import 'dart:developer' as dev;

import '../data/clients/github_catalog_client.dart';
import '../data/clients/tmdb_client.dart';
import '../data/local/manifest_dao.dart';
import '../data/local/search_database.dart';
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
///   4. Build dynamic sections from TMDB + SQLite index
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
        // Still rebuild dynamic sections (TMDB data changes daily)
        _buildDynamicSections();
        return SyncResult(
          updated: false,
          newVersion: remoteMeta.version,
          itemCount: remoteMeta.totalItems,
        );
      }

      dev.log('[SyncEngine] Catalog version changed: $cachedVersion → ${remoteMeta.version}');

      // Step 3: Save new metadata
      await _dao.saveCatalogMeta(remoteMeta);

      // Step 4: Fetch home sections (for carousel)
      final homeSections = await _client.fetchHomeSections();

      // Step 5: Cache and broadcast home sections
      if (homeSections != null) {
        await _dao.saveHomeSections(homeSections, remoteMeta.version);
        _homeSectionsController.add(homeSections);
        dev.log('[SyncEngine] Home sections cached: ${homeSections.sections.length} sections, ${homeSections.carousel.length} carousel items');
      }

      // Old page caches are no longer used since categories come from SQLite
      await _dao.invalidateAllPages();

      // Step 6: Build dynamic sections from TMDB + SQLite
      _buildDynamicSections();

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

  /// Build dynamic home sections — fire-and-forget, doesn't block sync.
  void _buildDynamicSections() {
    _doBuildDynamicSections().catchError((e) {
      dev.log('[SyncEngine] Dynamic section build failed: $e');
    });
  }

  /// Build home sections dynamically from TMDB + SQLite index.
  ///
  /// Sections built:
  ///   - Top 10 Today (TMDB daily trending → filtered by index)
  ///   - Indian, Korean, Anime, Hollywood, Punjabi, Pakistani, Chinese (from SQLite)
  ///   - Popular, Top Rated (TMDB → filtered by index)
  ///   - Action, Thriller, Romance, Comedy (genre-based from SQLite)
  Future<void> _doBuildDynamicSections() async {
    try {
      // Wait for SQLite to be ready
      int waitCount = 0;
      while (!SearchDatabase.instance.isReady && waitCount < 50) {
        await Future.delayed(const Duration(milliseconds: 200));
        waitCount++;
      }
      if (!SearchDatabase.instance.isReady) {
        dev.log('[SyncEngine] SQLite not ready after 10s, skipping dynamic sections');
        return;
      }

      final homeSections = await _dao.loadHomeSections();
      if (homeSections == null) return;

      // ═══ Step 1: Fetch TMDB data in parallel ═══
      final tmdbResults = await Future.wait([
        TmdbClient.instance.getTrending('movie', timeWindow: 'day'),       // 0
        TmdbClient.instance.getTrending('tv', timeWindow: 'day'),          // 1
        TmdbClient.instance.getPopularPages('movie', 1),                   // 2
        TmdbClient.instance.getPopularPages('tv', 1),                      // 3
        TmdbClient.instance.getTopRatedPages('movie', 1),                  // 4
        TmdbClient.instance.getTopRatedPages('tv', 1),                     // 5
      ]);

      final trendingMovies = tmdbResults[0];
      final trendingTv = tmdbResults[1];
      final popularMovies = tmdbResults[2];
      final popularTv = tmdbResults[3];
      final topRatedMovies = tmdbResults[4];
      final topRatedTv = tmdbResults[5];

      // ═══ Step 2: Collect all TMDB IDs and check which exist in index ═══
      final allTmdbItems = <Map<String, dynamic>>[];
      allTmdbItems.addAll(trendingMovies);
      allTmdbItems.addAll(trendingTv);
      allTmdbItems.addAll(popularMovies);
      allTmdbItems.addAll(popularTv);
      allTmdbItems.addAll(topRatedMovies);
      allTmdbItems.addAll(topRatedTv);

      final allTmdbIds = allTmdbItems
          .map((item) => (item['id'] as num?)?.toInt())
          .where((id) => id != null)
          .cast<int>()
          .toSet()
          .toList();

      final existingIds = await SearchDatabase.instance.existsByTmdbIds(allTmdbIds);
      dev.log('[SyncEngine] ${existingIds.length}/${allTmdbIds.length} TMDB items exist in index');

      // ═══ Step 3: Build Top 10 Today ═══
      final top10Items = _buildTop10FromTmdb(
        trendingMovies: trendingMovies,
        trendingTv: trendingTv,
        existingIds: existingIds,
      );

      // ═══ Step 4: Build TMDB-sourced sections (filtered by index) ═══
      final popularItems = _buildFilteredTmdbSection(
        movies: popularMovies,
        tv: popularTv,
        existingIds: existingIds,
        limit: 15,
      );

      final topRatedItems = _buildFilteredTmdbSection(
        movies: topRatedMovies,
        tv: topRatedTv,
        existingIds: existingIds,
        limit: 15,
      );

      // ═══ Step 5: Build category sections from SQLite ═══
      final categoryResults = await Future.wait([
        SearchDatabase.instance.getLatestByCategory('indian', limit: 15),
        SearchDatabase.instance.getLatestByCategory('korean', limit: 15),
        SearchDatabase.instance.getLatestByCategory('anime', limit: 15),
        SearchDatabase.instance.getLatestByCategory('hollywood', limit: 15),
        SearchDatabase.instance.getLatestByCategory('punjabi', limit: 15),
        SearchDatabase.instance.getLatestByCategory('pakistani', limit: 15),
        SearchDatabase.instance.getLatestByCategory('chinese', limit: 15),
      ]);

      // ═══ Step 6: Build genre sections from SQLite ═══
      final genreResults = await Future.wait([
        SearchDatabase.instance.getLatestByGenre('Action', limit: 15),
        SearchDatabase.instance.getLatestByGenre('Thriller', limit: 15),
        SearchDatabase.instance.getLatestByGenre('Romance', limit: 15),
        SearchDatabase.instance.getLatestByGenre('Comedy', limit: 15),
      ]);

      // ═══ Step 7: Convert search results to ManifestItems ═══
      ManifestItem resultToItem(ManifestSearchResult r) {
        return ManifestItem(
          id: r.itemId,
          mediaType: r.mediaType,
          title: r.title,
          posterUrl: r.posterUrl,
          releaseYear: r.releaseYear,
          language: r.languages,
          genres: r.genres,
          originalLanguage: r.originalLanguage,
          originCountry: r.originCountry,
        );
      }

      // ═══ Step 8: Assemble sections list ═══
      final sections = <HomeSection>[];

      // Top 10 Today (always first, ranked)
      if (top10Items.isNotEmpty) {
        sections.add(HomeSection(
          title: 'Top 10 Today',
          items: top10Items,
          isRanked: true,
        ));
      }

      // Category sections
      final categoryNames = ['Indian', 'Korean', 'Anime', 'Hollywood', 'Punjabi', 'Pakistani', 'Chinese'];
      for (int i = 0; i < categoryNames.length; i++) {
        final items = categoryResults[i].map(resultToItem).toList();
        if (items.isNotEmpty) {
          sections.add(HomeSection(title: categoryNames[i], items: items));
        }
      }

      // Popular (TMDB-sourced)
      if (popularItems.isNotEmpty) {
        sections.add(HomeSection(title: 'Popular', items: popularItems));
      }

      // Top Rated (TMDB-sourced)
      if (topRatedItems.isNotEmpty) {
        sections.add(HomeSection(title: 'Top Rated', items: topRatedItems));
      }

      // Genre sections
      final genreNames = ['Action', 'Thriller', 'Romance', 'Comedy'];
      for (int i = 0; i < genreNames.length; i++) {
        final items = genreResults[i].map(resultToItem).toList();
        if (items.isNotEmpty) {
          sections.add(HomeSection(title: genreNames[i], items: items));
        }
      }

      // ═══ Step 9: Enrich carousel with TMDB data ═══
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

      final enrichedCarousel = _enrichItems(
        homeSections.carousel, tmdbMap, trendingSet, popularSet, trendingRanks,
      );

      // ═══ Step 10: Save and broadcast ═══
      final dynamicData = HomeSectionsData(
        carousel: enrichedCarousel,
        sections: sections,
      );

      final version = await _dao.getCatalogVersion();
      await _dao.saveHomeSections(dynamicData, version);
      _homeSectionsController.add(dynamicData);

      dev.log('[SyncEngine] Dynamic sections built: ${sections.length} sections');
    } catch (e, stack) {
      dev.log('[SyncEngine] Dynamic section build error: $e', stackTrace: stack);
    }
  }

  /// Build the Top 10 list from TMDB daily trending, filtered to items in the index.
  List<ManifestItem> _buildTop10FromTmdb({
    required List<Map<String, dynamic>> trendingMovies,
    required List<Map<String, dynamic>> trendingTv,
    required Set<int> existingIds,
  }) {
    // Interleave movies and TV, prioritizing by TMDB trending rank
    final combined = <Map<String, dynamic>>[];
    int mi = 0, ti = 0;
    while (combined.length < 20 && (mi < trendingMovies.length || ti < trendingTv.length)) {
      if (mi < trendingMovies.length) {
        combined.add({...trendingMovies[mi], '_mediaType': 'movie'});
        mi++;
      }
      if (ti < trendingTv.length) {
        combined.add({...trendingTv[ti], '_mediaType': 'tv'});
        ti++;
      }
    }

    // Filter to items in the app index
    final filtered = combined.where((item) {
      final id = (item['id'] as num?)?.toInt();
      return id != null && existingIds.contains(id);
    }).toList();

    // Take top 10
    return filtered.take(10).map((item) {
      final id = (item['id'] as num?)?.toInt() ?? 0;
      final mediaType = item['_mediaType']?.toString() ?? 'movie';
      final posterPath = item['poster_path']?.toString();
      final backdropPath = item['backdrop_path']?.toString();
      return ManifestItem(
        id: id,
        mediaType: mediaType,
        title: (item['title'] ?? item['name'] ?? 'Unknown').toString(),
        posterUrl: posterPath != null ? TmdbClient.posterUrl(posterPath) : null,
        backdropUrl: backdropPath != null ? TmdbClient.backdropUrl(backdropPath) : null,
        voteAverage: (item['vote_average'] as num?)?.toDouble() ?? 0.0,
        voteCount: (item['vote_count'] as num?)?.toInt() ?? 0,
        releaseYear: _extractYear(item['release_date']?.toString() ?? item['first_air_date']?.toString()),
        overview: item['overview']?.toString(),
        originalLanguage: item['original_language']?.toString(),
        tmdbPosterPath: posterPath,
        tmdbBackdropPath: backdropPath,
        isTrending: true,
      );
    }).toList();
  }

  /// Build a section from TMDB data, filtered to items in the index.
  List<ManifestItem> _buildFilteredTmdbSection({
    required List<Map<String, dynamic>> movies,
    required List<Map<String, dynamic>> tv,
    required Set<int> existingIds,
    required int limit,
  }) {
    final combined = <Map<String, dynamic>>[];
    int mi = 0, ti = 0;
    while (combined.length < (limit * 3) && (mi < movies.length || ti < tv.length)) {
      if (mi < movies.length) {
        combined.add({...movies[mi], '_mediaType': 'movie'});
        mi++;
      }
      if (ti < tv.length) {
        combined.add({...tv[ti], '_mediaType': 'tv'});
        ti++;
      }
    }

    final filtered = combined.where((item) {
      final id = (item['id'] as num?)?.toInt();
      return id != null && existingIds.contains(id);
    }).toList();

    return filtered.take(limit).map((item) {
      final id = (item['id'] as num?)?.toInt() ?? 0;
      final mediaType = item['_mediaType']?.toString() ?? 'movie';
      final posterPath = item['poster_path']?.toString();
      final backdropPath = item['backdrop_path']?.toString();
      return ManifestItem(
        id: id,
        mediaType: mediaType,
        title: (item['title'] ?? item['name'] ?? 'Unknown').toString(),
        posterUrl: posterPath != null ? TmdbClient.posterUrl(posterPath) : null,
        backdropUrl: backdropPath != null ? TmdbClient.backdropUrl(backdropPath) : null,
        voteAverage: (item['vote_average'] as num?)?.toDouble() ?? 0.0,
        voteCount: (item['vote_count'] as num?)?.toInt() ?? 0,
        releaseYear: _extractYear(item['release_date']?.toString() ?? item['first_air_date']?.toString()),
        overview: item['overview']?.toString(),
        originalLanguage: item['original_language']?.toString(),
        tmdbPosterPath: posterPath,
        tmdbBackdropPath: backdropPath,
      );
    }).toList();
  }

  /// Extract year from date string like "2025-04-30"
  int? _extractYear(String? dateStr) {
    if (dateStr == null || dateStr.length < 4) return null;
    return int.tryParse(dateStr.substring(0, 4));
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
