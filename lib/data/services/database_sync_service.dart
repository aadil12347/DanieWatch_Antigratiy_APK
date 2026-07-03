import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/manifest_item.dart';

/// Service responsible for syncing, caching, and parsing the positional index.json
/// database files from the GitHub repository (Rogmovies + Vegamovies).
class DatabaseSyncService {
  DatabaseSyncService._();
  static final DatabaseSyncService instance = DatabaseSyncService._();

  /// Active sync future — prevents duplicate concurrent downloads.
  /// If syncIndex() is called while one is already in progress, it returns
  /// the existing future instead of starting a new HTTP request.
  Future<bool>? _activeSyncFuture;

  // ─── Remote URLs for site-specific indices ────────────────────────────────
  static const String _remoteRogIndexUrl =
      'https://raw.githubusercontent.com/aadil12347/DanieWatch_Apk_Database/main/streaming_links_sites/Rogmovies_Index/index.json';
  static const String _remoteVegaIndexUrl =
      'https://raw.githubusercontent.com/aadil12347/DanieWatch_Apk_Database/main/streaming_links_sites/Vegamovies_Index/index.json';

  // Local cache filenames
  static const String _rogFileName = 'rog_index.json';
  static const String _vegaFileName = 'vega_index.json';
  static const String _rogTempFileName = 'rog_index_temp.json';
  static const String _vegaTempFileName = 'vega_index_temp.json';

  // ─── 3rd Party Hosted Index (DEACTIVATED) ─────────────────────────────────
  static const String _remote3rdPartyUrl =
      'https://raw.githubusercontent.com/aadil12347/DanieWatch_Apk_Database/main/3rd%20party%20hosted/3rd_party_hosted_index.json';
  static const String _3rdPartyFileName = '3rd_party_hosted_index.json';
  static const String _3rdPartyTempFileName = '3rd_party_hosted_temp.json';
  Future<bool>? _active3rdPartySyncFuture;

