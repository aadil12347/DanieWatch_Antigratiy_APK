import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/manifest_item.dart';

/// Service responsible for syncing, caching, and parsing the positional index.json
/// database file from the GitHub repository.
class DatabaseSyncService {
  DatabaseSyncService._();
  static final DatabaseSyncService instance = DatabaseSyncService._();

  /// Active sync future — prevents duplicate concurrent downloads.
  /// If syncIndex() is called while one is already in progress, it returns
  /// the existing future instead of starting a new HTTP request.
  Future<bool>? _activeSyncFuture;

  static const String _remoteIndexUrl =
      'https://raw.githubusercontent.com/aadil12347/DanieWatch_Apk_Database/main/index.json';
  static const String _indexFileName = 'index_positional.json';
  static const String _tempFileName = 'index_positional_temp.json';

  // ─── 3rd Party Hosted Index ──────────────────────────────────────────────
  static const String _remote3rdPartyUrl =
      'https://raw.githubusercontent.com/aadil12347/DanieWatch_Apk_Database/main/3rd%20party%20hosted/3rd_party_hosted_index.json';
  static const String _3rdPartyFileName = '3rd_party_hosted_index.json';
  static const String _3rdPartyTempFileName = '3rd_party_hosted_temp.json';
  Future<bool>? _active3rdPartySyncFuture;

