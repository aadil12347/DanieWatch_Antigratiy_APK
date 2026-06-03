import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/manifest_item.dart';
import 'database.dart';

/// Data access object for manifest_cache table.
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

  const ManifestSearchResult({
    required this.itemId,
    required this.mediaType,
    required this.title,
    this.score = 0.0,
  });
}
