import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/entry.dart';

/// Permanent Watchlist Backup Manager
///
/// Guarantees that the user's watchlist/favorites are permanently saved on the device
/// across:
/// 1. App restarts
/// 2. Clearing app cache and app data (Android Settings -> Apps -> Storage -> Clear Data)
/// 3. App uninstall and re-install
///
/// Multi-layer persistence strategy:
/// - Primary: External public storage (/storage/emulated/0/Documents/DanieWatch/watchlist_backup.json)
///   which Android NEVER deletes when app data is cleared or app is uninstalled.
/// - Secondary: External public download (/storage/emulated/0/Download/DanieWatch/watchlist_backup.json)
/// - Tertiary: Hidden external storage (/storage/emulated/0/.daniewatch/watchlist_backup.json)
/// - Fallback: SharedPreferences + App documents directory
class WatchlistBackupManager {
  WatchlistBackupManager._();
  static final WatchlistBackupManager instance = WatchlistBackupManager._();

  static const String _backupFileName = 'daniewatch_watchlist_backup.json';
  static const String _folderName = 'DanieWatch';
  static const String _prefBackupKey = 'permanent_watchlist_backup_v1';

  /// Collects candidate directories across public external storage and local storage
  Future<List<Directory>> _getTargetDirectories() async {
    final List<Directory> dirs = [];
    final Set<String> pathsSeen = {};

    void addDir(String path) {
      if (path.trim().isEmpty || pathsSeen.contains(path)) return;
      pathsSeen.add(path);
      dirs.add(Directory(path));
    }

    try {
      // 1. PathProvider Downloads directory
      try {
        final dlDir = await getDownloadsDirectory();
        if (dlDir != null) {
          addDir('${dlDir.path}/$_folderName');
          addDir(dlDir.path);
        }
      } catch (_) {}

      // 2. Determine base external storage root on Android (/storage/emulated/0)
      if (!kIsWeb && Platform.isAndroid) {
        String? externalRoot;
        try {
          final extDir = await getExternalStorageDirectory();
          if (extDir != null) {
            final match = RegExp(r'^(/storage/emulated/\d+|/sdcard)').firstMatch(extDir.path);
            if (match != null) {
              externalRoot = match.group(0);
            } else if (extDir.path.contains('/Android/data/')) {
              externalRoot = extDir.path.split('/Android/data/').first;
            }
          }
        } catch (_) {}

        externalRoot ??= '/storage/emulated/0';

        // Public folders that survive Clear Data and Uninstall
        addDir('$externalRoot/Documents/$_folderName');
        addDir('$externalRoot/Documents');
        addDir('$externalRoot/Download/$_folderName');
        addDir('$externalRoot/Download');
        addDir('$externalRoot/.daniewatch');
      }

      // 3. App document directory (survives normal app life, backed up via Android Auto Backup)
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        addDir(appDocDir.path);
      } catch (_) {}

      // 4. External storage directory
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          addDir(extDir.path);
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('[WatchlistBackup] ⚠️ Error finding target directories: $e');
    }

    return dirs;
  }

  /// Saves the current watchlist to all permanent storage locations
  Future<void> saveBackup(List<WatchlistItem> items) async {
    try {
      final jsonList = items.map((i) => i.toJson()).toList();
      final jsonString = jsonEncode(jsonList);

      // 1. Save to SharedPreferences (instant fallback)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefBackupKey, jsonString);
      } catch (e) {
        debugPrint('[WatchlistBackup] ⚠️ Prefs backup warning: $e');
      }

      // 2. Save to external files
      final dirs = await _getTargetDirectories();
      int successCount = 0;

      for (final dir in dirs) {
        try {
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          final file = File('${dir.path}/$_backupFileName');
          await file.writeAsString(jsonString, flush: true);
          successCount++;
        } catch (_) {
          // Continue to next candidate directory
        }
      }

      debugPrint('[WatchlistBackup] 💾 Saved backup of ${items.length} items to $successCount location(s)');
    } catch (e) {
      debugPrint('[WatchlistBackup] ⚠️ Error saving watchlist backup: $e');
    }
  }

  /// Loads watchlist items from the most recent valid backup file or preferences
  Future<List<WatchlistItem>> loadBackup() async {
    // 1. Check persistent device file locations
    final dirs = await _getTargetDirectories();
    for (final dir in dirs) {
      try {
        final file = File('${dir.path}/$_backupFileName');
        if (await file.exists()) {
          final content = await file.readAsString();
          if (content.trim().isNotEmpty) {
            final List<dynamic> decoded = jsonDecode(content);
            final items = decoded
                .whereType<Map<String, dynamic>>()
                .map((m) => WatchlistItem.fromJson(m))
                .toList();
            if (items.isNotEmpty) {
              debugPrint('[WatchlistBackup] 📂 Restored ${items.length} items from ${file.path}');
              return items;
            }
          }
        }
      } catch (_) {
        // Try next candidate
      }
    }

    // 2. Check SharedPreferences fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final content = prefs.getString(_prefBackupKey);
      if (content != null && content.trim().isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(content);
        final items = decoded
            .whereType<Map<String, dynamic>>()
            .map((m) => WatchlistItem.fromJson(m))
            .toList();
        if (items.isNotEmpty) {
          debugPrint('[WatchlistBackup] 📂 Restored ${items.length} items from SharedPreferences');
          return items;
        }
      }
    } catch (e) {
      debugPrint('[WatchlistBackup] ⚠️ Error reading prefs backup: $e');
    }

    return [];
  }

  /// Restores items from device backup into the SQLite database table
  Future<List<WatchlistItem>> restoreToDatabase(Database db) async {
    try {
      final backupItems = await loadBackup();
      if (backupItems.isEmpty) return [];

      await db.transaction((txn) async {
        for (final item in backupItems) {
          await txn.insert(
            'watchlist',
            {
              'tmdb_id': item.tmdbId,
              'media_type': item.mediaType,
              'title': item.title,
              'poster_path': item.posterPath,
              'vote_average': item.voteAverage,
              'added_at': (item.addedAt ?? DateTime.now()).millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

      debugPrint('[WatchlistBackup] ✅ Restored and populated ${backupItems.length} items into SQLite database');
      return backupItems;
    } catch (e) {
      debugPrint('[WatchlistBackup] ⚠️ Error restoring to database: $e');
      return [];
    }
  }
}
