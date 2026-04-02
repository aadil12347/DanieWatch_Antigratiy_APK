import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import '../domain/models/manifest_item.dart';
import '../data/local/manifest_dao.dart';

/// Result of a sync operation
class SyncResult {
  final bool updated;
  final String? newVersion;
  final int itemCount;
  final String? error;

  const SyncResult({
    required this.updated,
    this.newVersion,
    required this.itemCount,
    this.error,
  });
}

/// Stale-while-revalidate manifest sync engine.
///
/// On app open:
///   1. Read from SQLite immediately → render cached content
///   2. Background: fetch from Supabase Storage → compare generated_at
///   3. If changed: update SQLite, rebuild FTS index, notify listeners
class ManifestSyncEngine {
  ManifestSyncEngine._();
  static final ManifestSyncEngine instance = ManifestSyncEngine._();

  final ManifestDao _dao = ManifestDao();
  final _updateController = StreamController<Manifest>.broadcast();

  Stream<Manifest> get onManifestUpdated => _updateController.stream;

  /// Read cached manifest from SQLite (instant, no network).
  Future<Manifest?> readCache() async {
    final manifest = await _dao.readManifest();
    if (manifest != null) {
      // Ensure index is ready for offline search
      _dao.ensureSearchIndex(manifest.items);
    }
    return manifest;
  }

  /// Fetch manifest from GitHub and update SQLite cache.
  /// Returns SyncResult indicating whether content was updated.
  Future<SyncResult> sync() async {
    try {
      final url = Uri.parse('${Env.githubRawBaseUrl}/index.json');
      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch manifest: ${response.statusCode}');
      }

      final jsonMap = jsonDecode(response.body) as Map<String, dynamic>;

      // Handle both formats: { posts: [...] } or { items: [...] }
      final List<ManifestItem> items;
      if (jsonMap.containsKey('posts')) {
        items = (jsonMap['posts'] as List)
            .map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (jsonMap.containsKey('items')) {
        items = (jsonMap['items'] as List)
            .map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        items = [];
      }

      final manifest = Manifest(
        items: items,
        generatedAt: (jsonMap['last_updated'] ?? jsonMap['generated_at'])?.toString(),
        version: jsonMap['version']?.toString(),
        totalCount: items.length,
      );

      // We always update the cache for GitHub-based data to ensure freshness
      dev.log('[SyncEngine] Manifest sync complete: ${items.length} items');
      await _dao.saveManifest(manifest, Env.appVersion);
      _updateController.add(manifest);

      return SyncResult(
        updated: true,
        newVersion: manifest.version,
        itemCount: manifest.items.length,
      );
    } catch (e, stack) {
      dev.log('[SyncEngine] Sync failed: $e', error: e, stackTrace: stack);
      
      // If sync failed, try clearing stale cache and re-parsing
      try {
        await _dao.clearCache();
        dev.log('[SyncEngine] Cleared stale cache, will retry on next sync');
      } catch (_) {}
      
      return SyncResult(updated: false, itemCount: 0, error: e.toString());
    }
  }

  void dispose() {
    _updateController.close();
  }
}
