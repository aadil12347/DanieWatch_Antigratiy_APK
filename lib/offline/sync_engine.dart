import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import '../domain/models/manifest_item.dart';
import '../data/local/manifest_dao.dart';
import '../data/local/category_storage.dart';
import '../domain/policies/visibility_policy.dart';
import '../data/clients/tmdb_client.dart';
import '../data/repositories/posting_record_repository.dart';

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
      // Snapshot the current index before overwriting (for auto-add comparison)
      await CategoryStorage.instance.snapshotCurrentIndex();

      // ━━━ Fetch index.json + posting_record.json in parallel ━━━
      final indexUrl = Uri.parse('${Env.githubRawBaseUrl}/index.json');
      final results = await Future.wait([
        http.get(indexUrl),
        PostingRecordRepository.instance.fetch(),
      ]);

      final response = results[0] as http.Response;
      // posting_record result is handled by PostingRecordRepository internally

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

      // ━━━ Posting Record Priority Sort ━━━
      // Build priority map from posting_record.json batches.
      // Batches are sorted by batch_id DESC internally, so newest batch content
      // (highest batch number) gets the lowest priority values and appears first.
      final priorityMap = await PostingRecordRepository.instance.buildPriorityMap();

      items.sort((a, b) {
        final yearA = a.releaseYear ?? 0;
        final yearB = b.releaseYear ?? 0;

        // 1. Year DESC (2026 before 2025)
        if (yearB != yearA) return yearB.compareTo(yearA);

        // 2. Within same year: posting_record items first
        final keyA = '${a.id}-${a.mediaType}';
        final keyB = '${b.id}-${b.mediaType}';
        final prA = priorityMap[keyA];
        final prB = priorityMap[keyB];

        final inPrA = prA != null;
        final inPrB = prB != null;

        if (inPrA && !inPrB) return -1; // A is PR item, comes first
        if (!inPrA && inPrB) return 1;  // B is PR item, comes first
        if (inPrA && inPrB) {
          return prA.compareTo(prB); // Both PR: batch order preserved
        }

        // 3. Neither in PR: sort by ID DESC (higher ID = newer)
        return b.id.compareTo(a.id);
      });

      final manifest = Manifest(
        items: items,
        generatedAt: (jsonMap['last_updated'] ?? jsonMap['generated_at'])?.toString(),
        version: jsonMap['version']?.toString(),
        totalCount: items.length,
      );

      dev.log('[SyncEngine] Manifest sync complete: ${items.length} items');
      await _dao.saveManifest(manifest, Env.appVersion);

      // ━━━ Category File Generation (New requirement) ━━━
      await _generateCategoryFiles(items);

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
        await CategoryStorage.instance.clearAll();
        dev.log('[SyncEngine] Cleared stale cache and category files');
      } catch (_) {}
      
      return SyncResult(updated: false, itemCount: 0, error: e.toString());
    }
  }

  /// Partitions items into categories and saves them as JSON files
  Future<void> _generateCategoryFiles(List<ManifestItem> allItems) async {
    try {
      dev.log('[SyncEngine] Generating category files...');
      
      // 1. Global index (everything)
      await CategoryStorage.instance.saveCategory(
        CategoryStorage.indexFile, 
        allItems
      );

      // 2. Bollywood (Indian)
      final bollywood = VisibilityPolicy.filterBollywood(allItems);
      await CategoryStorage.instance.saveCategory(
        CategoryStorage.bollywoodFile, 
        bollywood
      );

      // 4. Korean (KR, JP, CN, etc)
      final korean = VisibilityPolicy.filterKorean(allItems);
      await CategoryStorage.instance.saveCategory(
        CategoryStorage.koreanFile, 
        korean
      );

      // 5. Anime (Animation genre)
      final anime = VisibilityPolicy.filterAnime(allItems);
      await CategoryStorage.instance.saveCategory(
        CategoryStorage.animeFile, 
        anime
      );

      // 6. Hollywood (US/UK/EN)
      final hollywood = VisibilityPolicy.filterHollywood(allItems);
      await CategoryStorage.instance.saveCategory(
        CategoryStorage.hollywoodFile, 
        hollywood
      );

      // 7. Chinese (CN/HK/TW)
      final chinese = VisibilityPolicy.filterChinese(allItems);
      await CategoryStorage.instance.saveCategory(
        CategoryStorage.chineseFile, 
        chinese
      );

      // 8. Punjabi
      final punjabi = VisibilityPolicy.filterPunjabi(allItems);
      await CategoryStorage.instance.saveCategory(
        CategoryStorage.punjabiFile, 
        punjabi
      );

      // 9. Pakistani
      final pakistani = VisibilityPolicy.filterPakistani(allItems);
      await CategoryStorage.instance.saveCategory(
        CategoryStorage.pakistaniFile, 
        pakistani
      );

      dev.log('[SyncEngine] Category files generated successfully');
    } catch (e) {
      dev.log('[SyncEngine] Failed to generate category files: $e', error: e);
    }
  }

  /// Enrich manifest items with TMDB trending/popular data.
  /// Fetches trending + popular for both movies and TV, then cross-references
  /// by TMDB ID to add genre_ids, vote info, language, and poster paths.
  Future<List<ManifestItem>> _enrichWithTmdb(List<ManifestItem> items) async {
    try {
      dev.log('[SyncEngine] Starting deep TMDB enrichment (5 pages each)...');

      // 1. Fetch 5 pages of Trending and Popular (Movies & TV)
      final results = await Future.wait([
        TmdbClient.instance.getTrendingPages('movie', 5),
        TmdbClient.instance.getTrendingPages('tv', 5),
        TmdbClient.instance.getPopularPages('movie', 5),
        TmdbClient.instance.getPopularPages('tv', 5),
      ]);

      final trendingMovies = results[0];
      final trendingTv = results[1];
      final popularMovies = results[2];
      final popularTv = results[3];

      // 2. Build a deduplicated map of all TMDB data found, 
      //    mapping TMDB_ID-MEDIA_TYPE -> Metadata
      //    We use Trending first so it's "source of truth" for metadata if overlaps occur.
      final tmdbMap = <String, Map<String, dynamic>>{};
      
      // Store ranking information
      final trendingRanks = <String, int>{}; // Key -> Rank
      final isPopularSet = <String>{};

      // Process Trending (Preserves rank based on loop index)
      for (int i = 0; i < trendingMovies.length; i++) {
        final tmdb = trendingMovies[i];
        final id = tmdb['id']?.toString();
        if (id == null) continue;
        final key = '$id-movie';
        tmdbMap[key] = tmdb;
        trendingRanks[key] = i + 1;
      }
      for (int i = 0; i < trendingTv.length; i++) {
        final tmdb = trendingTv[i];
        final id = tmdb['id']?.toString();
        if (id == null) continue;
        final key = '$id-tv';
        // If already in movie (unlikely for same ID, but just in case), don't overwrite if it's the wrong type
        if (!tmdbMap.containsKey(key)) {
           tmdbMap[key] = tmdb;
           trendingRanks[key] = i + 1;
        }
      }

      // Process Popular
      for (final tmdb in popularMovies) {
        final id = tmdb['id']?.toString();
        if (id == null) continue;
        final key = '$id-movie';
        tmdbMap.putIfAbsent(key, () => tmdb);
        isPopularSet.add(key);
      }
      for (final tmdb in popularTv) {
        final id = tmdb['id']?.toString();
        if (id == null) continue;
        final key = '$id-tv';
        tmdbMap.putIfAbsent(key, () => tmdb);
        isPopularSet.add(key);
      }

      // 3. Update ALL items in manifest if they exist in our TMDB results
      int enrichedCount = 0;
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final key = '${item.id}-${item.mediaType}';
        
        if (tmdbMap.containsKey(key)) {
          final tmdb = tmdbMap[key]!;
          items[i] = _enrichItem(
            item, 
            tmdb, 
            isTrending: trendingRanks.containsKey(key),
            isPopular: isPopularSet.contains(key),
            rank: trendingRanks[key],
          );
          enrichedCount++;
        } else {
          // Reset trending/popular flags if they are no longer in the top results
          // This ensures the "updated TMDB trending" requirement
          if (item.isTrending || item.isPopular || item.trendingRank != null) {
            items[i] = item.copyWith(
              isTrending: false,
              isPopular: false,
              trendingRank: null, // This will clear the rank
            );
          }
        }
      }

      dev.log('[SyncEngine] TMDB enrichment complete: $enrichedCount items matched/updated');
      return items;
    } catch (e, stack) {
      dev.log('[SyncEngine] TMDB enrichment failed: $e', error: e, stackTrace: stack);
      return items;
    }
  }

  /// Enrich a single ManifestItem with TMDB data
  ManifestItem _enrichItem(ManifestItem item, Map<String, dynamic> tmdb, 
      {bool isTrending = false, bool isPopular = false, int? rank}) {
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
      isTrending: isTrending,
      isPopular: isPopular,
      trendingRank: rank,
    );
  }

  void dispose() {
    _updateController.close();
  }
}

