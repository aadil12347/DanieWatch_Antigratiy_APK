import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'hls_downloader_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:echo_wifi_lock/echo_wifi_lock.dart';

// ── Event/command constants (top-level so both isolates can use them) ──
const String _commandStart = 'startDownload';
const String _commandPause = 'pauseDownload';
const String _commandResume = 'resumeDownload';
const String _commandCancel = 'cancelDownload';
const String _eventProgress = 'progress';
const String _eventComplete = 'complete';
const String _eventError = 'error';
const String _eventConversionStarted = 'conversionStarted';

// ── Notification action routing ──
const String _notifActionEvent = 'onNotifAction';

// ── SharedPreferences key (must match download_manager.dart) ──
const String _downloadsKey = 'download_items';

// ── Foreground service notification ID ──
const int _foregroundNotifId = 888;

// ── Download notification channel ──
const String _downloadChannelId = 'download_progress_channel';
const String _downloadChannelName = 'Download Progress';
const String _downloadChannelDesc = 'Shows per-download progress with action buttons';

// ══════════════════════════════════════════════════════════════
//  TOP-LEVEL ENTRY POINTS  (required for background isolate)
// ══════════════════════════════════════════════════════════════

/// Called when a notification action button is tapped.
/// This runs in a SEPARATE background isolate — NOT the service isolate.
/// We bridge the gap by using FlutterBackgroundService().invoke() which
/// sends an IPC message to the running service isolate.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final actionId = response.actionId;
  final payload = response.payload; // This is the download item ID
  if (actionId == null || payload == null) return;

  debugPrint('🔔 Notification action: $actionId for download $payload');

  // Forward the action to the background service isolate via IPC
  FlutterBackgroundService().invoke(_notifActionEvent, {
    'action': actionId,
    'id': payload,
  });
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  debugPrint('🟢 BackgroundService onStart() executing');

  if (service is AndroidServiceInstance) {
    // CRITICAL for Android 14+: Set as foreground service IMMEDIATELY
    // to avoid the 5-second crash window.
    service.setAsForegroundService();

    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  // ── Initialize flutter_local_notifications in the background isolate ──
  final notifPlugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
  const initSettings = InitializationSettings(android: androidInit);

  await notifPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (response) {
      // Foreground action tap inside this isolate — route the same way
      final actionId = response.actionId;
      final payload = response.payload;
      if (actionId != null && payload != null) {
        service.invoke(_notifActionEvent, {
          'action': actionId,
          'id': payload,
        });
      }
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  // Create the download progress notification channel
  const channel = AndroidNotificationChannel(
    _downloadChannelId,
    _downloadChannelName,
    description: _downloadChannelDesc,
    importance: Importance.low,
    showBadge: false,
  );

  await notifPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  debugPrint('🔔 Notification plugin initialized in background isolate');

  // ── State tracking ──
  final Map<String, HlsDownloaderService> downloaders = {};
  final Map<String, String> downloadTitles = {}; // id → display title
  final Map<String, bool> downloadPausedState = {}; // id → isPaused

  // Shared locks for background stability
  EchoWifiLock? wifiLock;
  try {
    wifiLock = EchoWifiLock();
  } catch (e) {
    debugPrint('⚠ WiFi lock init failed (non-fatal): $e');
  }

  // ── Helper: Generate unique notification ID from download item ID ──
  int notifIdForDownload(String itemId) {
    final ts = int.tryParse(itemId) ?? itemId.hashCode;
    return ts.abs() % 2147483647;
  }

  // ── Helper: Show/update per-download notification ──
  Future<void> showDownloadNotification({
    required String itemId,
    required String title,
    required int progressPct,
    required bool isPaused,
    String? speedText,
  }) async {
    final notifId = notifIdForDownload(itemId);

    // Build action buttons based on state
    final List<AndroidNotificationAction> actions = [];
    if (isPaused) {
      actions.add(const AndroidNotificationAction(
        'resume',
        '▶ Resume',
        showsUserInterface: false,
        cancelNotification: false,
      ));
    } else {
      actions.add(const AndroidNotificationAction(
        'pause',
        '⏸ Pause',
        showsUserInterface: false,
        cancelNotification: false,
      ));
    }
    actions.add(const AndroidNotificationAction(
      'cancel',
      '✕ Cancel',
      showsUserInterface: false,
      cancelNotification: false,
    ));

    final body = isPaused
        ? 'Paused — $progressPct%'
        : speedText != null && speedText.isNotEmpty
            ? '$progressPct% · $speedText'
            : '$progressPct%';

    final androidDetails = AndroidNotificationDetails(
      _downloadChannelId,
      _downloadChannelName,
      channelDescription: _downloadChannelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: 100,
      progress: progressPct,
      onlyAlertOnce: true,
      icon: '@mipmap/launcher_icon',
      subText: '$progressPct%',
      actions: actions,
    );

    await notifPlugin.show(
      notifId,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: itemId, // CRITICAL: payload = download ID for action routing
    );
  }

  // ── Helper: Show completion notification ──
  Future<void> showCompleteNotification(String itemId, String title) async {
    final notifId = notifIdForDownload(itemId);
    const androidDetails = AndroidNotificationDetails(
      _downloadChannelId,
      _downloadChannelName,
      channelDescription: _downloadChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      icon: '@mipmap/launcher_icon',
    );

    await notifPlugin.show(
      notifId,
      '✅ Download Completed',
      title,
      const NotificationDetails(android: androidDetails),
      payload: itemId,
    );
  }

  // ── Helper: Show failure notification ──
  Future<void> showFailedNotification(
      String itemId, String title, String error) async {
    final notifId = notifIdForDownload(itemId);
    const androidDetails = AndroidNotificationDetails(
      _downloadChannelId,
      _downloadChannelName,
      channelDescription: _downloadChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      icon: '@mipmap/launcher_icon',
    );

    await notifPlugin.show(
      notifId,
      '❌ Download Failed',
      '$title — $error',
      const NotificationDetails(android: androidDetails),
      payload: itemId,
    );
  }

  // ── Helper: Cancel per-download notification ──
  Future<void> cancelDownloadNotification(String itemId) async {
    await notifPlugin.cancel(notifIdForDownload(itemId));
  }

  // ── Helper: Update the foreground service summary notification ──
  void updateSummaryNotification() {
    if (service is AndroidServiceInstance) {
      final activeCount = downloaders.length;
      if (activeCount == 0) {
        service.setForegroundNotificationInfo(
          title: 'DanieWatch',
          content: 'All downloads complete',
        );
      } else if (activeCount == 1) {
        final title = downloadTitles.values.first;
        service.setForegroundNotificationInfo(
          title: 'DanieWatch Downloading . . .',
          content: title,
        );
      } else {
        service.setForegroundNotificationInfo(
          title: 'DanieWatch Downloading . . .',
          content: '$activeCount downloads in progress',
        );
      }
    }
  }

  // ── Helper: Format speed for notification ──
  String formatSpeed(int bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  // ── Helper: Update SharedPreferences from background isolate ──
  Future<void> updateDownloadStatusInPrefs(
    String id, {
    required int statusIndex,
    double? progress,
    String? localPath,
    String? error,
    String? completedAt,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // Ensure we have the latest data
      final data = prefs.getString(_downloadsKey);
      if (data == null) return;

      final List<dynamic> jsonList = jsonDecode(data);
      for (int i = 0; i < jsonList.length; i++) {
        if (jsonList[i]['id'] == id) {
          jsonList[i]['status'] = statusIndex;
          if (progress != null) jsonList[i]['progress'] = progress;
          if (localPath != null) jsonList[i]['localPath'] = localPath;
          if (error != null) jsonList[i]['error'] = error;
          if (completedAt != null) jsonList[i]['completedAt'] = completedAt;
          break;
        }
      }

      await prefs.setString(_downloadsKey, jsonEncode(jsonList));
      debugPrint('💾 Background isolate updated prefs for $id → status=$statusIndex');
    } catch (e) {
      debugPrint('⚠ Failed to update prefs from background: $e');
    }
  }

  // ── Helper: Move temp file to public Downloads ──
  Future<String?> moveToPublicDownloads(
      String tempPath, String fileName) async {
    try {
      final safeFileName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final finalPath = '/storage/emulated/0/Download/$safeFileName';

      final tempFile = File(tempPath);
      if (!await tempFile.exists()) {
        debugPrint('⚠ Temp file not found: $tempPath');
        return null;
      }

      await tempFile.copy(finalPath);

      final destFile = File(finalPath);
      if (!await destFile.exists()) {
        debugPrint('⚠ Copy to Downloads failed');
        return null;
      }

      // Clean up temp file
      try {
        await tempFile.delete();
      } catch (_) {}

      debugPrint('📂 Moved to: $finalPath');
      return finalPath;
    } catch (e) {
      debugPrint('❌ File move error: $e');
      return null;
    }
  }

  // Update notification to show service is ready
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'DanieWatch Downloading . . .',
      content: 'Preparing download...',
    );
  }

  // Signal to the UI isolate that listeners are registered
  service.invoke('serviceReady', {});
  debugPrint('🟢 BackgroundService listeners registered, sent serviceReady');

  // ── Handle notification action events (from the notification callback isolate) ──
  service.on(_notifActionEvent).listen((data) {
    if (data == null) return;
    final action = data['action'] as String?;
    final id = data['id'] as String?;
    if (action == null || id == null) return;

    debugPrint('🔔 Processing notification action: $action for $id');

    switch (action) {
      case 'pause':
        downloaders[id]?.pause();
        downloadPausedState[id] = true;
        // Update the notification to show paused state
        final title = downloadTitles[id] ?? 'Download';
        showDownloadNotification(
          itemId: id,
          title: title,
          progressPct: 0, // Will be updated on next progress tick
          isPaused: true,
        );
        // Notify UI isolate
        service.invoke('notifPause', {'id': id});
        break;

      case 'resume':
        downloaders[id]?.resume();
        downloadPausedState[id] = false;
        // Notify UI isolate
        service.invoke('notifResume', {'id': id});
        break;

      case 'cancel':
        downloaders[id]?.cancel();
        downloaders.remove(id);
        downloadTitles.remove(id);
        downloadPausedState.remove(id);
        cancelDownloadNotification(id);
        updateSummaryNotification();
        // Notify UI isolate
        service.invoke('notifCancel', {'id': id});
        // Stop service if idle
        if (downloaders.isEmpty) {
          WakelockPlus.disable().catchError((_) {});
          wifiLock?.release();
          Future.delayed(const Duration(seconds: 1), () {
            if (downloaders.isEmpty) {
              debugPrint('🛑 All downloads cancelled — stopping service');
              service.stopSelf();
            }
          });
        }
        break;
    }
  });

  // ── Listen for download commands ───────────────────────────
  service.on(_commandStart).listen((data) async {
    if (data == null) return;
    final String id = data['id'];
    final String videoUrl = data['videoUrl'];
    final String? audioUrl = data['audioUrl'];
    final String? subtitleUrl = data['subtitleUrl'];
    final String saveDir = data['saveDir'];
    final String outputMp4Path = data['outputMp4Path'];
    final String title = data['title'];
    final String? fileName = data['fileName'];

    debugPrint('🟢 Received download command for "$title" (id=$id)');

    if (downloaders.containsKey(id)) {
      debugPrint('⚠ Download $id already in progress, skipping');
      return;
    }

    // Enable locks for background stability
    try {
      WakelockPlus.enable();
      await wifiLock?.acquire(EchoWifiMode.wifiModeFullHighPerf);
    } catch (e) {
      debugPrint('⚠ Lock acquire failed (non-fatal): $e');
    }

    final downloader = HlsDownloaderService();
    downloaders[id] = downloader;
    downloadTitles[id] = title;
    downloadPausedState[id] = false;

    // Show initial per-download notification
    await showDownloadNotification(
      itemId: id,
      title: title,
      progressPct: 0,
      isPaused: false,
    );
    updateSummaryNotification();

    // Throttle notification updates (max once per second)
    int lastNotifUpdate = 0;

    downloader.onProgress = (progress, completed, total, bytes, speed) {
      // Always send progress to UI isolate
      service.invoke(_eventProgress, {
        'id': id,
        'progress': progress,
        'completed': completed,
        'total': total,
        'bytes': bytes,
        'speed': speed,
      });

      // Throttle notification updates to max 1/sec
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastNotifUpdate >= 1000) {
        lastNotifUpdate = now;
        final pct = (progress * 100).toInt().clamp(0, 100);
        final isPaused = downloadPausedState[id] ?? false;
        showDownloadNotification(
          itemId: id,
          title: title,
          progressPct: pct,
          isPaused: isPaused,
          speedText: formatSpeed(speed),
        );

        // Update summary
        updateSummaryNotification();
      }
    };

    downloader.onConversionStarted = () {
      service.invoke(_eventConversionStarted, {'id': id});

      // Update notification to show conversion
      showDownloadNotification(
        itemId: id,
        title: '$title — Converting…',
        progressPct: 97,
        isPaused: false,
      );
    };

    downloader.onComplete = (path) async {
      debugPrint('✅ Download complete for $id: $path');

      // Move file to public Downloads
      final resolvedFileName = fileName ?? '$title.mp4';
      final publicPath = await moveToPublicDownloads(path, resolvedFileName);

      // Clean up segment directory
      try {
        final segDir = Directory(saveDir);
        if (await segDir.exists()) await segDir.delete(recursive: true);
      } catch (e) {
        debugPrint('⚠ Segment cleanup: $e');
      }

      // Update SharedPreferences from background isolate
      // Status index: completed = 3 (matching DownloadStatus.completed)
      await updateDownloadStatusInPrefs(
        id,
        statusIndex: 3, // DownloadStatus.completed
        progress: 1.0,
        localPath: publicPath ?? path,
        completedAt: DateTime.now().toIso8601String(),
      );

      // Show completion notification (replaces progress notification)
      await showCompleteNotification(id, title);

      // Notify UI isolate
      service.invoke(_eventComplete, {
        'id': id,
        'path': publicPath ?? path,
        'finalizedInBackground': true,
      });

      downloaders.remove(id);
      downloadTitles.remove(id);
      downloadPausedState.remove(id);
      updateSummaryNotification();

      if (downloaders.isEmpty) {
        WakelockPlus.disable().catchError((_) {});
        wifiLock?.release();
        Future.delayed(const Duration(seconds: 2), () {
          if (downloaders.isEmpty) {
            debugPrint('🛑 All downloads done — stopping service');
            service.stopSelf();
          }
        });
      }
    };

    downloader.onError = (error) async {
      debugPrint('❌ Download error for $id: $error');

      // Update SharedPreferences from background isolate
      // Status index: failed = 4 (matching DownloadStatus.failed)
      await updateDownloadStatusInPrefs(
        id,
        statusIndex: 4, // DownloadStatus.failed
        error: error,
      );

      // Show failure notification
      await showFailedNotification(id, title, error);

      // Notify UI isolate
      service.invoke(_eventError, {'id': id, 'error': error});

      downloaders.remove(id);
      downloadTitles.remove(id);
      downloadPausedState.remove(id);
      updateSummaryNotification();

      if (downloaders.isEmpty) {
        WakelockPlus.disable().catchError((_) {});
        wifiLock?.release();
        Future.delayed(const Duration(seconds: 2), () {
          if (downloaders.isEmpty) {
            debugPrint(
                '🛑 All downloads done (after error) — stopping service');
            service.stopSelf();
          }
        });
      }
    };

    try {
      await downloader.startDownload(
        videoM3u8Url: videoUrl,
        audioM3u8Url: audioUrl,
        subtitleM3u8Url: subtitleUrl,
        saveDirectory: saveDir,
        outputMp4Path: outputMp4Path,
      );
    } catch (e) {
      debugPrint('❌ Download threw exception for $id: $e');
      service.invoke(_eventError, {'id': id, 'error': e.toString()});
      await showFailedNotification(id, title, e.toString());
      downloaders.remove(id);
      downloadTitles.remove(id);
      downloadPausedState.remove(id);
    }
  });

  service.on(_commandPause).listen((data) {
    final id = data?['id'];
    if (id == null) return;
    downloaders[id]?.pause();
    downloadPausedState[id] = true;

    // Update per-download notification to show paused state
    final title = downloadTitles[id] ?? 'Download';
    showDownloadNotification(
      itemId: id,
      title: title,
      progressPct: 0, // approximate — will update on next tick
      isPaused: true,
    );

    // Update summary
    if (service is AndroidServiceInstance) {
      final pausedCount =
          downloadPausedState.values.where((v) => v).length;
      final activeCount = downloaders.length;
      if (pausedCount == activeCount) {
        service.setForegroundNotificationInfo(
          title: 'DanieWatch',
          content: 'All downloads paused',
        );
      } else {
        service.setForegroundNotificationInfo(
          title: 'DanieWatch Downloading . . .',
          content:
              '${activeCount - pausedCount} downloading, $pausedCount paused',
        );
      }
    }
  });

  service.on(_commandResume).listen((data) {
    final id = data?['id'];
    if (id == null) return;
    downloaders[id]?.resume();
    downloadPausedState[id] = false;

    // Update per-download notification
    final title = downloadTitles[id] ?? 'Download';
    showDownloadNotification(
      itemId: id,
      title: title,
      progressPct: 0,
      isPaused: false,
    );

    updateSummaryNotification();
  });

  service.on(_commandCancel).listen((data) {
    final id = data?['id'];
    if (id == null) return;
    downloaders[id]?.cancel();
    downloaders.remove(id);
    downloadTitles.remove(id);
    downloadPausedState.remove(id);
    cancelDownloadNotification(id);
    updateSummaryNotification();

    if (downloaders.isEmpty) {
      WakelockPlus.disable().catchError((_) {});
      wifiLock?.release();
      Future.delayed(const Duration(seconds: 1), () {
        if (downloaders.isEmpty) {
          debugPrint('🛑 All downloads cancelled — stopping service');
          service.stopSelf();
        }
      });
    }
  });

  // Allow UI isolate to request service stop
  service.on('stopService').listen((_) {
    // Cancel all active downloads first
    for (final entry in downloaders.entries.toList()) {
      entry.value.cancel();
      cancelDownloadNotification(entry.key);
    }
    downloaders.clear();
    downloadTitles.clear();
    downloadPausedState.clear();
    WakelockPlus.disable().catchError((_) {});
    wifiLock?.release();
    service.stopSelf();
  });
}

