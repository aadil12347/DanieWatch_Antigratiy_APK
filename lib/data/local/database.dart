import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite database manager — single instance, handles schema + migrations.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'daniewatch.db';
  static const _schemaVersion = 2;

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
      CREATE TABLE manifest_cache (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        data TEXT NOT NULL,
        version TEXT,
        generated_at TEXT,
        cached_at INTEGER NOT NULL,
        app_version TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE entry_cache (
        entry_id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        content TEXT NOT NULL,
        title TEXT,
        poster_url TEXT,
        backdrop_url TEXT,
        overview TEXT,
        tagline TEXT,
        runtime INTEGER,
        genres TEXT,
        cast_data TEXT,
        vote_average REAL DEFAULT 0,
        cached_at INTEGER NOT NULL
      )
    ''');

    // Full-text search for offline search
    await db.execute('''
      CREATE VIRTUAL TABLE search_fts USING fts4(
        item_id TEXT,
        media_type TEXT,
        title TEXT,
        overview TEXT,
        tokenize=porter
      )
    ''');

    // Watchlist (local guest storage)
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

    // Sync metadata KV store
    await db.execute('''
      CREATE TABLE sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // TMDB enrichment queue
    await db.execute('''
      CREATE TABLE enrichment_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tmdb_id INTEGER NOT NULL,
        media_type TEXT NOT NULL,
        missing_fields TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        attempts INTEGER DEFAULT 0,
        last_attempt_at INTEGER,
        created_at INTEGER NOT NULL,
        UNIQUE(tmdb_id, media_type)
      )
    ''');

    // Indexes for performance
    await db.execute(
        'CREATE INDEX idx_entry_cache_cached ON entry_cache(cached_at)');

    // ━━━ Paginated Catalog Cache Tables (v2) ━━━
    await _createPaginatedTables(db);
  }

  /// Create tables for paginated catalog caching.
  /// Separated so they can be called from both _onCreate and _onUpgrade.
  Future<void> _createPaginatedTables(Database db) async {
    // Per-page cache: stores individual pages of each category
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_page_cache (
        category TEXT NOT NULL,
        page INTEGER NOT NULL,
        data TEXT NOT NULL,
        total_pages INTEGER,
        total_items INTEGER,
        cached_at INTEGER NOT NULL,
        PRIMARY KEY (category, page)
      )
    ''');

    // Catalog metadata: version + page counts (tiny, single row)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_meta (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        version TEXT NOT NULL,
        data TEXT NOT NULL,
        cached_at INTEGER NOT NULL
      )
    ''');

    // Search index cache: lightweight id+title+type+language for all items
    await db.execute('''
      CREATE TABLE IF NOT EXISTS search_index_cache (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        data TEXT NOT NULL,
        version TEXT,
        cached_at INTEGER NOT NULL
      )
    ''');

    // Home sections cache: pre-built home screen data
    await db.execute('''
      CREATE TABLE IF NOT EXISTS home_sections_cache (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        data TEXT NOT NULL,
        version TEXT,
        cached_at INTEGER NOT NULL
      )
    ''');

    // Index for page cache lookups
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_page_cache_cat ON catalog_page_cache(category, cached_at)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2: Add paginated catalog cache tables
    // Preserves: watchlist, continue_watching, sync_meta, entry_cache
    if (oldVersion < 2) {
      await _createPaginatedTables(db);
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Nuke all caches (called on version change / force refresh)
  Future<void> invalidateAll() async {
    final database = db;
    await database.transaction((txn) async {
      await txn.delete('manifest_cache');
      await txn.delete('entry_cache');
      await txn.execute('DELETE FROM search_fts');
      await txn.delete('enrichment_queue');
      // Paginated cache tables
      await txn.delete('catalog_page_cache');
      await txn.delete('catalog_meta');
      await txn.delete('search_index_cache');
      await txn.delete('home_sections_cache');
    });
  }

  /// Full data wipe for a Fresh Start (called on logout)
  Future<void> clearAll() async {
    if (_db == null) return;
    await _db!.transaction((txn) async {
      await txn.delete('manifest_cache');
      await txn.delete('entry_cache');
      await txn.execute('DELETE FROM search_fts');
      await txn.delete('watchlist');
      await txn.delete('continue_watching');
      await txn.delete('sync_meta');
      await txn.delete('enrichment_queue');
      // Paginated cache tables
      await txn.delete('catalog_page_cache');
      await txn.delete('catalog_meta');
      await txn.delete('search_index_cache');
      await txn.delete('home_sections_cache');
    });
  }
}
