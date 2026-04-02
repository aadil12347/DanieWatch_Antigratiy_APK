import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import '../domain/models/manifest_item.dart';
import '../data/local/manifest_dao.dart';
import '../data/clients/tmdb_client.dart';

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

/// Stale-while-revalidate manifest sync engine.
///
/// On app open:
///   1. Read from SQLite immediately → render cached content
///   2. Background: fetch from GitHub → parse index.json
///   3. Enrich items with TMDB trending/popular data
///   4. Update SQLite, rebuild FTS index, notify listeners
class ManifestSyncEngine {
  ManifestSyncEngine._();
  static final ManifestSyncEngine instance = ManifestSyncEngine._();

  final ManifestDao _dao = ManifestDao();
  final _updateController = StreamController<Manifest>.broadcast();

  Stream<Manifest> get onManifestUpdated => _updateController.stream;

  /// Read cached manifest from SQLite (instant, no network).
  Future<Manifest?> readCache() async {
    final manifest = await _dao.readManifest();
    if (manifest != null) {
      _dao.ensureSearchIndex(manifest.items);
    }
    return manifest;
  }

  /// Fetch manifest from GitHub, enrich with TMDB, and update SQLite cache.
  Future<SyncResult> sync() async {
    try {
      final url = Uri.parse('${Env.githubRawBaseUrl}/index.json');
      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch manifest: ${response.statusCode}');
      }

      final jsonMap = jsonDecode(response.body) as Map<String, dynamic>;

      // Handle both formats: { posts: [...] } or { items: [...] }
      List<ManifestItem> items;
      if (jsonMap.containsKey('posts')) {
        items = (jsonMap['posts'] as List)
            .map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (jsonMap.containsKey('items')) {
        items = (jsonMap['items'] as List)
            .map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        items = [];
      }

      // ━━━ TMDB Enrichment: cross-reference trending/popular lists ━━━
      items = await _enrichWithTmdb(items);

      // ━━━ Global Sorting: Year (Latest to Oldest) then ID (Newest first) ━━━
      items.sort((a, b) {
        final yearA = a.releaseYear ?? 0;
        final yearB = b.releaseYear ?? 0;
        if (yearB != yearA) return yearB.compareTo(yearA);
        return b.id.compareTo(a.id); // Higher ID = newer
      });

      final manifest = Manifest(
        items: items,
        generatedAt: (jsonMap['last_updated'] ?? jsonMap['generated_at'])?.toString(),
        version: jsonMap['version']?.toString(),
        totalCount: items.length,
      );

      dev.log('[SyncEngine] Manifest sync complete: ${items.length} items');
      await _dao.saveManifest(manifest, Env.appVersion);
      _updateController.add(manifest);

      return SyncResult(
        updated: true,
        newVersion: manifest.version,
        itemCount: manifest.items.length,
      );
    } catch (e, stack) {
      dev.log('[SyncEngine] Sync failed: $e', error: e, stackTrace: stack);
      
      try {
        await _dao.clearCache();
        dev.log('[SyncEngine] Cleared stale cache, will retry on next sync');
      } catch (_) {}
      
      return SyncResult(updated: false, itemCount: 0, error: e.toString());
    }
  }

