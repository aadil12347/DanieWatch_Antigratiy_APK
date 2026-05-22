import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/app_update_info.dart';
import '../config/env.dart';

/// Singleton service for checking, downloading, and installing app updates.
///
/// Uses a JSON file hosted on GitHub (`app_update.json`) to determine if
/// an update is available. Supports resumable downloads and persistent
/// state tracking across app restarts.
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  // SharedPreferences keys for persisting download state
  static const _keyTargetVersion = 'update_target_version';
  static const _keyApkPath = 'update_apk_path';
  static const _keyBytesDownloaded = 'update_bytes_downloaded';
  static const _keyTotalBytes = 'update_total_bytes';
  static const _keyDownloadComplete = 'update_download_complete';

  /// Platform channel for triggering native APK installation.
  static const _installChannel = MethodChannel('com.daniewatch/install_apk');

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 120),
  ));

  CancelToken? _downloadCancelToken;

  // ─────────────────────────────────────────────────────────
  // A. CHECK FOR UPDATES
  // ─────────────────────────────────────────────────────────

  /// Fetches `app_update.json` from GitHub and returns [AppUpdateInfo]
  /// if an update is available (remote version ≠ current app version).
  /// Returns `null` if app is up-to-date or if the check fails.
  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final url = '${Env.githubRawBaseUrl}/app_update.json';
      debugPrint('🔄 AppUpdate: Checking for updates at $url');

      final response = await _dio.get<String>(
        url,
        options: Options(
          // Bypass any GitHub CDN cache
          headers: {'Cache-Control': 'no-cache'},
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        debugPrint('🔄 AppUpdate: Non-200 response or null data');
        return null;
      }

      final json = jsonDecode(response.data!) as Map<String, dynamic>;
      final info = AppUpdateInfo.fromJson(json);

      if (info.version.isEmpty || info.downloadUrl.isEmpty) {
        debugPrint('🔄 AppUpdate: Invalid update JSON (missing version or URL)');
        return null;
      }

      // Compare remote version with current app version (semver)
      if (_isNewerVersion(info.version, Env.appVersion)) {
        debugPrint('🔄 AppUpdate: Update available! '
            'Current: ${Env.appVersion}, Remote: ${info.version}');
        return info;
      }

      debugPrint('🔄 AppUpdate: App is up-to-date (${Env.appVersion})');
      return null;
    } catch (e) {
      debugPrint('🔄 AppUpdate: Error checking for updates: $e');
      return null;
    }
  }

  /// Returns true if [remote] is a strictly higher version than [current].
  /// Supports standard semver: "1.2.3" > "1.2.0" > "1.0.0"
  /// Prevents downgrades: "0.9.0" vs "1.0.0" → false.
  static bool _isNewerVersion(String remote, String current) {
    final remoteParts =
        remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentParts =
        current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    // Pad to at least 3 parts
    while (remoteParts.length < 3) remoteParts.add(0);
    while (currentParts.length < 3) currentParts.add(0);

    for (int i = 0; i < 3; i++) {
      if (remoteParts[i] > currentParts[i]) return true;
      if (remoteParts[i] < currentParts[i]) return false;
    }
    return false; // versions are equal
  }

  // ─────────────────────────────────────────────────────────
  // B. DETERMINE UPDATE STATE ON STARTUP
  // ─────────────────────────────────────────────────────────

  /// Determines the current download/install state by checking
  /// SharedPreferences and the file system.
  ///
  /// Returns one of:
  /// - `null` — no prior download state exists
  /// - A map with keys: `state` ("resumable" | "complete"), `path`, `bytesDownloaded`, `totalBytes`
  Future<Map<String, dynamic>?> getPersistedState(String targetVersion) async {
    final prefs = await SharedPreferences.getInstance();
    final savedVersion = prefs.getString(_keyTargetVersion);

    // If the saved version doesn't match what we're looking for, no state
    if (savedVersion != targetVersion) {
      return null;
    }

    final apkPath = prefs.getString(_keyApkPath);
    if (apkPath == null || apkPath.isEmpty) return null;

    final file = File(apkPath);
    if (!await file.exists()) {
      // File was deleted or corrupted — clear state
      await _clearPersistedState();
      return null;
    }

    final isComplete = prefs.getBool(_keyDownloadComplete) ?? false;
    final totalBytes = prefs.getInt(_keyTotalBytes) ?? 0;
    final actualFileSize = await file.length();

    if (isComplete) {
      // Verify file size integrity
      if (totalBytes > 0 && actualFileSize >= totalBytes) {
        return {
          'state': 'complete',
          'path': apkPath,
          'bytesDownloaded': actualFileSize,
          'totalBytes': totalBytes,
        };
      } else {
        // File is incomplete despite flag — treat as resumable
        return {
          'state': 'resumable',
          'path': apkPath,
          'bytesDownloaded': actualFileSize,
          'totalBytes': totalBytes,
        };
      }
    } else {
      // Partial download
      if (actualFileSize > 0) {
        return {
          'state': 'resumable',
          'path': apkPath,
          'bytesDownloaded': actualFileSize,
          'totalBytes': totalBytes,
        };
      }
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────
  // C. DOWNLOAD APK (WITH RESUME SUPPORT)
  // ─────────────────────────────────────────────────────────

  /// Downloads the APK file from [downloadUrl] to the app's documents directory.
  ///
  /// Supports resuming from a previously interrupted download. Calls
  /// [onProgress] with (received, total) bytes periodically.
  ///
  /// Returns the full path to the downloaded APK file.
  Future<String> downloadApk({
    required String downloadUrl,
    required String targetVersion,
    required void Function(int received, int total) onProgress,
  }) async {
    _downloadCancelToken = CancelToken();

    // Determine save path
    final dir = await getApplicationDocumentsDirectory();
    final updateDir = Directory('${dir.path}/updates');
    if (!await updateDir.exists()) {
      await updateDir.create(recursive: true);
    }
    final apkPath = '${updateDir.path}/daniewatch_update.apk';
    final file = File(apkPath);

    // Check for existing partial file (resume support)
    int resumeFrom = 0;
    if (await file.exists()) {
      resumeFrom = await file.length();
      debugPrint('🔄 AppUpdate: Resuming download from $resumeFrom bytes');
    }

    // Persist state
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTargetVersion, targetVersion);
    await prefs.setString(_keyApkPath, apkPath);
    await prefs.setBool(_keyDownloadComplete, false);

    try {
      final response = await _dio.get<ResponseBody>(
        downloadUrl,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          maxRedirects: 5,
          headers: resumeFrom > 0
              ? {'Range': 'bytes=$resumeFrom-'}
              : null,
        ),
        cancelToken: _downloadCancelToken,
      );

      // Determine total size
      final contentLength = response.headers.value(Headers.contentLengthHeader);
      int totalBytes;
      
      if (response.statusCode == 206) {
        // Partial content — server supports resume
        totalBytes = resumeFrom + (int.tryParse(contentLength ?? '') ?? 0);
      } else {
        // Full content — either no resume support or fresh download
        totalBytes = int.tryParse(contentLength ?? '') ?? 0;
        // Server doesn't support range — start from scratch
        if (resumeFrom > 0 && response.statusCode == 200) {
          resumeFrom = 0;
          if (await file.exists()) await file.delete();
        }
      }

      await prefs.setInt(_keyTotalBytes, totalBytes);

      // Write to file (append if resuming, write if fresh)
      final raf = await file.open(
        mode: resumeFrom > 0 && response.statusCode == 206
            ? FileMode.append
            : FileMode.write,
      );

      int received = resumeFrom;
      int lastSavedMilestone = resumeFrom;
      final milestoneInterval = totalBytes > 0 ? (totalBytes * 0.1).toInt() : 1024 * 1024;

      try {
        await for (final chunk in response.data!.stream) {
          await raf.writeFrom(chunk);
          received += chunk.length;

          onProgress(received, totalBytes);

          // Persist progress at milestones (every ~10%)
          if (received - lastSavedMilestone >= milestoneInterval) {
            await prefs.setInt(_keyBytesDownloaded, received);
            lastSavedMilestone = received;
          }
        }
      } finally {
        await raf.close();
      }

      // Mark download as complete
      await prefs.setInt(_keyBytesDownloaded, received);
      await prefs.setBool(_keyDownloadComplete, true);

      debugPrint('🔄 AppUpdate: Download complete! File: $apkPath ($received bytes)');
      return apkPath;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        debugPrint('🔄 AppUpdate: Download cancelled');
        // Don't clear state — allow resume later
        rethrow;
      }
      debugPrint('🔄 AppUpdate: Download error: $e');
      // Don't delete the file — allow resume
      rethrow;
    }
  }

  /// Cancels an in-progress download.
  void cancelDownload() {
    _downloadCancelToken?.cancel('User cancelled');
    _downloadCancelToken = null;
  }

  // ─────────────────────────────────────────────────────────
  // D. INSTALL APK
  // ─────────────────────────────────────────────────────────

  /// Triggers the Android system package installer for the APK at [apkPath].
  ///
  /// Returns `true` if the install intent was launched successfully.
  /// Returns `false` if the user needs to enable "Install unknown apps" permission.
  /// Throws if there's a platform error.
  Future<String> installApk(String apkPath) async {
    try {
      final result = await _installChannel.invokeMethod<String>(
        'installApk',
        {'apkPath': apkPath},
      );
      return result ?? 'success';
    } on PlatformException catch (e) {
      debugPrint('🔄 AppUpdate: Install error: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────
  // E. CLEANUP
  // ─────────────────────────────────────────────────────────

  /// Cleans up downloaded APK and persisted state.
  /// Called on app start when the current version matches the target version
  /// (i.e., the update was successfully installed).
  Future<void> cleanupIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final savedVersion = prefs.getString(_keyTargetVersion);

    if (savedVersion == null) return; // No update was in progress

    // If our current version matches what we were trying to update TO,
    // it means the install was successful → clean up!
    if (savedVersion == Env.appVersion) {
      debugPrint('🔄 AppUpdate: Update to $savedVersion was successful! Cleaning up...');
      final apkPath = prefs.getString(_keyApkPath);
      if (apkPath != null) {
        final file = File(apkPath);
        if (await file.exists()) {
          await file.delete();
          debugPrint('🔄 AppUpdate: Deleted old APK: $apkPath');
        }
        // Also try to remove the updates directory if empty
        final dir = file.parent;
        if (await dir.exists()) {
          final children = await dir.list().toList();
          if (children.isEmpty) {
            await dir.delete();
          }
        }
      }
      await _clearPersistedState();
    }
    // If savedVersion != Env.appVersion, the update hasn't been installed yet.
    // The modal will handle this case.
  }

  /// Clears all persisted update state from SharedPreferences.
  Future<void> _clearPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyTargetVersion);
    await prefs.remove(_keyApkPath);
    await prefs.remove(_keyBytesDownloaded);
    await prefs.remove(_keyTotalBytes);
    await prefs.remove(_keyDownloadComplete);
    debugPrint('🔄 AppUpdate: Cleared persisted update state');
  }


  /// Clears state for a version that no longer matches the remote update.
  /// Called when a NEW update is pushed and the old download is stale.
  Future<void> clearStaleState() async {
    final prefs = await SharedPreferences.getInstance();
    final apkPath = prefs.getString(_keyApkPath);
    if (apkPath != null) {
      final file = File(apkPath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('🔄 AppUpdate: Deleted stale APK: $apkPath');
      }
    }
    await _clearPersistedState();
  }
}