// ══════════════════════════════════════════════════════════════
//  BackgroundDownloadService  (UI isolate API)
// ══════════════════════════════════════════════════════════════

class BackgroundDownloadService {
  static final BackgroundDownloadService _instance =
      BackgroundDownloadService._internal();
  factory BackgroundDownloadService() => _instance;
  BackgroundDownloadService._internal();

  Future<void> initialize() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'download_service_channel',
      'Download Service',
      description: 'Keeps downloads running in the background',
      importance: Importance.min,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'download_service_channel',
        initialNotificationTitle: 'DanieWatch Downloading . . .',
        initialNotificationContent: 'Preparing download...',
        foregroundServiceNotificationId: _foregroundNotifId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  // ── UI Isolate Methods ─────────────────────────────────

  Future<void> startDownload({
    required String id,
    required String title,
    required String videoUrl,
    String? audioUrl,
    String? subtitleUrl,
    required String saveDir,
    required String outputMp4Path,
    String? fileName,
  }) async {
    final service = FlutterBackgroundService();
    final wasRunning = await service.isRunning();

    if (!wasRunning) {
      await service.startService();

      // Wait for the background isolate to fully spin up and register its
      // listeners. We listen for 'serviceReady' with a timeout fallback.
      debugPrint('⏳ Waiting for background service to be ready...');
      final readyCompleter = Completer<void>();
      StreamSubscription? readySub;
      readySub = service.on('serviceReady').listen((_) {
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete();
        }
        readySub?.cancel();
      });

      // Wait for ready signal OR timeout after 6 seconds
      await readyCompleter.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () {
          debugPrint('⚠ serviceReady timeout — sending command anyway');
          readySub?.cancel();
        },
      );
      debugPrint('✅ Background service is ready');
    }

    debugPrint('📤 Invoking startDownload command for $id');
    service.invoke(_commandStart, {
      'id': id,
      'title': title,
      'videoUrl': videoUrl,
      'audioUrl': audioUrl,
      'subtitleUrl': subtitleUrl,
      'saveDir': saveDir,
      'outputMp4Path': outputMp4Path,
      'fileName': fileName,
    });
  }

  void pauseDownload(String id) {
    FlutterBackgroundService().invoke(_commandPause, {'id': id});
  }

  void resumeDownload(String id) {
    FlutterBackgroundService().invoke(_commandResume, {'id': id});
  }

  void cancelDownload(String id) {
    FlutterBackgroundService().invoke(_commandCancel, {'id': id});
  }
}
