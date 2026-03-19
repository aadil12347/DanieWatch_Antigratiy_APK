import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:supabase_flutter/supabase_flutter.dart';

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

  SupabaseClient get _client => Supabase.instance.client;

  /// Read cached manifest from SQLite (instant, no network).
  Future<Manifest?> readCache() async {
    final manifest = await _dao.readManifest();
    if (manifest != null) {
      // Ensure index is ready for offline search
      _dao.ensureSearchIndex(manifest.items);
    }
    return manifest;
  }

  /// Fetch manifest from Supabase Storage bucket and check if it's newer.
  /// Returns SyncResult indicating whether content was updated.
  Future<SyncResult> sync() async {
    try {
      // Download manifest from storage bucket
      final bytes = await _client.storage
          .from(Env.manifestBucket)
          .download(Env.manifestPath);

      final jsonStr = utf8.decode(bytes);
      final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Handle both formats: { items: [...] } or just [...]
      final Manifest manifest;
      if (jsonMap.containsKey('items')) {
        manifest = Manifest.fromJson(jsonMap);
      } else {
        // Legacy: the file itself is an array wrapped in a container
        final items = (jsonMap['data'] as List?)
                ?.map(
                    (e) => ManifestItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        manifest = Manifest(
          items: items,
          generatedAt: jsonMap['generated_at'] as String?,
          version: jsonMap['version']?.toString(),
          totalCount: items.length,
        );
      }

      // Compare with cached generated_at
      final cachedGeneratedAt = await _dao.getGeneratedAt();
      final remoteGeneratedAt = manifest.generatedAt;

      final isNewer = remoteGeneratedAt != null &&
          remoteGeneratedAt != cachedGeneratedAt;

      if (isNewer) {
        dev.log(
            '[SyncEngine] Manifest updated: $cachedGeneratedAt → $remoteGeneratedAt');
        await _dao.saveManifest(manifest, Env.appVersion);
        _updateController.add(manifest);
        return SyncResult(
          updated: true,
          newVersion: manifest.version,
          itemCount: manifest.items.length,
        );
      }

      dev.log(
          '[SyncEngine] Manifest unchanged (${manifest.items.length} items)');
      return SyncResult(
        updated: false,
        newVersion: manifest.version,
        itemCount: manifest.items.length,
      );
    } catch (e, stack) {
      dev.log('[SyncEngine] Sync failed: $e', error: e, stackTrace: stack);
      return SyncResult(updated: false, itemCount: 0, error: e.toString());
    }
  }

  void dispose() {
    _updateController.close();
  }
}
