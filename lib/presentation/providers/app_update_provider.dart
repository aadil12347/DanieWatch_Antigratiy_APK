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
  const AppUpdateInstalling(this.info);
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

    // 1. Check if an update is available
    final updateInfo = await _service.checkForUpdate();

    if (updateInfo == null) {
      state = const AppUpdateUpToDate();
      return;
    }

    // 2. Check if we have a prior download for this version
    final persisted = await _service.getPersistedState(updateInfo.version);

    if (persisted == null) {
      // No prior state — fresh download needed
      state = AppUpdateReadyToDownload(updateInfo);
      return;
    }

    final downloadState = persisted['state'] as String;

    if (downloadState == 'complete') {
      // APK fully downloaded — ready to install
      state = AppUpdateReadyToInstall(
        updateInfo,
        persisted['path'] as String,
      );
    } else {
      // Partial download — can resume
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

      // Download complete — transition to ready to install
      state = AppUpdateReadyToInstall(info, apkPath);

      // Auto-trigger install after a brief delay for UI feedback
      await Future.delayed(const Duration(milliseconds: 500));
      await startInstall();
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        // User cancelled — go back to resume state
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
    }

    if (apkPath == null || info == null) return;

    state = AppUpdateInstalling(info);

    try {
      final result = await _service.installApk(apkPath);

      if (result == 'needs_permission') {
        // User needs to enable "Install unknown apps" 
        state = AppUpdateNeedsPermission(info, apkPath);
      }
      // If result == 'success', the Android installer is now open.
      // The app lifecycle observer will handle what happens next.
      // We stay in "Installing" state until onAppResumed() is called.
    } on PlatformException catch (e) {
      if (e.code == 'NEEDS_PERMISSION') {
        state = AppUpdateNeedsPermission(info, apkPath);
      } else {
        state = AppUpdateReadyToInstall(info, apkPath);
      }
    } catch (e) {
      state = AppUpdateReadyToInstall(info, apkPath);
    }
  }

  /// Called when the app returns to foreground after install intent.
  /// If we're still alive, the install was cancelled by the user.
  void onAppResumed() {
    final currentState = state;
    if (currentState is AppUpdateInstalling) {
      // We're still alive → install was cancelled
      // Find the APK path from persisted state and transition to ReadyToInstall
      _restoreToReadyToInstall(currentState.info);
    } else if (currentState is AppUpdateNeedsPermission) {
      // User came back from Settings — retry install
      startInstall();
    }
  }

  Future<void> _restoreToReadyToInstall(AppUpdateInfo info) async {
    final persisted = await _service.getPersistedState(info.version);
    if (persisted != null && persisted['state'] == 'complete') {
      state = AppUpdateReadyToInstall(info, persisted['path'] as String);
    } else {
      // Shouldn't happen, but fallback
      state = AppUpdateReadyToDownload(info);
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
