import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/posting_record.dart';

/// Repository for fetching, caching, and providing posting_record.json data.
/// Used to determine display priority of posts across all Explore tabs.
class PostingRecordRepository {
  PostingRecordRepository._();
  static final PostingRecordRepository instance = PostingRecordRepository._();

  static const _remoteUrl =
      'https://raw.githubusercontent.com/aadil12347/DanieWatch_Apk_Database/main/posting_record.json';
  static const _cacheFileName = 'posting_record_cache.json';

  PostingRecord? _cached;

  /// Fetch posting_record.json from GitHub, falling back to local cache.
  /// Returns null only if both network and cache fail.
  Future<PostingRecord?> fetch() async {
    try {
      final response = await http.get(Uri.parse(_remoteUrl));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        _cached = PostingRecord.fromJson(json);
        // Cache to disk for offline use
        await _saveToDisk(response.body);
        dev.log(
            '[PostingRecordRepo] Fetched ${_cached!.totalPosts} posts, ${_cached!.batches.length} batches');
        return _cached;
      }
      dev.log(
          '[PostingRecordRepo] HTTP ${response.statusCode}, falling back to cache');
    } catch (e) {
      dev.log('[PostingRecordRepo] Network error: $e, falling back to cache');
    }

    // Fallback to cached version
    return _readFromDisk();
  }

  /// Returns the cached PostingRecord if available (from memory or disk).
  Future<PostingRecord?> getCached() async {
    if (_cached != null) return _cached;
    return _readFromDisk();
  }

  /// Build a priority map from the current posting record.
  /// key = "tmdbId-type", value = priority (lower = higher priority).
  Future<Map<String, int>> buildPriorityMap() async {
    final record = _cached ?? await getCached();
    if (record == null) return {};
    return record.buildPriorityMap();
  }

  // ─── Local Cache ──────────────────────────────────────────

  Future<File> get _cacheFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_cacheFileName');
  }

  Future<void> _saveToDisk(String rawJson) async {
    try {
      final file = await _cacheFile;
      await file.writeAsString(rawJson);
    } catch (e) {
      dev.log('[PostingRecordRepo] Failed to cache: $e');
    }
  }

  Future<PostingRecord?> _readFromDisk() async {
    try {
      final file = await _cacheFile;
      if (await file.exists()) {
        final raw = await file.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _cached = PostingRecord.fromJson(json);
        dev.log('[PostingRecordRepo] Loaded from cache: ${_cached!.totalPosts} posts');
        return _cached;
      }
    } catch (e) {
      dev.log('[PostingRecordRepo] Failed to read cache: $e');
    }
    return null;
  }
}