  /// Enrich manifest items with TMDB trending/popular data.
  /// Fetches trending + popular for both movies and TV, then cross-references
  /// by TMDB ID to add genre_ids, vote info, language, and poster paths.
  Future<List<ManifestItem>> _enrichWithTmdb(List<ManifestItem> items) async {
    try {
      dev.log('[SyncEngine] Starting TMDB enrichment...');

      // Build index by ID for fast lookup
      final itemIndex = <String, int>{};
      for (int i = 0; i < items.length; i++) {
        itemIndex['${items[i].id}-${items[i].mediaType}'] = i;
      }

      // Fetch TMDB trending and popular lists (2 pages each for movies + TV)
      final tmdbResults = await Future.wait([
        TmdbClient.instance.getTrending('movie', page: 1),
        TmdbClient.instance.getTrending('movie', page: 2),
        TmdbClient.instance.getTrending('tv', page: 1),
        TmdbClient.instance.getTrending('tv', page: 2),
        TmdbClient.instance.getPopular('movie', page: 1),
        TmdbClient.instance.getPopular('movie', page: 2),
        TmdbClient.instance.getPopular('tv', page: 1),
        TmdbClient.instance.getPopular('tv', page: 2),
      ]);

      final trendingMovies = [...tmdbResults[0], ...tmdbResults[1]];
      final trendingTv = [...tmdbResults[2], ...tmdbResults[3]];
      final popularMovies = [...tmdbResults[4], ...tmdbResults[5]];
      final popularTv = [...tmdbResults[6], ...tmdbResults[7]];

      int enrichedCount = 0;

      // Process trending items
      for (final tmdb in [...trendingMovies, ...trendingTv]) {
        final id = tmdb['id'] as int?;
        final mediaType = tmdb['media_type']?.toString() ?? 
            (tmdb['first_air_date'] != null ? 'tv' : 'movie');
        if (id == null) continue;

        final key = '$id-$mediaType';
        final idx = itemIndex[key];
        if (idx == null) continue;

        items[idx] = _enrichItem(items[idx], tmdb, isTrending: true);
        enrichedCount++;
      }

      // Process popular items
      for (final tmdb in popularMovies) {
        final id = tmdb['id'] as int?;
        if (id == null) continue;
        final key = '$id-movie';
        final idx = itemIndex[key];
        if (idx == null) continue;
        items[idx] = _enrichItem(items[idx], tmdb, isPopular: true);
        enrichedCount++;
      }
      for (final tmdb in popularTv) {
        final id = tmdb['id'] as int?;
        if (id == null) continue;
        final key = '$id-tv';
        final idx = itemIndex[key];
        if (idx == null) continue;
        items[idx] = _enrichItem(items[idx], tmdb, isPopular: true);
        enrichedCount++;
      }

      dev.log('[SyncEngine] TMDB enrichment complete: $enrichedCount items enriched');
      return items;
    } catch (e) {
      dev.log('[SyncEngine] TMDB enrichment failed (non-fatal): $e');
      return items; // Return un-enriched items — app still works
    }
  }

  /// Enrich a single ManifestItem with TMDB data
  ManifestItem _enrichItem(ManifestItem item, Map<String, dynamic> tmdb, 
      {bool isTrending = false, bool isPopular = false}) {
    final genreIds = (tmdb['genre_ids'] as List<dynamic>?)
        ?.map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
        .toList();
    final voteAvg = (tmdb['vote_average'] as num?)?.toDouble();
    final voteCount = (tmdb['vote_count'] as num?)?.toInt();
    final origLang = tmdb['original_language']?.toString();
    final originCountry = (tmdb['origin_country'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList();
    final overview = tmdb['overview']?.toString();
    final posterPath = tmdb['poster_path']?.toString();
    final backdropPath = tmdb['backdrop_path']?.toString();

    return item.copyWith(
      genreIds: (genreIds != null && genreIds.isNotEmpty) ? genreIds : null,
      voteAverage: voteAvg != null && voteAvg > 0 ? voteAvg : null,
      voteCount: voteCount != null && voteCount > 0 ? voteCount : null,
      originalLanguage: origLang?.isNotEmpty == true ? origLang : null,
      originCountry: (originCountry != null && originCountry.isNotEmpty) ? originCountry : null,
      overview: (overview != null && overview.isNotEmpty) ? overview : null,
      tmdbPosterPath: posterPath,
      tmdbBackdropPath: backdropPath,
      isTrending: isTrending || item.isTrending,
      isPopular: isPopular || item.isPopular,
    );
  }

  void dispose() {
    _updateController.close();
  }
}

