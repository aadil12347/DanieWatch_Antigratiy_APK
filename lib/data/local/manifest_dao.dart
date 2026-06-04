import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/manifest_item.dart';
import '../../domain/models/catalog_page.dart';
import 'database.dart';

/// Data access object for manifest_cache + paginated catalog cache tables.
class ManifestDao {
  Database get _db => AppDatabase.instance.db;

  static const _cacheTableMs = 30 * 60 * 1000; // 30 minutes in ms

  Future<File> get _manifestFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/manifest_data.json');
  }

  Future<ManifestCacheEntry?> getManifest() async {
    try {
      final rows = await _db.query('manifest_cache', where: 'id = 1', limit: 1);
      if (rows.isEmpty) return null;
      return ManifestCacheEntry.fromMap(rows.first);
    } catch (e) {
      // If the table is corrupt or row is too large from a previous version, clear it.
      await _db.delete('manifest_cache');
      return null;
    }
  }

  Future<bool> isCacheValid(String appVersion) async {
    final entry = await getManifest();
    if (entry == null) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    final age = now - entry.cachedAt;

    // Invalidate if app version changed
    if (entry.appVersion != appVersion) return false;

    // Invalidate if older than 30 minutes
    return age < _cacheTableMs;
  }

  Future<Manifest?> readManifest() async {
    final entry = await getManifest();
    if (entry == null) return null;
    try {
      final file = await _manifestFile;
      if (!await file.exists()) return null;
      
      final dataString = await file.readAsString();
      final json = jsonDecode(dataString) as Map<String, dynamic>;
      return Manifest.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  Future<void> saveManifest(Manifest manifest, String appVersion) async {
    final dataString = jsonEncode(manifest.toJson());
    final file = await _manifestFile;
    await file.writeAsString(dataString);

    final now = DateTime.now().millisecondsSinceEpoch;

    // We store an empty string in the 'data' column so it doesn't exceed the 2MB
    // SQLite CursorWindow limit on Android. The actual data is in manifest_data.json
    await _db.insert(
      'manifest_cache',
      {
        'id': 1,
        'data': '', 
        'version': manifest.version,
        'generated_at': manifest.generatedAt,
        'cached_at': now,
        'app_version': appVersion,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Rebuild FTS search index after saving
    await _rebuildSearchIndex(manifest.items);
  }

  Future<String?> getGeneratedAt() async {
    final entry = await getManifest();
    return entry?.generatedAt;
  }

  /// Clear manifest cache and search index
  Future<void> clearCache() async {
    await _db.delete('manifest_cache');
    await _db.execute('DELETE FROM search_fts');
  }

  Future<void> _rebuildSearchIndex(List<ManifestItem> items) async {
    await _db.transaction((txn) async {
      // Clear existing index
      await txn.execute('DELETE FROM search_fts');

      // Insert all items into FTS
      final batch = txn.batch();
      for (final item in items) {
        batch.insert('search_fts', {
          'item_id': item.id.toString(),
          'media_type': item.mediaType,
          'title': item.title,
          'overview': item.overview ?? '',
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> ensureSearchIndex(List<ManifestItem> items) async {
    final count = Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM search_fts'));
    if (count == 0 && items.isNotEmpty) {
      await _rebuildSearchIndex(items);
    }
  }

  Future<List<ManifestSearchResult>> searchFts(String query) async {
    if (query.trim().isEmpty) return [];

    // FTS4 query: Support multi-word prefix matching (e.g. "The Mat" -> "The* Mat*")
    final tokens = query.trim().split(RegExp(r'\s+'));
    final ftsQuery = tokens.map((t) => '$t*').join(' ');

    final rows = await _db.rawQuery(
      'SELECT item_id, media_type, title FROM search_fts WHERE search_fts MATCH ? LIMIT 50',
      [ftsQuery],
    );

    return rows
        .map((r) => ManifestSearchResult(
              itemId: int.tryParse(r['item_id'] as String) ?? 0,
              mediaType: r['media_type'] as String,
              title: r['title'] as String,
            ))
        .where((r) => r.itemId > 0)
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAGINATED CATALOG CACHE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Save a single page of catalog data to cache.
  Future<void> savePage(String category, CatalogPage page) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dataJson = jsonEncode(page.toJson());
    await _db.insert(
      'catalog_page_cache',
      {
        'category': category,
        'page': page.page,
        'data': dataJson,
        'total_pages': page.totalPages,
        'total_items': page.totalItems,
        'cached_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Load a cached page. Returns null if not cached.
  Future<CatalogPage?> loadPage(String category, int page) async {
    try {
      final rows = await _db.query(
        'catalog_page_cache',
        where: 'category = ? AND page = ?',
        whereArgs: [category, page],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final json = jsonDecode(rows.first['data'] as String) as Map<String, dynamic>;
      return CatalogPage.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  /// Check if a cached page is still fresh (< 30 minutes old).
  Future<bool> isPageFresh(String category, int page) async {
    final rows = await _db.query(
      'catalog_page_cache',
      columns: ['cached_at'],
      where: 'category = ? AND page = ?',
      whereArgs: [category, page],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final cachedAt = rows.first['cached_at'] as int;
    final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
    return age < _cacheTableMs;
  }

  /// Invalidate all cached pages for a specific category.
  Future<void> invalidateCategory(String category) async {
    await _db.delete(
      'catalog_page_cache',
      where: 'category = ?',
      whereArgs: [category],
    );
  }

  /// Invalidate all cached pages across all categories.
  Future<void> invalidateAllPages() async {
    await _db.delete('catalog_page_cache');
  }

  // ─── Catalog Metadata ───────────────────────────────────────────────────

  /// Save catalog metadata (version, page counts).
  Future<void> saveCatalogMeta(CatalogMeta meta) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert(
      'catalog_meta',
      {
        'id': 1,
        'version': meta.version,
        'data': jsonEncode(meta.toJson()),
        'cached_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Load cached catalog metadata.
  Future<CatalogMeta?> loadCatalogMeta() async {
    try {
      final rows = await _db.query('catalog_meta', where: 'id = 1', limit: 1);
      if (rows.isEmpty) return null;
      final json = jsonDecode(rows.first['data'] as String) as Map<String, dynamic>;
      return CatalogMeta.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  /// Get the cached catalog version string.
  Future<String?> getCatalogVersion() async {
    final rows = await _db.query(
      'catalog_meta',
      columns: ['version'],
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['version'] as String?;
  }

  // ─── Search Index ───────────────────────────────────────────────────────

  /// Save the lightweight search index.
  Future<void> saveSearchIndex(List<SearchIndexEntry> entries, String? version) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dataJson = jsonEncode(entries.map((e) => e.toJson()).toList());
    await _db.insert(
      'search_index_cache',
      {
        'id': 1,
        'data': dataJson,
        'version': version,
        'cached_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Load cached search index.
  Future<List<SearchIndexEntry>?> loadSearchIndex() async {
    try {
      final rows = await _db.query('search_index_cache', where: 'id = 1', limit: 1);
      if (rows.isEmpty) return null;
      final jsonList = jsonDecode(rows.first['data'] as String) as List<dynamic>;
      return jsonList
          .map((e) => SearchIndexEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return null;
    }
  }

  /// Get the cached search index version.
  Future<String?> getSearchIndexVersion() async {
    final rows = await _db.query(
      'search_index_cache',
      columns: ['version'],
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['version'] as String?;
  }

  // ─── Home Sections ──────────────────────────────────────────────────────

  /// Save pre-built home sections data.
  Future<void> saveHomeSections(HomeSectionsData sections, String? version) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dataJson = jsonEncode(sections.toJson());
    await _db.insert(
      'home_sections_cache',
      {
        'id': 1,
        'data': dataJson,
        'version': version,
        'cached_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Load cached home sections data.
  Future<HomeSectionsData?> loadHomeSections() async {
    try {
      final rows = await _db.query('home_sections_cache', where: 'id = 1', limit: 1);
      if (rows.isEmpty) return null;
      final json = jsonDecode(rows.first['data'] as String) as Map<String, dynamic>;
      return HomeSectionsData.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  /// Check if home sections cache is fresh.
  Future<bool> isHomeSectionsFresh() async {
    final rows = await _db.query(
      'home_sections_cache',
      columns: ['cached_at'],
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final cachedAt = rows.first['cached_at'] as int;
    final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
    return age < _cacheTableMs;
  }
}

class ManifestCacheEntry {
  final String data;
  final String? version;
  final String? generatedAt;
  final int cachedAt;
  final String? appVersion;

  const ManifestCacheEntry({
    required this.data,
    this.version,
    this.generatedAt,
    required this.cachedAt,
    this.appVersion,
  });

  factory ManifestCacheEntry.fromMap(Map<String, dynamic> map) =>
      ManifestCacheEntry(
        data: map['data'] as String,
        version: map['version'] as String?,
        generatedAt: map['generated_at'] as String?,
        cachedAt: map['cached_at'] as int,
        appVersion: map['app_version'] as String?,
      );
}

class ManifestSearchResult {
  final int itemId;
  final String mediaType;
  final String title;
  final double score;
  final String? posterUrl;
  final List<String> languages;
  final List<String> genres;
  final int releaseYear;
  final List<String> originCountry;
  final String? originalLanguage;

  const ManifestSearchResult({
    required this.itemId,
    required this.mediaType,
    required this.title,
    this.score = 0.0,
    this.posterUrl,
    this.languages = const [],
    this.genres = const [],
    this.releaseYear = 0,
    this.originCountry = const [],
    this.originalLanguage,
  });
}
