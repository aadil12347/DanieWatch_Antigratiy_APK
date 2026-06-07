import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/manifest_item.dart';

/// Service responsible for syncing, caching, and parsing the positional index.json
/// database file from the GitHub repository.
class DatabaseSyncService {
  DatabaseSyncService._();
  static final DatabaseSyncService instance = DatabaseSyncService._();

  static const String _remoteIndexUrl =
      'https://raw.githubusercontent.com/aadil12347/DanieWatch_Apk_Database/main/index.json';
  static const String _indexFileName = 'index_positional.json';
  static const String _tempFileName = 'index_positional_temp.json';

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
  Future<bool> syncIndex() async {
    try {
      dev.log('[DatabaseSync] Starting sync from $_remoteIndexUrl');
      final response = await http.get(Uri.parse(_remoteIndexUrl));
      
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
      
      dev.log('[DatabaseSync] Database successfully synchronized & cached.');
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
      return false;
    }
  }

  /// Load and parse the positional index from the local file in a background isolate.
  Future<List<ManifestItem>> loadLocalIndex() async {
    try {
      final file = await _indexFile;
      
      bool fileIsValid = false;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty && content.trim() != '[]') {
          fileIsValid = true;
        }
      }

      if (!fileIsValid) {
        dev.log('[DatabaseSync] Local index file not found or empty. Loading placeholder from assets/base_index.json...');
        try {
          final placeholderData = await rootBundle.loadString('assets/base_index.json');
          await file.writeAsString(placeholderData, flush: true);
          dev.log('[DatabaseSync] Bundled placeholder cached successfully.');
        } catch (assetErr) {
          dev.log('[DatabaseSync] Error loading bundled placeholder: $assetErr');
          return [];
        }
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
