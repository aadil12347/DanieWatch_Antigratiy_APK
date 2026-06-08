import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite database manager — single instance, handles schema + migrations.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'daniewatch.db';
  static const _schemaVersion = 3;

  Database? _db;

  Database get db {
    if (_db == null) {
      throw StateError('Database not initialized. Call initialize() first.');
    }
    return _db!;
  }

  Future<void> initialize() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    _db = await openDatabase(
      path,
      version: _schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        // Enable WAL mode for better concurrent read performance
        // PRAGMA statements that return results must use rawQuery on Android
        await db.rawQuery('PRAGMA journal_mode=WAL');
        await db.execute('PRAGMA synchronous=NORMAL');
        await db.execute('PRAGMA cache_size=-8000'); // 8MB cache
        await db.execute('PRAGMA temp_store=MEMORY');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE watchlist (
        tmdb_id INTEGER NOT NULL,
        media_type TEXT NOT NULL,
        title TEXT NOT NULL,
        poster_path TEXT,
        vote_average REAL DEFAULT 0,
        added_at INTEGER NOT NULL,
        PRIMARY KEY (tmdb_id, media_type)
      )
    ''');

    // Continue watching (local guest storage)
    await db.execute('''
      CREATE TABLE continue_watching (
        tmdb_id INTEGER NOT NULL,
        media_type TEXT NOT NULL,
        title TEXT NOT NULL,
        poster_path TEXT,
        season INTEGER,
        episode INTEGER,
        progress_seconds INTEGER DEFAULT 0,
        total_seconds INTEGER DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (tmdb_id, media_type)
      )
    ''');

    // TMDB raw response cache
    await db.execute('''
      CREATE TABLE tmdb_cache (
        cache_key TEXT PRIMARY KEY,
        response_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS tmdb_cache (
          cache_key TEXT PRIMARY KEY,
          response_json TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
  }

  Future<String?> getCachedTmdbResponse(String key, {Duration maxAge = const Duration(days: 1)}) async {
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'tmdb_cache',
        where: 'cache_key = ?',
        whereArgs: [key],
      );
      if (maps.isEmpty) return null;
      
      final updatedAt = maps.first['updated_at'] as int;
      final age = DateTime.now().millisecondsSinceEpoch - updatedAt;
      if (age > maxAge.inMilliseconds) {
        return null; // Cache expired
      }
      
      return maps.first['response_json'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheTmdbResponse(String key, String jsonStr) async {
    try {
      await db.insert(
        'tmdb_cache',
        {
          'cache_key': key,
          'response_json': jsonStr,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Full data wipe for a Fresh Start (called on logout)
  Future<void> clearAll() async {
    if (_db == null) return;
    await _db!.transaction((txn) async {
      await txn.delete('watchlist');
      await txn.delete('continue_watching');
      await txn.delete('tmdb_cache');
    });
  }
}
