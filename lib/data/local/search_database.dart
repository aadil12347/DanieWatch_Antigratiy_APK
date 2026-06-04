import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../local/manifest_dao.dart';
import '../../presentation/providers/search_provider.dart';

/// Local SQLite search database with FTS5 full-text search.
/// Replaces Algolia with instant, offline, zero-cost search.
class SearchDatabase {
  static SearchDatabase? _instance;
  static SearchDatabase get instance => _instance ??= SearchDatabase._();
  SearchDatabase._();

  Database? _db;
  bool _isInitialized = false;

  bool get isReady => _isInitialized;

  /// Language name -> ISO code mapping for filter translation
  static const _langCodeMap = {
    'English': 'en',
    'Hindi': 'hi',
    'Korean': 'ko',
    'Japanese': 'ja',
    'Chinese': 'zh',
    'Turkish': 'tr',
    'Punjabi': 'pa',
    'Urdu': 'ur',
    'Tamil': 'ta',
    'Telugu': 'te',
    'Malayalam': 'ml',
    'Kannada': 'kn',
    'Bengali': 'bn',
    'Marathi': 'mr',
    'French': 'fr',
    'Spanish': 'es',
    'Italian': 'it',
    'German': 'de',
    'Portuguese': 'pt',
    'Russian': 'ru',
    'Arabic': 'ar',
    'Thai': 'th',
  };

  Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'search_catalog.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS items (
        uid TEXT PRIMARY KEY,
        itemId TEXT NOT NULL,
        mediaType TEXT NOT NULL DEFAULT 'movie',
        title TEXT NOT NULL DEFAULT '',
        posterUrl TEXT DEFAULT '',
        genres TEXT DEFAULT '[]',
        originalLanguage TEXT DEFAULT '',
        languages TEXT DEFAULT '[]',
        releaseYear INTEGER DEFAULT 0,
        originCountry TEXT DEFAULT '[]',
        imdbId TEXT DEFAULT '',
        addedAt TEXT DEFAULT '',
        releaseDate TEXT DEFAULT ''
      )
    ''');

    // FTS5 for full-text search on title
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
        title,
        content='items',
        content_rowid='rowid',
        tokenize='unicode61 remove_diacritics 2'
      )
    ''');

    // Triggers to keep FTS in sync
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
        INSERT INTO items_fts(rowid, title) VALUES (new.rowid, new.title);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
        INSERT INTO items_fts(items_fts, rowid, title) VALUES('delete', old.rowid, old.title);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE ON items BEGIN
        INSERT INTO items_fts(items_fts, rowid, title) VALUES('delete', old.rowid, old.title);
        INSERT INTO items_fts(rowid, title) VALUES (new.rowid, new.title);
      END
    ''');

    // Indexes for fast filtering
    await db.execute('CREATE INDEX IF NOT EXISTS idx_year ON items(releaseYear)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_lang ON items(originalLanguage)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_type ON items(mediaType)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_added ON items(addedAt)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Drop and recreate for major schema changes
    await db.execute('DROP TABLE IF EXISTS items_fts');
    await db.execute('DROP TABLE IF EXISTS items');
    await db.execute('DROP TRIGGER IF EXISTS items_ai');
    await db.execute('DROP TRIGGER IF EXISTS items_ad');
    await db.execute('DROP TRIGGER IF EXISTS items_au');
    await _onCreate(db, newVersion);
  }

  /// Bulk insert/replace items from a JSON list.
  /// Each item should have: id, type, title, poster, genres, etc.
  Future<int> insertItems(List<Map<String, dynamic>> items) async {
    final db = await _getDb();
    int count = 0;
    final batch = db.batch();

    for (final item in items) {
      final id = item['id']?.toString() ?? '';
      final type = item['type']?.toString() ?? 'movie';
      if (id.isEmpty) continue;

      final uid = '$id-$type';

      final genres = item['genres'];
      final genresJson = genres is List ? jsonEncode(genres) : '[]';

      final lang = item['language'];
      final langJson = lang is List ? jsonEncode(lang) : '[]';

      final country = item['country'];
      final countryJson = country is List ? jsonEncode(country) : '[]';

      int year = 0;
      try {
        year = int.parse(item['year']?.toString() ?? '0');
      } catch (_) {}

      // Poster: use 'poster' key from index.json
      String posterUrl = item['poster']?.toString() ?? '';
      if (posterUrl.toLowerCase().endsWith('.avif')) posterUrl = '';

      batch.insert(
        'items',
        {
          'uid': uid,
          'itemId': id,
          'mediaType': type,
          'title': item['title']?.toString() ?? '',
          'posterUrl': posterUrl,
          'genres': genresJson,
          'originalLanguage': (item['original_language'] ?? '').toString().toLowerCase(),
          'languages': langJson,
          'releaseYear': year,
          'originCountry': countryJson,
          'imdbId': item['imdb_id']?.toString() ?? '',
          'addedAt': item['addedAt']?.toString() ?? '',
          'releaseDate': item['releaseDate']?.toString() ?? '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      count++;
    }

    await batch.commit(noResult: true);
    return count;
  }

  /// Delete items by their uid (id-type format)
  Future<void> deleteByUids(List<String> uids) async {
    if (uids.isEmpty) return;
    final db = await _getDb();
    final placeholders = uids.map((_) => '?').join(',');
    await db.delete('items', where: 'uid IN ($placeholders)', whereArgs: uids);
  }

  /// Get total item count
  Future<int> getItemCount() async {
    final db = await _getDb();
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM items');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Mark database as initialized
  void markReady() => _isInitialized = true;

  /// Full-text search with filters. Returns ManifestSearchResult list.
  Future<List<ManifestSearchResult>> search(
    String query, {
    SearchFilters? filters,
    int limit = 80,
  }) async {
    final db = await _getDb();

    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    // --- Full-text search ---
    String orderBy = 'i.addedAt DESC'; // default: newest first
    bool useFts = query.trim().isNotEmpty;

    if (useFts) {
      // Use LIKE for simple substring matching (works better for short queries)
      // and FTS5 MATCH for longer queries
      final q = query.trim();
      if (q.length <= 2) {
        whereClauses.add("i.title LIKE ?");
        whereArgs.add('%$q%');
      } else {
        // FTS5 prefix search
        whereClauses.add("i.rowid IN (SELECT rowid FROM items_fts WHERE items_fts MATCH ?)");
        whereArgs.add('"$q"*');
      }
    }

    // --- Filters ---
    if (filters != null) {
      // Genre filter
      if (filters.genres.isNotEmpty) {
        final genreClauses = filters.genres.map((g) {
          whereArgs.add('%"$g"%');
          return "i.genres LIKE ?";
        }).toList();
        whereClauses.add('(${genreClauses.join(' OR ')})');
      }

      // Original language filter (convert display name to ISO code)
      if (filters.originalLanguages.isNotEmpty) {
        final langCodes = filters.originalLanguages.map((l) {
          return _langCodeMap[l] ?? l.toLowerCase();
        }).toList();
        final placeholders = langCodes.map((_) => '?').join(',');
        whereClauses.add("i.originalLanguage IN ($placeholders)");
        whereArgs.addAll(langCodes);
      }

      // Year filter
      if (filters.years.isNotEmpty) {
        final yearInts = filters.years.map((y) => int.tryParse(y) ?? 0).where((y) => y > 0).toList();
        if (yearInts.isNotEmpty) {
          final placeholders = yearInts.map((_) => '?').join(',');
          whereClauses.add("i.releaseYear IN ($placeholders)");
          whereArgs.addAll(yearInts);
        }
      }

      // Sort
      switch (filters.sortBy) {
        case 'Release Year':
          orderBy = 'i.releaseYear DESC, i.addedAt DESC';
          break;
        case 'Title A-Z':
          orderBy = 'i.title ASC';
          break;
        case 'Title Z-A':
          orderBy = 'i.title DESC';
          break;
        case 'Latest Added':
          orderBy = 'i.addedAt DESC';
          break;
        default:
          orderBy = 'i.addedAt DESC';
      }
    }

    final whereString = whereClauses.isEmpty ? '' : 'WHERE ${whereClauses.join(' AND ')}';

    final sql = '''
      SELECT i.* FROM items i
      $whereString
      ORDER BY $orderBy
      LIMIT ?
    ''';
    whereArgs.add(limit);

    final rows = await db.rawQuery(sql, whereArgs);

    return rows.map((row) {
      List<String> parseJsonList(String? json) {
        if (json == null || json.isEmpty || json == '[]') return [];
        try {
          return (jsonDecode(json) as List).map((e) => e.toString()).toList();
        } catch (_) {
          return [];
        }
      }

      return ManifestSearchResult(
        // Convert string ID to a stable positive int via hashCode
        // (matches how ManifestItem.fromJson handles non-numeric IDs)
        itemId: _stableIntId(row['itemId']?.toString() ?? ''),
        mediaType: row['mediaType']?.toString() ?? 'movie',
        title: row['title']?.toString() ?? '',
        score: 1.0,
        posterUrl: row['posterUrl']?.toString(),
        languages: parseJsonList(row['languages']?.toString()),
        genres: parseJsonList(row['genres']?.toString()),
        releaseYear: row['releaseYear'] as int? ?? 0,
        originCountry: parseJsonList(row['originCountry']?.toString()),
        originalLanguage: row['originalLanguage']?.toString(),
      );
    }).toList();
  }

  /// Convert a string ID to a stable positive int.
  /// For numeric strings, returns the parsed int.
  /// For alphanumeric strings (ULIDs), returns a positive hashCode.
  static int _stableIntId(String id) {
    if (id.isEmpty) return 0;
    final parsed = int.tryParse(id);
    if (parsed != null) return parsed;
    // Use hashCode & mask to ensure positive 32-bit int
    return id.hashCode & 0x7FFFFFFF;
  }

  /// Close the database
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _isInitialized = false;
  }
}