  /// Returns the file path for a named file in the app documents directory.
  Future<File> _localFile(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  /// Check if both local database files already exist in cache.
  Future<bool> hasLocalIndex() async {
    final rogFile = await _localFile(_rogFileName);
    final vegaFile = await _localFile(_vegaFileName);
    return await rogFile.exists() || await vegaFile.exists();
  }

  /// Sync the index database from GitHub.
  /// Downloads both Rogmovies and Vegamovies indices in parallel.
  /// Returns true if sync succeeded (at least one index downloaded).
  /// Deduplicates: if a sync is already in progress, returns the same Future.
  Future<bool> syncIndex() {
    if (_activeSyncFuture != null) {
      dev.log('[DatabaseSync] Sync already in progress — joining existing future.');
      return _activeSyncFuture!;
    }
    _activeSyncFuture = _doSync().whenComplete(() => _activeSyncFuture = null);
    return _activeSyncFuture!;
  }

  Future<bool> _doSync() async {
    try {
      dev.log('[DatabaseSync] Starting dual-index sync (Rogmovies + Vegamovies)');

      // Download both indices in parallel
      final results = await Future.wait([
        _syncSingleIndex(
          remoteUrl: _remoteRogIndexUrl,
          localFileName: _rogFileName,
          tempFileName: _rogTempFileName,
          etagKey: 'rog_index_etag',
          lastModifiedKey: 'rog_index_last_modified',
          label: 'Rogmovies',
        ),
        _syncSingleIndex(
          remoteUrl: _remoteVegaIndexUrl,
          localFileName: _vegaFileName,
          tempFileName: _vegaTempFileName,
          etagKey: 'vega_index_etag',
          lastModifiedKey: 'vega_index_last_modified',
          label: 'Vegamovies',
        ),
      ]);

      final rogSuccess = results[0];
      final vegaSuccess = results[1];

      dev.log('[DatabaseSync] Sync results — Rog: $rogSuccess, Vega: $vegaSuccess');

      // Trigger top picks sync
      // ignore: unawaited_futures
      syncTopPicks();

      return rogSuccess || vegaSuccess;
    } catch (e, stack) {
      dev.log('[DatabaseSync] Sync failed with error: $e', stackTrace: stack);

      // ignore: unawaited_futures
      syncTopPicks();

      return false;
    }
  }

  /// Download, validate, and cache a single index file.
  Future<bool> _syncSingleIndex({
    required String remoteUrl,
    required String localFileName,
    required String tempFileName,
    required String etagKey,
    required String lastModifiedKey,
    required String label,
  }) async {
    try {
      dev.log('[DatabaseSync] Syncing $label from $remoteUrl');

      final localFile = await _localFile(localFileName);
      final fileExists = await localFile.exists();
      final prefs = await SharedPreferences.getInstance();

      final headers = <String, String>{};
      if (fileExists) {
        final savedEtag = prefs.getString(etagKey);
        final savedLastModified = prefs.getString(lastModifiedKey);
        if (savedEtag != null) {
          headers['If-None-Match'] = savedEtag;
        }
        if (savedLastModified != null) {
          headers['If-Modified-Since'] = savedLastModified;
        }
      }

      final response = await http.get(Uri.parse(remoteUrl), headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 304) {
        dev.log('[DatabaseSync] $label: 304 Not Modified. Using cached local index.');
        return true;
      }

      if (response.statusCode != 200) {
        dev.log('[DatabaseSync] $label HTTP Error: ${response.statusCode}');
        return false;
      }

      final rawData = response.body;
      if (rawData.isEmpty) {
        dev.log('[DatabaseSync] $label: Downloaded data is empty.');
        return false;
      }

      // 1. Write to temporary file first
      final tempFile = await _localFile(tempFileName);
      await tempFile.writeAsString(rawData, flush: true);
      dev.log('[DatabaseSync] $label: Temp file written. Validating...');

      // 2. Validate the downloaded data in a background isolate
      final isValid = await compute(_validateIndexIsolate, rawData);
      if (!isValid) {
        dev.log('[DatabaseSync] $label: Validation failed. Deleting temp file.');
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        return false;
      }

      // 3. Validation passed! Overwrite the active index file
      await tempFile.copy(localFile.path);

      // Clean up temp file
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      // 4. Save ETag / Last-Modified headers for conditional requests
      final etag = response.headers['etag'];
      final lastModified = response.headers['last-modified'];
      if (etag != null) {
        await prefs.setString(etagKey, etag);
      } else {
        await prefs.remove(etagKey);
      }
      if (lastModified != null) {
        await prefs.setString(lastModifiedKey, lastModified);
      } else {
        await prefs.remove(lastModifiedKey);
      }

      dev.log('[DatabaseSync] $label: Database successfully synchronized & cached.');
      return true;
    } catch (e, stack) {
      dev.log('[DatabaseSync] $label sync failed: $e', stackTrace: stack);
      // Clean up temp file if needed
      try {
        final tempFile = await _localFile(tempFileName);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      return false;
    }
  }

  /// Load and parse both site indices from local files, merge and deduplicate.
  /// Returns the combined list of ManifestItems.
  /// On first launch (no cached files), falls back to bundled asset seed files.
  Future<List<ManifestItem>> loadLocalIndex() async {
    try {
      final rogFile = await _localFile(_rogFileName);
      final vegaFile = await _localFile(_vegaFileName);

      final rogExists = await rogFile.exists();
      final vegaExists = await vegaFile.exists();

      String? rogData;
      String? vegaData;

      // Load Rogmovies index
      if (rogExists) {
        rogData = await rogFile.readAsString();
      } else {
        dev.log('[DatabaseSync] Rog local index not found — loading bundled seed.');
        try {
          rogData = await rootBundle.loadString('assets/rog_index.json');
        } catch (e) {
          dev.log('[DatabaseSync] Failed to load rog seed: $e');
        }
      }

      // Load Vegamovies index
      if (vegaExists) {
        vegaData = await vegaFile.readAsString();
      } else {
        dev.log('[DatabaseSync] Vega local index not found — loading bundled seed.');
        try {
          vegaData = await rootBundle.loadString('assets/vega_index.json');
        } catch (e) {
          dev.log('[DatabaseSync] Failed to load vega seed: $e');
        }
      }

      if (rogData == null && vegaData == null) {
        dev.log('[DatabaseSync] No index data available at all.');
        return [];
      }

      // Parse and merge in a background isolate
      final items = await compute(_parseMergeIndicesIsolate, _DualIndexPayload(
        rogJson: rogData,
        vegaJson: vegaData,
      ));

      dev.log('[DatabaseSync] Loaded ${items.length} items (merged & deduplicated).');
      return items;
    } catch (e, stack) {
      dev.log('[DatabaseSync] Failed to load local database: $e', stackTrace: stack);
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3rd Party Hosted Index — Download, Cache, Load (DEACTIVATED)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<File> get _3rdPartyFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_3rdPartyFileName');
  }

  Future<File> get _3rdPartyTempFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_3rdPartyTempFileName');
  }

  Future<bool> hasLocal3rdPartyIndex() async {
    final file = await _3rdPartyFile;
    return await file.exists();
  }

  /// Sync the 3rd party hosted index from GitHub.
  /// DEACTIVATED — 3rd party index is no longer used. Kept for future reactivation.
  Future<bool> sync3rdPartyIndex() {
    dev.log('[DatabaseSync] 3rd party sync DEACTIVATED — skipping.');
    return Future.value(true);
  }

  Future<bool> _do3rdPartySync() async {
    try {
      dev.log('[DatabaseSync] Starting 3rd party sync from $_remote3rdPartyUrl');

      final fileExists = await hasLocal3rdPartyIndex();
      final prefs = await SharedPreferences.getInstance();

      final headers = <String, String>{};
      if (fileExists) {
        final savedEtag = prefs.getString('3rdparty_etag');
        final savedLastModified = prefs.getString('3rdparty_last_modified');
        if (savedEtag != null) headers['If-None-Match'] = savedEtag;
        if (savedLastModified != null) headers['If-Modified-Since'] = savedLastModified;
      }

      final response = await http.get(Uri.parse(_remote3rdPartyUrl), headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 304) {
        dev.log('[DatabaseSync] 3rd party: 304 Not Modified.');
        return true;
      }

      if (response.statusCode != 200) {
        dev.log('[DatabaseSync] 3rd party HTTP Error: ${response.statusCode}');
        return false;
      }

      final rawData = response.body;
      if (rawData.isEmpty) {
        dev.log('[DatabaseSync] 3rd party: Downloaded data is empty.');
        return false;
      }

      // 1. Write to temp file
      final tempFile = await _3rdPartyTempFile;
      await tempFile.writeAsString(rawData, flush: true);

      // 2. Validate
      final isValid = await compute(_validateIndexIsolate, rawData);
      if (!isValid) {
        dev.log('[DatabaseSync] 3rd party validation failed.');
        if (await tempFile.exists()) await tempFile.delete();
        return false;
      }

      // 3. Atomic swap
      final primaryFile = await _3rdPartyFile;
      await tempFile.copy(primaryFile.path);
      if (await tempFile.exists()) await tempFile.delete();

      // 4. Save ETag / Last-Modified
      final etag = response.headers['etag'];
      final lastModified = response.headers['last-modified'];
      if (etag != null) {
        await prefs.setString('3rdparty_etag', etag);
      } else {
        await prefs.remove('3rdparty_etag');
      }
      if (lastModified != null) {
        await prefs.setString('3rdparty_last_modified', lastModified);
      } else {
        await prefs.remove('3rdparty_last_modified');
      }

      dev.log('[DatabaseSync] 3rd party index synced successfully.');
      return true;
    } catch (e, stack) {
      dev.log('[DatabaseSync] 3rd party sync failed: $e', stackTrace: stack);
      try {
        final tempFile = await _3rdPartyTempFile;
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      return false;
    }
  }

  /// Load and parse the 3rd party index from local cache.
  /// DEACTIVATED — 3rd party index is no longer used. Kept for future reactivation.
  Future<List<ManifestItem>> load3rdPartyIndex() async {
    dev.log('[DatabaseSync] 3rd party load DEACTIVATED — returning empty list.');
    return [];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Top 5 / Top 10 Curated Picks — Fetch from GitHub, Cache Locally
  // ═══════════════════════════════════════════════════════════════════════════

  static const String _githubApiBase =
      'https://api.github.com/repos/aadil12347/DanieWatch_Apk_Database/contents';
  static const String _top5CacheFile = 'top_picks_5.json';
  static const String _top10CacheFile = 'top_picks_10.json';

  Future<File> _topPicksFile(String folder) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = folder == 'Top 5' ? _top5CacheFile : _top10CacheFile;
    return File('${dir.path}/$fileName');
  }

  /// Sync both Top 5 and Top 10 curated picks from GitHub.
  /// Returns true if at least one succeeded.
  Future<bool> syncTopPicks() async {
    final results = await Future.wait([
      _syncTopPicksFolder('Top 5'),
      _syncTopPicksFolder('Top 10'),
    ]);
    return results[0] || results[1];
  }

  /// Fetch a Top N folder from GitHub API, download each numbered JSON file,
  /// extract tmdb_id, and cache as {position: tmdb_id} map.
  Future<bool> _syncTopPicksFolder(String folder) async {
    try {
      dev.log('[DatabaseSync] Syncing $folder curated picks...');

      // 1. Get directory listing from GitHub API
      final encodedFolder = Uri.encodeComponent(folder);
      final dirUrl = '$_githubApiBase/$encodedFolder';
      final dirResponse = await http.get(
        Uri.parse(dirUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 15));

      if (dirResponse.statusCode != 200) {
        dev.log('[DatabaseSync] $folder directory listing failed: ${dirResponse.statusCode}');
        return false;
      }

      final List<dynamic> files = jsonDecode(dirResponse.body);
      if (files.isEmpty) {
        dev.log('[DatabaseSync] $folder folder is empty.');
        // Cache empty map
        final cacheFile = await _topPicksFile(folder);
        await cacheFile.writeAsString('{}', flush: true);
        return true;
      }

      // 2. For each JSON file, extract position number and download content
      final Map<String, int> positionMap = {}; // position string → tmdb_id

      final downloadFutures = <Future<void>>[];
      for (final fileEntry in files) {
        final String name = fileEntry['name']?.toString() ?? '';
        final String? downloadUrl = fileEntry['download_url']?.toString();

        if (!name.endsWith('.json') || downloadUrl == null) continue;

        // Extract position number from filename (e.g., "1.json" → 1)
        final posStr = name.replaceAll('.json', '');
        final pos = int.tryParse(posStr);
        if (pos == null) continue;

        downloadFutures.add(_fetchTopPickFile(downloadUrl, pos, positionMap));
      }

      await Future.wait(downloadFutures);

      // 3. Cache the position → tmdb_id map
      final cacheFile = await _topPicksFile(folder);
      await cacheFile.writeAsString(jsonEncode(positionMap), flush: true);

      dev.log('[DatabaseSync] $folder synced: ${positionMap.length} curated picks cached.');
      return true;
    } catch (e, stack) {
      dev.log('[DatabaseSync] $folder sync failed: $e', stackTrace: stack);
      return false;
    }
  }

  /// Download a single top pick JSON file and extract its tmdb_id.
  Future<void> _fetchTopPickFile(
      String downloadUrl, int position, Map<String, int> positionMap) async {
    try {
      final response = await http.get(Uri.parse(downloadUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tmdbId = data['tmdb_id'];
        if (tmdbId is int && tmdbId > 0) {
          positionMap[position.toString()] = tmdbId;
        }
      }
    } catch (e) {
      dev.log('[DatabaseSync] Failed to fetch top pick at position $position: $e');
    }
  }

  /// Load cached Top N picks. Returns {position: tmdb_id} map.
  /// Position is 1-indexed (1 = first slot).
  Future<Map<int, int>> loadTopPicks(String folder) async {
    try {
      final file = await _topPicksFile(folder);
      if (!await file.exists()) {
        return {};
      }
      final raw = await file.readAsString();
      final Map<String, dynamic> parsed = jsonDecode(raw);
      // Convert string keys back to int
      return parsed.map((key, value) => MapEntry(int.parse(key), value as int));
    } catch (e) {
      dev.log('[DatabaseSync] Failed to load $folder picks: $e');
      return {};
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Isolate helpers — run in background threads to avoid blocking UI
// ═══════════════════════════════════════════════════════════════════════════════

/// Payload for sending both index JSONs to the merge isolate.
class _DualIndexPayload {
  final String? rogJson;
  final String? vegaJson;
  _DualIndexPayload({this.rogJson, this.vegaJson});
}

/// Helper function running in a separate Isolate to validate the index JSON.
bool _validateIndexIsolate(String rawJson) {
  try {
    final parsed = jsonDecode(rawJson);
    if (parsed is! List) return false;
    if (parsed.isEmpty) return true; // Empty database is valid
    
    // Check if the first element is a list (positional array format)
    final first = parsed.first;
    if (first is! List) return false;
    
    // Must contain at least ID (0) and Title (1)
    if (first.length < 2) return false;
    
    return true;
  } catch (_) {
    return false;
  }
}

/// Helper function running in a separate Isolate to parse positional arrays to ManifestItems.
List<ManifestItem> _parseIndexIsolate(String rawJson) {
  try {
    final List<dynamic> parsedList = jsonDecode(rawJson);
    return parsedList.map((e) {
      if (e is List) {
        return ManifestItem.fromArray(e);
      }
      // Fallback for dict format just in case
      if (e is Map<String, dynamic>) {
        return ManifestItem.fromJson(e);
      }
      throw FormatException('Unknown item format in database: $e');
    }).toList();
  } catch (e) {
    dev.log('[DatabaseSync Isolate] Parsing error: $e');
    return [];
  }
}

/// Parse, merge, and deduplicate both Rog and Vega indices in a background isolate.
/// Deduplication key = tmdbId + mediaType + seasonDetail.
/// Same show with different seasons → kept as separate entries.
/// Same show + same season across both indices → merged (union languages/genres).
List<ManifestItem> _parseMergeIndicesIsolate(_DualIndexPayload payload) {
  try {
    final List<ManifestItem> rogItems = payload.rogJson != null
        ? _parseIndexIsolate(payload.rogJson!)
        : [];
    final List<ManifestItem> vegaItems = payload.vegaJson != null
        ? _parseIndexIsolate(payload.vegaJson!)
        : [];

    dev.log('[DatabaseSync Isolate] Parsed Rog: ${rogItems.length}, Vega: ${vegaItems.length}');

    // Merge with deduplication by tmdbId + mediaType + seasonDetail
    final Map<String, ManifestItem> merged = {};

    for (final item in rogItems) {
      final key = item.deduplicationKey;
      merged[key] = item;
    }

    for (final item in vegaItems) {
      final key = item.deduplicationKey;
      if (merged.containsKey(key)) {
        // Duplicate — merge languages and genres
        final existing = merged[key]!;
        final mergedLanguages = {...existing.language, ...item.language}.toList();
        final mergedGenres = {...existing.genres, ...item.genres}.toList();
        merged[key] = existing.copyWith(
          language: mergedLanguages,
          genres: mergedGenres,
        );
      } else {
        merged[key] = item;
      }
    }

    final result = merged.values.toList();
    dev.log('[DatabaseSync Isolate] Merged result: ${result.length} items '
        '(${rogItems.length + vegaItems.length - result.length} duplicates removed)');

    return result;
  } catch (e) {
    dev.log('[DatabaseSync Isolate] Merge error: $e');
    return [];
  }
}

/// Helper function to parse dict-format seed index (from bundled assets).
/// The seed uses {title, tmdb_id, imdb_id, languages, type, aired_date} format.
List<ManifestItem> _parseDictIndexIsolate(String rawJson) {
  try {
    final List<dynamic> parsedList = jsonDecode(rawJson);
    return parsedList.where((e) => e is Map<String, dynamic>).map((e) {
      return ManifestItem.fromJson(e as Map<String, dynamic>);
    }).toList();
  } catch (e) {
    dev.log('[DatabaseSync Isolate] Seed parsing error: $e');
    return [];
  }
}
