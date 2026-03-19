import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/local/database.dart';
import '../../domain/models/entry.dart';

/// Watchlist provider — guest local storage in SQLite
class WatchlistNotifier extends AsyncNotifier<List<WatchlistItem>> {
  @override
  Future<List<WatchlistItem>> build() async {
    // Try to trigger a sync in the background on load
    Future.microtask(() => syncWithSupabase());
    return _loadWatchlist();
  }

  Future<List<WatchlistItem>> _loadWatchlist() async {
    final db = AppDatabase.instance.db;
    final rows = await db.query('watchlist', orderBy: 'added_at DESC');
    return rows.map((r) => WatchlistItem(
      tmdbId: r['tmdb_id'] as int,
      mediaType: r['media_type'] as String,
      title: r['title'] as String,
      posterPath: r['poster_path'] as String?,
      voteAverage: (r['vote_average'] as num?)?.toDouble() ?? 0.0,
      addedAt: DateTime.fromMillisecondsSinceEpoch(r['added_at'] as int),
    )).toList();
  }

  Future<void> toggle({
    required int tmdbId,
    required String mediaType,
    required String title,
    String? posterPath,
    double voteAverage = 0.0,
  }) async {
    final db = AppDatabase.instance.db;
    final existing = await db.query(
      'watchlist',
      where: 'tmdb_id = ? AND media_type = ?',
      whereArgs: [tmdbId, mediaType],
    );

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (existing.isNotEmpty) {
      await db.delete('watchlist',
          where: 'tmdb_id = ? AND media_type = ?',
          whereArgs: [tmdbId, mediaType]);
          
      if (user != null) {
        try {
          await client.from('watchlist').delete()
              .eq('user_id', user.id)
              .eq('tmdb_id', tmdbId)
              .eq('media_type', mediaType);
        } catch (e) {
          print('Supabase delete error: $e');
        }
      }
    } else {
      await db.insert('watchlist', {
        'tmdb_id': tmdbId,
        'media_type': mediaType,
        'title': title,
        'poster_path': posterPath,
        'vote_average': voteAverage,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      });
      
      if (user != null) {
        try {
          await client.from('watchlist').upsert({
            'user_id': user.id,
            'tmdb_id': tmdbId,
            'media_type': mediaType,
            'title': title,
            'poster_path': posterPath,
            'vote_average': voteAverage,
          });
        } catch (e) {
          print('Supabase upsert error: $e');
        }
      }
    }

    state = AsyncValue.data(await _loadWatchlist());
  }

  Future<void> syncWithSupabase() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    final db = AppDatabase.instance.db;
    final localItems = await db.query('watchlist');

    try {
      final remoteItems = await client.from('watchlist').select().eq('user_id', user.id);
      
      if (localItems.isEmpty && remoteItems.isNotEmpty) {
        // Pull down from Supabase
        for (final r in remoteItems) {
          final createdAtStr = r['created_at']?.toString();
          final addedAt = createdAtStr != null 
              ? DateTime.tryParse(createdAtStr)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch
              : DateTime.now().millisecondsSinceEpoch;
              
          await db.insert(
            'watchlist', 
            {
              'tmdb_id': r['tmdb_id'],
              'media_type': r['media_type'],
              'title': r['title'],
              'poster_path': r['poster_path'],
              'vote_average': r['vote_average'],
              'added_at': addedAt,
            }, 
            conflictAlgorithm: ConflictAlgorithm.replace
          );
        }
        state = AsyncValue.data(await _loadWatchlist());
      } else if (localItems.isNotEmpty) {
        // Push local up to Supabase
        for (final l in localItems) {
          await client.from('watchlist').upsert({
            'user_id': user.id,
            'tmdb_id': l['tmdb_id'],
            'media_type': l['media_type'],
            'title': l['title'],
            'poster_path': l['poster_path'],
            'vote_average': l['vote_average'],
          }, onConflict: 'user_id, tmdb_id, media_type');
        }
        // Could do a two-way merge here, but simple upload for local items is a good start.
      }
    } catch (e) {
      print('Watchlist sync error: $e');
    }
  }

  bool isInWatchlist(int tmdbId, String mediaType) {
    final items = state.valueOrNull ?? [];
    return items.any((i) => i.tmdbId == tmdbId && i.mediaType == mediaType);
  }
}

final watchlistProvider =
    AsyncNotifierProvider<WatchlistNotifier, List<WatchlistItem>>(
        () => WatchlistNotifier());

/// Continue watching provider
class ContinueWatchingNotifier extends AsyncNotifier<List<ContinueWatchingItem>> {
  @override
  Future<List<ContinueWatchingItem>> build() async {
    return _load();
  }

  Future<List<ContinueWatchingItem>> _load() async {
    final db = AppDatabase.instance.db;
    final rows = await db.query('continue_watching', orderBy: 'updated_at DESC');
    return rows.map((r) => ContinueWatchingItem(
      tmdbId: r['tmdb_id'] as int,
      mediaType: r['media_type'] as String,
      title: r['title'] as String,
      posterPath: r['poster_path'] as String?,
      season: r['season'] as int?,
      episode: r['episode'] as int?,
      progressSeconds: r['progress_seconds'] as int? ?? 0,
      totalSeconds: r['total_seconds'] as int? ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
    )).toList();
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
    final db = AppDatabase.instance.db;
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
    final db = AppDatabase.instance.db;
    await db.delete('continue_watching',
        where: 'tmdb_id = ? AND media_type = ?',
        whereArgs: [tmdbId, mediaType]);
    state = AsyncValue.data(await _load());
  }
}

final continueWatchingProvider =
    AsyncNotifierProvider<ContinueWatchingNotifier, List<ContinueWatchingItem>>(
        () => ContinueWatchingNotifier());
