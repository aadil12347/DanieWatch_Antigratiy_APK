import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../local/search_database.dart';

/// Handles loading the base index from assets and syncing delta updates.
class SyncService {
  static SyncService? _instance;
  static SyncService get instance => _instance ??= SyncService._();
  SyncService._();

  static const _lastSyncKey = 'search_last_sync_timestamp';
  static const _dbInitializedKey = 'search_db_initialized_v2';

  // TODO: Update this to your actual GitHub raw content URL
  static const _baseUrl =
      'https://raw.githubusercontent.com/aadil12347/DanieWatch_Antigratiy_APK/main/catalog/updates';

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// Initialize the search database.
  /// On first run: loads base_index.json from assets.
  /// On subsequent runs: downloads only new delta updates.
  Future<void> initialize() async {
    final db = SearchDatabase.instance;
    final prefs = await SharedPreferences.getInstance();
    final isDbInitialized = prefs.getBool(_dbInitializedKey) ?? false;

    if (!isDbInitialized) {
      // First launch: load bundled base index
      await _loadBaseIndex(db);
      await prefs.setBool(_dbInitializedKey, true);
      print('[SyncService] Base index loaded from assets');
    }

    db.markReady();

    // Then sync deltas in background
    _syncDeltas(db, prefs);
  }

  /// Load the bundled base_index.json from assets into SQLite
  Future<void> _loadBaseIndex(SearchDatabase db) async {
    try {
      final jsonStr = await rootBundle.loadString('assets/base_index.json');
      final data = jsonDecode(jsonStr);

      final List<dynamic> posts = data['posts'] ?? [];
      if (posts.isEmpty) {
        print('[SyncService] WARNING: base_index.json has no posts');
        return;
      }

      // Add addedAt for items that don't have it
      final now = DateTime.now().toUtc().toIso8601String();
      final items = posts.map((p) {
        final map = Map<String, dynamic>.from(p);
        map['addedAt'] ??= now;
        return map;
      }).toList();

      final count = await db.insertItems(items);
      print('[SyncService] Inserted $count items from base index');
    } catch (e) {
      print('[SyncService] Error loading base index: $e');
    }
  }

  /// Download and apply delta updates from the server
  Future<void> _syncDeltas(SearchDatabase db, SharedPreferences prefs) async {
    try {
      // Fetch the update manifest
      final manifestUrl = '$_baseUrl/update_manifest.json';
      final response = await _dio.get(manifestUrl);

      if (response.statusCode != 200) {
        print('[SyncService] Failed to fetch manifest: ${response.statusCode}');
        return;
      }

      final manifest = response.data;
      final List<dynamic> updates = manifest['updates'] ?? [];

      if (updates.isEmpty) {
        print('[SyncService] No updates available');
        return;
      }

      // Get our last sync timestamp
      final lastSync = prefs.getInt(_lastSyncKey) ?? 0;

      // Filter to only new updates
      final newUpdates = updates.where((u) {
        final ts = u['timestamp'] as int? ?? 0;
        return ts > lastSync;
      }).toList();

      if (newUpdates.isEmpty) {
        print('[SyncService] Already up to date');
        return;
      }

      print('[SyncService] Downloading ${newUpdates.length} delta updates...');

      int latestTimestamp = lastSync;

      for (final update in newUpdates) {
        final fileName = update['file'] as String;
        final timestamp = update['timestamp'] as int? ?? 0;

        try {
          final updateUrl = '$_baseUrl/$fileName';
          final updateResp = await _dio.get(updateUrl);

          if (updateResp.statusCode == 200) {
            final updateData = updateResp.data;

            // Process removals first
            final List<dynamic> removals = updateData['removals'] ?? [];
            if (removals.isNotEmpty) {
              await db.deleteByUids(removals.map((r) => r.toString()).toList());
              print('[SyncService] Removed ${removals.length} items');
            }

            // Then insert/update items
            final List<dynamic> items = updateData['items'] ?? [];
            if (items.isNotEmpty) {
              final count = await db.insertItems(
                items.map((i) => Map<String, dynamic>.from(i)).toList(),
              );
              print('[SyncService] Applied $count items from $fileName');
            }

            if (timestamp > latestTimestamp) {
              latestTimestamp = timestamp;
            }
          }
        } catch (e) {
          print('[SyncService] Error downloading $fileName: $e');
          // Continue with next update
        }
      }

      // Save the latest timestamp
      if (latestTimestamp > lastSync) {
        await prefs.setInt(_lastSyncKey, latestTimestamp);
      }

      final totalCount = await db.getItemCount();
      print('[SyncService] Sync complete. Total items in DB: $totalCount');
    } catch (e) {
      // Non-fatal: delta sync failure just means user has slightly stale data
      print('[SyncService] Delta sync error (non-fatal): $e');
    }
  }

  /// Force a full resync (clears DB and reloads from assets + deltas)
  Future<void> forceResync() async {
    final db = SearchDatabase.instance;
    final prefs = await SharedPreferences.getInstance();
    
    await db.close();
    await prefs.remove(_dbInitializedKey);
    await prefs.remove(_lastSyncKey);
    
    await initialize();
  }
}
