import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/app_update_service.dart';
import '../../domain/models/app_update_info.dart';

// ─────────────────────────────────────────────────────────
// UPDATE STATE
// ─────────────────────────────────────────────────────────

/// All possible states for the app update flow.
sealed class AppUpdateState {
  const AppUpdateState();
}

/// Checking for updates (initial state).
class AppUpdateChecking extends AppUpdateState {
  const AppUpdateChecking();
}

/// App is up-to-date — no update needed.
class AppUpdateUpToDate extends AppUpdateState {
  const AppUpdateUpToDate();
}

/// Update available, APK not downloaded yet.
class AppUpdateReadyToDownload extends AppUpdateState {
  final AppUpdateInfo info;
  const AppUpdateReadyToDownload(this.info);
}

/// Update available, partial APK exists on disk — can resume.
class AppUpdateReadyToResume extends AppUpdateState {
  final AppUpdateInfo info;
  final int bytesDownloaded;
  final int totalBytes;
  const AppUpdateReadyToResume(this.info, this.bytesDownloaded, this.totalBytes);
}

/// APK fully downloaded, ready to install.
class AppUpdateReadyToInstall extends AppUpdateState {
  final AppUpdateInfo info;
  final String apkPath;
  const AppUpdateReadyToInstall(this.info, this.apkPath);
}

/// Currently downloading APK.
class AppUpdateDownloading extends AppUpdateState {
  final AppUpdateInfo info;
  final double progress; // 0.0 to 1.0
  final int receivedBytes;
  final int totalBytes;
  const AppUpdateDownloading(this.info, this.progress, this.receivedBytes, this.totalBytes);
}

/// Download failed.
class AppUpdateDownloadError extends AppUpdateState {
  final AppUpdateInfo info;
  final String errorMessage;
  const AppUpdateDownloadError(this.info, this.errorMessage);
}

/// Install intent triggered, waiting for user to confirm in Android installer.
class AppUpdateInstalling extends AppUpdateState {
  final AppUpdateInfo info;
  final String apkPath;
  const AppUpdateInstalling(this.info, this.apkPath);
}

/// User needs to enable "Install from unknown sources" permission.
class AppUpdateNeedsPermission extends AppUpdateState {
  final AppUpdateInfo info;
  final String apkPath;
  const AppUpdateNeedsPermission(this.info, this.apkPath);
}

// ─────────────────────────────────────────────────────────
// STATE NOTIFIER
// ─────────────────────────────────────────────────────────

class AppUpdateStateNotifier extends StateNotifier<AppUpdateState> {
  AppUpdateStateNotifier() : super(const AppUpdateChecking());

  final _service = AppUpdateService.instance;

  /// Initialize: check for updates and determine starting state.
  Future<void> initialize() async {
    state = const AppUpdateChecking();
    debugPrint('🔄 AppUpdateProvider: Initializing...');

    // 1. Check if an update is available
    final updateInfo = await _service.checkForUpdate();

    if (updateInfo == null) {
      debugPrint('🔄 AppUpdateProvider: No update needed');
      state = const AppUpdateUpToDate();
      return;
    }

    debugPrint('🔄 AppUpdateProvider: Update available: ${updateInfo.version}');

    // 2. Check if we have a prior download for this version
    final persisted = await _service.getPersistedState(updateInfo.version);

    if (persisted == null) {
      debugPrint('🔄 AppUpdateProvider: No prior download → ReadyToDownload');
      state = AppUpdateReadyToDownload(updateInfo);
      return;
    }

    final downloadState = persisted['state'] as String;
    debugPrint('🔄 AppUpdateProvider: Found persisted state: $downloadState');

    if (downloadState == 'complete') {
      final path = persisted['path'] as String;
      debugPrint('🔄 AppUpdateProvider: APK ready at $path → ReadyToInstall');
      state = AppUpdateReadyToInstall(updateInfo, path);
    } else {
      state = AppUpdateReadyToResume(
        updateInfo,
        persisted['bytesDownloaded'] as int,
        persisted['totalBytes'] as int,
      );
    }
  }