  /// Returns the file path for the active local index.json database.
  Future<File> get _indexFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_indexFileName');
  }

  /// Returns the file path for the temporary download file.
  Future<File> get _tempFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_tempFileName');
  }

  /// Check if a local database file already exists in cache.
  Future<bool> hasLocalIndex() async {
    final file = await _indexFile;
    return await file.exists();
  }

  /// Sync the index database from GitHub.
  /// Downloads to a temp file, validates it, and only overwrites the primary
  /// file on success. Returns true if sync succeeded.
  /// Deduplicates: if a sync is already in progress, returns the same Future.
  Future<bool> syncIndex() {
    if (_activeSyncFuture != null) {
      dev.log('[DatabaseSync] Sync already in progress — joining existing future.');
      return _activeSyncFuture!;
    }
    _activeSyncFuture = _doSync().whenComplete(() => _activeSyncFuture = null);
    return _activeSyncFuture!;
  }

  Future<bool> _doSync() async {
    try {
      dev.log('[DatabaseSync] Starting sync from $_remoteIndexUrl');
      
      final fileExists = await hasLocalIndex();
      final prefs = await SharedPreferences.getInstance();
      
      final headers = <String, String>{};
      if (fileExists) {
        final savedEtag = prefs.getString('index_etag');
        final savedLastModified = prefs.getString('index_last_modified');
        if (savedEtag != null) {
          headers['If-None-Match'] = savedEtag;
        }
        if (savedLastModified != null) {
          headers['If-Modified-Since'] = savedLastModified;
        }
      }

      final response = await http.get(Uri.parse(_remoteIndexUrl), headers: headers)
          .timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 304) {
        dev.log('[DatabaseSync] 304 Not Modified. Using cached local index.');
        return true;
      }

      if (response.statusCode != 200) {
        dev.log('[DatabaseSync] HTTP Error: ${response.statusCode}');
        return false;
      }

      final rawData = response.body;
      if (rawData.isEmpty) {
        dev.log('[DatabaseSync] Error: Downloaded data is empty.');
        return false;
      }

      // 1. Write to temporary file first
      final tempFile = await _tempFile;
      await tempFile.writeAsString(rawData, flush: true);
      dev.log('[DatabaseSync] Temp file written. Initiating validation...');

      // 2. Validate the downloaded data in a background isolate
      final isValid = await compute(_validateIndexIsolate, rawData);
      if (!isValid) {
        dev.log('[DatabaseSync] Validation failed. Deleting temp file. Primary file preserved.');
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        return false;
      }

      // 3. Validation passed! Overwrite the active index file (Safe Transaction)
      final primaryFile = await _indexFile;
      await tempFile.copy(primaryFile.path);
      
      // Clean up temp file
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      
      // 4. Save ETag / Last-Modified headers for conditional requests
      final etag = response.headers['etag'];
      final lastModified = response.headers['last-modified'];
      if (etag != null) {
        await prefs.setString('index_etag', etag);
      } else {
        await prefs.remove('index_etag');
      }
      if (lastModified != null) {
        await prefs.setString('index_last_modified', lastModified);
      } else {
        await prefs.remove('index_last_modified');
      }

      dev.log('[DatabaseSync] Database successfully synchronized & cached.');

      // Also trigger 3rd party sync in parallel (fire-and-forget)
      // ignore: unawaited_futures
      sync3rdPartyIndex();

      return true;
    } catch (e, stack) {
      dev.log('[DatabaseSync] Sync failed with error: $e', stackTrace: stack);
      // Clean up temp file if needed
      try {
        final tempFile = await _tempFile;
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}

      // Even if main sync fails, still try 3rd party sync
      // ignore: unawaited_futures
      sync3rdPartyIndex();

      return false;
    }
  }

  /// Load and parse the positional index from the local file in a background isolate.
  /// Returns an empty list if no cached index exists yet (e.g. first launch before sync).
  Future<List<ManifestItem>> loadLocalIndex() async {
    try {
      final file = await _indexFile;
      
      if (!await file.exists()) {
        dev.log('[DatabaseSync] Local index file not found. No cached index available yet.');
        return [];
      }

      final rawData = await file.readAsString();
      
      // Parse JSON in a background thread to prevent UI thread blocking
      final items = await compute(_parseIndexIsolate, rawData);
      dev.log('[DatabaseSync] Loaded ${items.length} items from local database file.');
      return items;
    } catch (e, stack) {
      dev.log('[DatabaseSync] Failed to load local database: $e', stackTrace: stack);
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3rd Party Hosted Index — Download, Cache, Load
  // ═══════════════════════════════════════════════════════════════════════════

  Future<File> get _3rdPartyFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_3rdPartyFileName');
  }

  Future<File> get _3rdPartyTempFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_3rdPartyTempFileName');
  }

  Future<bool> hasLocal3rdPartyIndex() async {
    final file = await _3rdPartyFile;
    return await file.exists();
  }

  /// Sync the 3rd party hosted index from GitHub.
  /// Deduplicates concurrent calls like syncIndex().
  Future<bool> sync3rdPartyIndex() {
    if (_active3rdPartySyncFuture != null) {
      dev.log('[DatabaseSync] 3rd party sync already in progress — joining.');
      return _active3rdPartySyncFuture!;
    }
    _active3rdPartySyncFuture = _do3rdPartySync()
        .whenComplete(() => _active3rdPartySyncFuture = null);
    return _active3rdPartySyncFuture!;
  }

  Future<bool> _do3rdPartySync() async {
    try {
      dev.log('[DatabaseSync] Starting 3rd party sync from $_remote3rdPartyUrl');

      final fileExists = await hasLocal3rdPartyIndex();
      final prefs = await SharedPreferences.getInstance();

      final headers = <String, String>{};
      if (fileExists) {
        final savedEtag = prefs.getString('3rdparty_etag');
        final savedLastModified = prefs.getString('3rdparty_last_modified');
        if (savedEtag != null) headers['If-None-Match'] = savedEtag;
        if (savedLastModified != null) headers['If-Modified-Since'] = savedLastModified;
      }

      final response = await http.get(Uri.parse(_remote3rdPartyUrl), headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 304) {
        dev.log('[DatabaseSync] 3rd party: 304 Not Modified.');
        return true;
      }

      if (response.statusCode != 200) {
        dev.log('[DatabaseSync] 3rd party HTTP Error: ${response.statusCode}');
        return false;
      }

      final rawData = response.body;
      if (rawData.isEmpty) {
        dev.log('[DatabaseSync] 3rd party: Downloaded data is empty.');
        return false;
      }

      // 1. Write to temp file
      final tempFile = await _3rdPartyTempFile;
      await tempFile.writeAsString(rawData, flush: true);

      // 2. Validate
      final isValid = await compute(_validateIndexIsolate, rawData);
      if (!isValid) {
        dev.log('[DatabaseSync] 3rd party validation failed.');
        if (await tempFile.exists()) await tempFile.delete();
        return false;
      }

      // 3. Atomic swap
      final primaryFile = await _3rdPartyFile;
      await tempFile.copy(primaryFile.path);
      if (await tempFile.exists()) await tempFile.delete();

      // 4. Save ETag / Last-Modified
      final etag = response.headers['etag'];
      final lastModified = response.headers['last-modified'];
      if (etag != null) {
        await prefs.setString('3rdparty_etag', etag);
      } else {
        await prefs.remove('3rdparty_etag');
      }
      if (lastModified != null) {
        await prefs.setString('3rdparty_last_modified', lastModified);
      } else {
        await prefs.remove('3rdparty_last_modified');
      }

      dev.log('[DatabaseSync] 3rd party index synced successfully.');
      return true;
    } catch (e, stack) {
      dev.log('[DatabaseSync] 3rd party sync failed: $e', stackTrace: stack);
      try {
        final tempFile = await _3rdPartyTempFile;
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      return false;
    }
  }

  /// Load and parse the 3rd party index from local cache.
  Future<List<ManifestItem>> load3rdPartyIndex() async {
    try {
      final file = await _3rdPartyFile;
      if (!await file.exists()) {
        dev.log('[DatabaseSync] 3rd party index not cached yet.');
        return [];
      }
      final rawData = await file.readAsString();
      final items = await compute(_parseIndexIsolate, rawData);
      dev.log('[DatabaseSync] Loaded ${items.length} 3rd party items.');
      return items;
    } catch (e, stack) {
      dev.log('[DatabaseSync] Failed to load 3rd party index: $e', stackTrace: stack);
      return [];
    }
  }
}

/// Helper function running in a separate Isolate to validate the index JSON.
bool _validateIndexIsolate(String rawJson) {
  try {
    final parsed = jsonDecode(rawJson);
    if (parsed is! List) return false;
    if (parsed.isEmpty) return true; // Empty database is valid
    
    // Check if the first element is a list (positional array format)
    final first = parsed.first;
    if (first is! List) return false;
    
    // Must contain at least ID (0) and Title (1)
    if (first.length < 2) return false;
    
    return true;
  } catch (_) {
    return false;
  }
}

/// Helper function running in a separate Isolate to parse index positional arrays to ManifestItems.
List<ManifestItem> _parseIndexIsolate(String rawJson) {
  try {
    final List<dynamic> parsedList = jsonDecode(rawJson);
    return parsedList.map((e) {
      if (e is List) {
        return ManifestItem.fromArray(e);
      }
      // Fallback for dict format just in case
      if (e is Map<String, dynamic>) {
        return ManifestItem.fromJson(e);
      }
      throw FormatException('Unknown item format in database: $e');
    }).toList();
  } catch (e) {
    dev.log('[DatabaseSync Isolate] Parsing error: $e');
    return [];
  }
}
