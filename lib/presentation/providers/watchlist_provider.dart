import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/local/database.dart';
import '../../data/local/watchlist_backup_manager.dart';
import '../../domain/models/entry.dart';
import 'auth_provider.dart';

/// Watchlist provider — SQLite local sandbox with zero-load Supabase user_metadata cloud sync.
///
/// Ensures the user's watchlist is:
/// 1. Instant and responsive locally (SQLite sandbox)
/// 2. Permanently synced to the user's cloud account (via Supabase auth user_metadata, 0 DB tables)
/// 3. Automatically recovered upon login after "Clear Data", app uninstall/reinstall, or switching phones.
class WatchlistNotifier extends AsyncNotifier<List<WatchlistItem>> {
  Timer? _cloudDebounceTimer;

  @override
  Future<List<WatchlistItem>> build() async {
    // Ensure SQLite database is fully initialized before loading
    await AppDatabase.instance.ensureInitialized();

    // Listen to auth state so when the user logs in, the watchlist auto-recovers from cloud!
    ref.listen(authStateProvider, (prev, next) {
      final user = next.valueOrNull;
      if (user != null) {
        // User logged in: trigger refresh to recover cloud watchlist
        Future.microtask(() => ref.invalidateSelf());
      }
    });

    return _loadWatchlist();
  }

  Future<List<WatchlistItem>> _queryWatchlist(Database db) async {
    final rows = await db.query('watchlist', orderBy: 'added_at DESC');
    return rows
        .map((r) => WatchlistItem(
              tmdbId: r['tmdb_id'] as int,
              mediaType: r['media_type'] as String,
              title: r['title'] as String,
              posterPath: r['poster_path'] as String?,
              releaseDate: r['release_date'] as String?,
              voteAverage: (r['vote_average'] as num?)?.toDouble() ?? 0.0,
              addedAt:
                  DateTime.fromMillisecondsSinceEpoch(r['added_at'] as int),
            ))
        .toList();
  }

  Future<List<WatchlistItem>> _loadWatchlist() async {
    final db = await AppDatabase.instance.database;
    List<WatchlistItem> items = await _queryWatchlist(db);

    // Check if user is logged in to sync with cloud user_metadata
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      items = await _syncWithCloud(db, user, items);
    } else if (items.isEmpty) {
      // Guest fallback: restore from device backup
      final restored = await WatchlistBackupManager.instance.restoreToDatabase(db);
      if (restored.isNotEmpty) {
        items = restored;
      }
    } else {
      // In the background, keep permanent device backup fresh
      unawaited(WatchlistBackupManager.instance.saveBackup(items));
    }