  /// Start or resume downloading the APK.
  Future<void> startDownload() async {
    final info = _getUpdateInfo();
    if (info == null) return;

    debugPrint('🔄 AppUpdateProvider: Starting download for ${info.version}');
    state = AppUpdateDownloading(info, 0.0, 0, 0);

    try {
      final apkPath = await _service.downloadApk(
        downloadUrl: info.downloadUrl,
        targetVersion: info.version,
        onProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          state = AppUpdateDownloading(info, progress.clamp(0.0, 1.0), received, total);
        },
      );

      debugPrint('🔄 AppUpdateProvider: Download complete → $apkPath');
      state = AppUpdateReadyToInstall(info, apkPath);

      // Auto-trigger install after a brief delay for UI feedback
      await Future.delayed(const Duration(milliseconds: 500));
      await startInstall();
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        final persisted = await _service.getPersistedState(info.version);
        if (persisted != null) {
          state = AppUpdateReadyToResume(
            info,
            persisted['bytesDownloaded'] as int,
            persisted['totalBytes'] as int,
          );
        } else {
          state = AppUpdateReadyToDownload(info);
        }
        return;
      }

      String message = 'Download failed';
      if (e is DioException) {
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          message = 'Connection timed out. Check your internet and try again.';
        } else if (e.type == DioExceptionType.connectionError) {
          message = 'No internet connection. Please connect and try again.';
        } else {
          message = 'Download failed: ${e.message ?? 'Unknown error'}';
        }
      }
      debugPrint('🔄 AppUpdateProvider: Download error: $message');
      state = AppUpdateDownloadError(info, message);
    }
  }

  /// Trigger APK installation via platform channel.
  Future<void> startInstall() async {
    final currentState = state;
    String? apkPath;
    AppUpdateInfo? info;

    if (currentState is AppUpdateReadyToInstall) {
      apkPath = currentState.apkPath;
      info = currentState.info;
    } else if (currentState is AppUpdateNeedsPermission) {
      apkPath = currentState.apkPath;
      info = currentState.info;
    } else if (currentState is AppUpdateInstalling) {
      apkPath = currentState.apkPath;
      info = currentState.info;
    }

    if (apkPath == null || info == null) {
      debugPrint('🔄 AppUpdateProvider: startInstall called but no apkPath/info (state: ${state.runtimeType})');
      return;
    }

    debugPrint('🔄 AppUpdateProvider: Triggering install for $apkPath');
    state = AppUpdateInstalling(info, apkPath);

    try {
      final result = await _service.installApk(apkPath);
      debugPrint('🔄 AppUpdateProvider: Install result: $result');

      if (result == 'needs_permission') {
        debugPrint('🔄 AppUpdateProvider: Needs install permission → NeedsPermission');
        state = AppUpdateNeedsPermission(info, apkPath);
      }
      // If result == 'success', the Android installer is now open.
      // We stay in "Installing" state until onAppResumed() is called.
    } on PlatformException catch (e) {
      debugPrint('🔄 AppUpdateProvider: PlatformException: ${e.code} - ${e.message}');
      if (e.code == 'NEEDS_PERMISSION') {
        state = AppUpdateNeedsPermission(info, apkPath);
      } else {
        state = AppUpdateReadyToInstall(info, apkPath);
      }
    } catch (e) {
      debugPrint('🔄 AppUpdateProvider: Install error: $e');
      state = AppUpdateReadyToInstall(info, apkPath);
    }
  }

  /// Called when the app returns to foreground after install/settings intent.
  void onAppResumed() {
    final currentState = state;
    debugPrint('🔄 AppUpdateProvider: onAppResumed (state: ${currentState.runtimeType})');

    if (currentState is AppUpdateInstalling) {
      // We're still alive → install was cancelled by user
      // Show "Install Update" button again
      debugPrint('🔄 AppUpdateProvider: Install was cancelled → ReadyToInstall');
      state = AppUpdateReadyToInstall(currentState.info, currentState.apkPath);
    } else if (currentState is AppUpdateNeedsPermission) {
      // User came back from Settings — retry install
      debugPrint('🔄 AppUpdateProvider: Returned from Settings → retrying install');
      startInstall();
    }
  }

  /// Helper to extract AppUpdateInfo from current state.
  AppUpdateInfo? _getUpdateInfo() {
    final s = state;
    if (s is AppUpdateReadyToDownload) return s.info;
    if (s is AppUpdateReadyToResume) return s.info;
    if (s is AppUpdateReadyToInstall) return s.info;
    if (s is AppUpdateDownloading) return s.info;
    if (s is AppUpdateDownloadError) return s.info;
    if (s is AppUpdateInstalling) return s.info;
    if (s is AppUpdateNeedsPermission) return s.info;
    return null;
  }
}

// ─────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────

/// Main provider for the update state machine.
final appUpdateStateProvider =
    StateNotifierProvider<AppUpdateStateNotifier, AppUpdateState>(
  (ref) => AppUpdateStateNotifier(),
);
