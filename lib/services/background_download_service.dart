import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'hls_downloader_service.dart';
import 'download_notification_service.dart';

/// Manages background downloading using a Foreground Service.
/// This ensures the download continues even if the app is minimized.
class BackgroundDownloadService {
  static const String _commandStart = 'startDownload';
  static const String _commandPause = 'pauseDownload';
  static const String _commandResume = 'resumeDownload';
  static const String _commandCancel = 'cancelDownload';
  static const String _eventProgress = 'progress';
  static const String _eventComplete = 'complete';
  static const String _eventError = 'error';
  static const String _eventConversionStarted = 'conversionStarted';

  static final BackgroundDownloadService _instance =
      BackgroundDownloadService._internal();
  factory BackgroundDownloadService() => _instance;
  BackgroundDownloadService._internal();

  final Map<String, HlsDownloaderService> _activeDownloaders = {};

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
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'download_service_channel',
        initialNotificationTitle: 'DanieWatch Downloader',
        initialNotificationContent: 'Preparing download...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    if (service is AndroidServiceInstance) {
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
    final notifService = DownloadNotificationService();
    await notifService.init();

    // Listen for download commands
    service.on(_commandStart).listen((data) async {
      if (data == null) return;
      final String id = data['id'];
      final String videoUrl = data['videoUrl'];
      final String? audioUrl = data['audioUrl'];
      final String? subtitleUrl = data['subtitleUrl'];
      final String saveDir = data['saveDir'];
      final String outputMp4Path = data['outputMp4Path'];
      final String title = data['title'];

      if (downloaders.containsKey(id)) return;

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

        // Update foreground notification if this is the primary download
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
        service.invoke(_eventComplete, {'id': id, 'path': path});
        downloaders.remove(id);
        if (downloaders.isEmpty) {
          // service.stopSelf(); // Optional: keep alive if user wants to queue more
        }
      };

      downloader.onError = (error) {
        service.invoke(_eventError, {'id': id, 'error': error});
        downloaders.remove(id);
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
    if (!await service.isRunning()) {
      await service.startService();
    }
    
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
