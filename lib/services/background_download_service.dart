import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

// ══════════════════════════════════════════════════════════════
//  TOP-LEVEL ENTRY POINTS  (required for background isolate)
// ══════════════════════════════════════════════════════════════

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

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  final Map<String, HlsDownloaderService> downloaders = {};

  // Shared locks for background stability
  EchoWifiLock? wifiLock;
  try {
    wifiLock = EchoWifiLock();
  } catch (e) {
    debugPrint('⚠ WiFi lock init failed (non-fatal): $e');
  }

  // Update notification to show service is ready
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'DanieWatch Downloader',
      content: 'Ready to download.',
    );
  }

  // Signal to the UI isolate that listeners are registered
  service.invoke('serviceReady', {});
  debugPrint('🟢 BackgroundService listeners registered, sent serviceReady');

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

    downloader.onProgress = (progress, completed, total, bytes, speed) {
      service.invoke(_eventProgress, {
        'id': id,
        'progress': progress,
        'completed': completed,
        'total': total,
        'bytes': bytes,
        'speed': speed,
      });

      // Update foreground notification
      if (service is AndroidServiceInstance) {
        final pct = (progress * 100).toInt();
        service.setForegroundNotificationInfo(
          title: 'Downloading $title',
          content: '$pct% completed',
        );
      }
    };

    downloader.onConversionStarted = () {
      service.invoke(_eventConversionStarted, {'id': id});
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Finalizing $title',
          content: 'Muxing segments...',
        );
      }
    };

    downloader.onComplete = (path) {
      debugPrint('✅ Download complete for $id: $path');
      service.invoke(_eventComplete, {'id': id, 'path': path});
      downloaders.remove(id);
      if (downloaders.isEmpty) {
        try {
          WakelockPlus.disable();
          wifiLock?.release();
        } catch (_) {}
        // Stop the foreground service after a brief delay so the
        // "Muxing segments" notification is dismissed cleanly.
        Future.delayed(const Duration(seconds: 2), () {
          if (downloaders.isEmpty) {
            debugPrint('🛑 All downloads done — stopping service');
            service.stopSelf();
          }
        });
      }
    };

    downloader.onError = (error) {
      debugPrint('❌ Download error for $id: $error');
      service.invoke(_eventError, {'id': id, 'error': error});
      downloaders.remove(id);
      if (downloaders.isEmpty) {
        try {
          WakelockPlus.disable();
          wifiLock?.release();
        } catch (_) {}
        Future.delayed(const Duration(seconds: 2), () {
          if (downloaders.isEmpty) {
            debugPrint('🛑 All downloads done (after error) — stopping service');
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
      downloaders.remove(id);
    }
  });

  service.on(_commandPause).listen((data) {
    final id = data?['id'];
    downloaders[id]?.pause();
  });

  service.on(_commandResume).listen((data) {
    final id = data?['id'];
    downloaders[id]?.resume();
  });

  service.on(_commandCancel).listen((data) {
    final id = data?['id'];
    downloaders[id]?.cancel();
    downloaders.remove(id);
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
      importance: Importance.low,
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
        initialNotificationTitle: 'DanieWatch Downloader',
        initialNotificationContent: 'Preparing download...',
        foregroundServiceNotificationId: 888,
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