    return items;
  }

  /// Two-way sync with Supabase Auth user_metadata (Zero DB tables, Zero server load)
  Future<List<WatchlistItem>> _syncWithCloud(
      Database db, User user, List<WatchlistItem> localItems) async {
    try {
      final dynamic cloudRaw = user.userMetadata?['watchlist'];
      final List<WatchlistItem> cloudItems = [];

      if (cloudRaw is List) {
        for (final entry in cloudRaw) {
          if (entry is Map) {
            cloudItems.add(
              WatchlistItem.fromJson(Map<String, dynamic>.from(entry)),
            );
          }
        }
      }

      // Merge cloud items and local items (keyed by tmdbId + mediaType)
      final Map<String, WatchlistItem> mergedMap = {};

      // 1. Add cloud items
      for (final item in cloudItems) {
        mergedMap['${item.tmdbId}_${item.mediaType}'] = item;
      }

      // 2. Add local items (local takes priority if present)
      bool hasNewLocalItems = false;
      for (final item in localItems) {
        final key = '${item.tmdbId}_${item.mediaType}';
        if (!mergedMap.containsKey(key)) {
          hasNewLocalItems = true;
        }
        mergedMap[key] = item;
      }

      final mergedList = mergedMap.values.toList()
        ..sort((a, b) =>
            (b.addedAt ?? DateTime(2000)).compareTo(a.addedAt ?? DateTime(2000)));

      // If cloud had items that were missing in local SQLite (e.g. after Clear Data or reinstall),
      // populate local SQLite sandbox immediately
      if (cloudItems.isNotEmpty || hasNewLocalItems) {
        await db.transaction((txn) async {
          for (final item in mergedList) {
            await txn.insert(
              'watchlist',
              {
                'tmdb_id': item.tmdbId,
                'media_type': item.mediaType,
                'title': item.title,
                'poster_path': item.posterPath,
                'release_date': item.releaseDate,
                'vote_average': item.voteAverage,
                'added_at':
                    (item.addedAt ?? DateTime.now()).millisecondsSinceEpoch,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        });
      }

      // If local had items not yet in cloud, sync up to user_metadata
      if (hasNewLocalItems || (cloudItems.length != mergedList.length)) {
        _uploadToUserMetadata(mergedList);
      }

      unawaited(WatchlistBackupManager.instance.saveBackup(mergedList));
      debugPrint('[Watchlist] ✅ Cloud sync complete: ${mergedList.length} items (Cloud had ${cloudItems.length}, Local had ${localItems.length})');
      return mergedList;
    } catch (e) {
      debugPrint('[Watchlist] ⚠️ Cloud sync warning: $e');
      return localItems;
    }
  }

  /// Debounced background upload to Supabase user_metadata (Zero DB tables, Zero Postgres rows)
  void _uploadToUserMetadata(List<WatchlistItem> items) {
    _cloudDebounceTimer?.cancel();
    _cloudDebounceTimer = Timer(const Duration(milliseconds: 1000), () async {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      try {
        final compactList = items.map((i) => i.toCompactJson()).toList();
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(data: {'watchlist': compactList}),
        );
        debugPrint(
            '[Watchlist] ☁️ Backed up ${items.length} titles to Supabase user_metadata (0 DB load)');
      } catch (e) {
        debugPrint('[Watchlist] ⚠️ Failed to update user_metadata: $e');
      }
    });
  }

  Future<void> toggle({
    required int tmdbId,
    required String mediaType,
    required String title,
    String? posterPath,
    String? releaseDate,
    double voteAverage = 0.0,
  }) async {
    final db = await AppDatabase.instance.database;
    final existing = await db.query(
      'watchlist',
      where: 'tmdb_id = ? AND media_type = ?',
      whereArgs: [tmdbId, mediaType],
    );

    if (existing.isNotEmpty) {
      await db.delete('watchlist',
          where: 'tmdb_id = ? AND media_type = ?',
          whereArgs: [tmdbId, mediaType]);
    } else {
      await db.insert('watchlist', {
        'tmdb_id': tmdbId,
        'media_type': mediaType,
        'title': title,
        'poster_path': posterPath,
        'release_date': releaseDate,
        'vote_average': voteAverage,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      });
    }

    final updatedItems = await _queryWatchlist(db);
    state = AsyncValue.data(updatedItems);

    // 1. Keep local device backup updated
    unawaited(WatchlistBackupManager.instance.saveBackup(updatedItems));

    // 2. Keep Supabase user_metadata cloud backup updated
    _uploadToUserMetadata(updatedItems);
  }

  bool isInWatchlist(int tmdbId, String mediaType) {
    final items = state.valueOrNull ?? [];
    return items.any((i) => i.tmdbId == tmdbId && i.mediaType == mediaType);
  }

  /// Manually trigger a restore from permanent device backup
  Future<void> restoreFromBackup() async {
    final db = await AppDatabase.instance.database;
    final restored = await WatchlistBackupManager.instance.restoreToDatabase(db);
    if (restored.isNotEmpty) {
      final updated = await _queryWatchlist(db);
      state = AsyncValue.data(updated);
      _uploadToUserMetadata(updated);
    }
  }
}

final watchlistProvider =
    AsyncNotifierProvider<WatchlistNotifier, List<WatchlistItem>>(
        () => WatchlistNotifier());

/// Continue watching provider
class ContinueWatchingNotifier
    extends AsyncNotifier<List<ContinueWatchingItem>> {
  @override
  Future<List<ContinueWatchingItem>> build() async {
    await AppDatabase.instance.ensureInitialized();
    return _load();
  }

  Future<List<ContinueWatchingItem>> _load() async {
    final db = await AppDatabase.instance.database;
    final rows =
        await db.query('continue_watching', orderBy: 'updated_at DESC');
    return rows
        .map((r) => ContinueWatchingItem(
              tmdbId: r['tmdb_id'] as int,
              mediaType: r['media_type'] as String,
              title: r['title'] as String,
              posterPath: r['poster_path'] as String?,
              season: r['season'] as int?,
              episode: r['episode'] as int?,
              progressSeconds: r['progress_seconds'] as int? ?? 0,
              totalSeconds: r['total_seconds'] as int? ?? 0,
              updatedAt:
                  DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
            ))
        .toList();
  }

  Future<void> updateProgress({
    required int tmdbId,
    required String mediaType,
    required String title,
    String? posterPath,
    int? season,
    int? episode,
    required int progressSeconds,
    required int totalSeconds,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      'continue_watching',
      {
        'tmdb_id': tmdbId,
        'media_type': mediaType,
        'title': title,
        'poster_path': posterPath,
        'season': season,
        'episode': episode,
        'progress_seconds': progressSeconds,
        'total_seconds': totalSeconds,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    state = AsyncValue.data(await _load());
  }

  Future<void> remove(int tmdbId, String mediaType) async {
    final db = await AppDatabase.instance.database;
    await db.delete('continue_watching',
        where: 'tmdb_id = ? AND media_type = ?',
        whereArgs: [tmdbId, mediaType]);
    state = AsyncValue.data(await _load());
  }
}

final continueWatchingProvider =
    AsyncNotifierProvider<ContinueWatchingNotifier, List<ContinueWatchingItem>>(
        () => ContinueWatchingNotifier());
