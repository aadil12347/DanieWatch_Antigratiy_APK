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

  /// Display-name language → ISO 639-1 code mapping.
  /// Used to infer originalLanguage for non-TMDB (ULID) items.
  static const _displayLangToIso = {
    'hindi': 'hi',
    'english': 'en',
    'tamil': 'ta',
    'telugu': 'te',
    'malayalam': 'ml',
    'kannada': 'kn',
    'bengali': 'bn',
    'marathi': 'mr',
    'punjabi': 'pa',
    'urdu': 'ur',
    'japanese': 'ja',
    'korean': 'ko',
    'chinese': 'zh',
    'french': 'fr',
    'spanish': 'es',
    'german': 'de',
    'italian': 'it',
    'portuguese': 'pt',
    'russian': 'ru',
    'arabic': 'ar',
    'turkish': 'tr',
    'thai': 'th',
    'gujarati': 'gu',
    'bhojpuri': 'bh',
  };

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
      version: 3,
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

    // FTS4 for full-text search on title (standard table for maximum compatibility)
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts4(
        title,
        tokenize=unicode61
      )
    ''');

    // Triggers to keep FTS in sync
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
        INSERT INTO items_fts(docid, title) VALUES (new.rowid, new.title);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
        DELETE FROM items_fts WHERE docid = old.rowid;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE ON items BEGIN
        UPDATE items_fts SET title = new.title WHERE docid = old.rowid;
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

      final country = item['origin_country'] ?? item['country'];
      final countryJson = country is List ? jsonEncode(country) : '[]';

      int year = 0;
      try {
        year = int.parse(item['year']?.toString() ?? '0');
      } catch (_) {}

      // Poster: use 'poster' key from index
      String posterUrl = item['poster']?.toString() ?? '';
      if (posterUrl.toLowerCase().endsWith('.avif')) posterUrl = '';

      // release_date comes as snake_case from streaming_links JSON
      final releaseDate = (item['release_date'] ?? item['releaseDate'] ?? '').toString();

      // Derive originalLanguage:
      // - For TMDB items (numeric ID): trust original_language from TMDB
      // - For ULID items (non-numeric ID): if original_language is missing/en,
      //   infer from the display-name language array
      String origLang = (item['original_language'] ?? '').toString().toLowerCase();
      final isUlid = int.tryParse(id) == null;
      if (isUlid && (origLang.isEmpty || origLang == 'en')) {
        final langs = lang is List ? lang : [];
        if (langs.isNotEmpty) {
          final displayName = langs.first.toString().toLowerCase();
          origLang = _displayLangToIso[displayName] ?? origLang;
        }
      }

      batch.insert(
        'items',
        {
          'uid': uid,
          'itemId': id,
          'mediaType': type,
          'title': item['title']?.toString() ?? '',
          'posterUrl': posterUrl,
          'genres': genresJson,
          'originalLanguage': origLang,
          'languages': langJson,
          'releaseYear': year,
          'originCountry': countryJson,
          'imdbId': item['imdb_id']?.toString() ?? '',
          'addedAt': item['addedAt']?.toString() ?? '',
          'releaseDate': releaseDate,
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
    // Default sorting: Year (latest), then Date (latest), then recently added.
    String orderBy = 'i.releaseYear DESC, i.releaseDate DESC, i.addedAt DESC';
    bool useFts = query.trim().isNotEmpty;

    if (useFts) {
      // Use LIKE for simple substring matching (works better for short queries)
      // and FTS5 MATCH for longer queries
      final q = query.trim();
      if (q.length <= 2) {
        whereClauses.add("i.title LIKE ?");
        whereArgs.add('%$q%');
      } else {
        // FTS4 prefix search
        whereClauses.add("i.rowid IN (SELECT docid FROM items_fts WHERE items_fts MATCH ?)");
        whereArgs.add('"$q"*');
      }
    }

    // --- Filters ---
    if (filters != null) {
      // Category filter (from navbar)
      if (filters.categories.isNotEmpty) {
        final List<String> catClauses = [];
        
        for (final cat in filters.categories) {
          switch (cat.toLowerCase()) {
            case 'hollywood':
              // Hollywood = everything NOT in the regional/language categories.
              // ONLY filter by originalLanguage (from TMDB) and originCountry.
              // Do NOT filter by display-name languages[] — those are DUB languages,
              // not original languages (e.g. The Godfather dubbed in Hindi is still Hollywood).
              final excludedLangs = ['hi', 'ja', 'ko', 'pa', 'ur', 'zh', 'cn', 'ta', 'te', 'ml', 'kn', 'bn', 'mr', 'gu', 'bh'];
              final placeholders = excludedLangs.map((_) => '?').join(',');
              catClauses.add(
                "(i.originalLanguage NOT IN ($placeholders)"
                " AND i.originCountry NOT LIKE '%IN%'"
                " AND i.originCountry NOT LIKE '%KR%'"
                " AND i.originCountry NOT LIKE '%JP%'"
                " AND i.originCountry NOT LIKE '%PK%'"
                " AND i.originCountry NOT LIKE '%CN%'"
                " AND i.originCountry NOT LIKE '%HK%'"
                " AND i.originCountry NOT LIKE '%TW%'"
                // For items with NO originalLanguage metadata, use display language as fallback
                // to exclude genuinely regional content (not dubs)
                " AND NOT (i.originalLanguage = '' AND ("
                "   i.languages LIKE '%Tamil%'"
                "   OR i.languages LIKE '%Telugu%'"
                "   OR i.languages LIKE '%Malayalam%'"
                "   OR i.languages LIKE '%Kannada%'"
                "   OR i.languages LIKE '%Bengali%'"
                "   OR i.languages LIKE '%Marathi%'"
                "   OR i.languages LIKE '%Japanese%'"
                "   OR i.languages LIKE '%Korean%'"
                "   OR i.languages LIKE '%Urdu%'"
                "   OR UPPER(i.languages) LIKE '%PUNJABI%'"
                "))"
                ")"
              );
              whereArgs.addAll(excludedLangs);
              break;
            case 'indian':
            case 'bollywood':
              catClauses.add(
                "(i.originalLanguage IN ('hi', 'ta', 'te', 'ml', 'kn', 'bn', 'mr', 'gu', 'bh')"
                " OR i.originCountry LIKE '%IN%'"
                // Fallback: check display-name languages for items missing originalLanguage
                " OR (i.originalLanguage = '' AND i.languages LIKE '%Hindi%')"
                " OR (i.originalLanguage = '' AND i.languages LIKE '%Tamil%')"
                " OR (i.originalLanguage = '' AND i.languages LIKE '%Telugu%')"
                " OR (i.originalLanguage = '' AND i.languages LIKE '%Malayalam%')"
                " OR (i.originalLanguage = '' AND i.languages LIKE '%Kannada%')"
                " OR (i.originalLanguage = '' AND i.languages LIKE '%Bengali%')"
                " OR (i.originalLanguage = '' AND i.languages LIKE '%Marathi%')"
                " OR (i.originalLanguage = '' AND i.languages LIKE '%Gujarati%')"
                " OR (i.originalLanguage = '' AND i.languages LIKE '%Bhojpuri%')"
                ")"
              );
              break;
            case 'korean':
            case 'k-drama':
              catClauses.add(
                "(i.originalLanguage = 'ko'"
                " OR i.originCountry LIKE '%KR%'"
                " OR (i.originalLanguage = '' AND i.languages LIKE '%Korean%')"
                ")"
              );
              break;
            case 'anime':
            case 'japanese':
              catClauses.add(
                "(i.originalLanguage = 'ja'"
                " OR i.originCountry LIKE '%JP%'"
                " OR (i.originalLanguage = '' AND i.languages LIKE '%Japanese%')"
                ")"
              );
              break;
            case 'chinese':
              catClauses.add(
                "(i.originalLanguage IN ('zh', 'cn')"
                " OR i.originCountry LIKE '%CN%'"
                " OR i.originCountry LIKE '%TW%'"
                " OR i.originCountry LIKE '%HK%'"
                " OR (i.originalLanguage = '' AND i.languages LIKE '%Chinese%')"
                ")"
              );
              break;
            case 'punjabi':
              catClauses.add(
                "(i.originalLanguage = 'pa'"
                " OR (i.originalLanguage = '' AND UPPER(i.languages) LIKE '%PUNJABI%')"
                ")"
              );
              break;
            case 'pakistani':
              catClauses.add(
                "(i.originalLanguage = 'ur'"
                " OR i.originCountry LIKE '%PK%'"
                " OR (i.originalLanguage = '' AND i.languages LIKE '%Urdu%')"
                ")"
              );
              break;
          }
        }
        
        if (catClauses.isNotEmpty) {
          whereClauses.add('(${catClauses.join(' OR ')})');
        }
      }

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
          orderBy = 'i.releaseYear DESC, i.releaseDate DESC, i.addedAt DESC';
          break;
        case 'Title A-Z':
          orderBy = 'i.title ASC';
          break;
        case 'Title Z-A':
          orderBy = 'i.title DESC';
          break;
        case 'Latest Added':
          orderBy = 'i.addedAt DESC, i.releaseYear DESC, i.releaseDate DESC';
          break;
        case 'Popularity':
        default:
          // Default sorting: Newest release first
          orderBy = 'i.releaseYear DESC, i.releaseDate DESC, i.addedAt DESC';
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
