// lib/services/download_notification_service.dart
// ─────────────────────────────────────────────────────────
// Shows download progress / completion / failure
// in the Android notification bar (like Chrome downloads).
// ─────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class DownloadNotificationService {
  static final DownloadNotificationService _instance =
      DownloadNotificationService._internal();
  factory DownloadNotificationService() => _instance;
  DownloadNotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized || kIsWeb || !Platform.isAndroid) return;

    const android = AndroidInitializationSettings('@mipmap/launcher_icon');
    const settings = InitializationSettings(android: android);

    await _plugin.initialize(settings);

    // Create notification channel
    const channel = AndroidNotificationChannel(
      'download_channel',
      'Downloads',
      description: 'Shows download progress',
      importance: Importance.low,
      showBadge: false,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// Show / update a progress notification
  Future<void> showProgress({
    required int id,
    required String title,
    required int progress, // 0 – 100
    String? body,
  }) async {
    if (!_initialized) return;

    final androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Shows download progress',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      onlyAlertOnce: true,
      icon: '@mipmap/launcher_icon',
      subText: '$progress%',
    );

    await _plugin.show(
      id,
      title,
      body ?? 'Downloading… $progress%',
      NotificationDetails(android: androidDetails),
    );
  }

  /// Show a "completed" notification
  Future<void> showComplete({
    required int id,
    required String title,
  }) async {
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Shows download progress',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      icon: '@mipmap/launcher_icon',
    );

    await _plugin.show(
      id,
      '✅ $title',
      'Download complete',
      const NotificationDetails(android: androidDetails),
    );
  }

  /// Show a "failed" notification
  Future<void> showFailed({
    required int id,
    required String title,
    String? error,
  }) async {
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Shows download progress',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      icon: '@mipmap/launcher_icon',
    );

    await _plugin.show(
      id,
      '❌ $title',
      error ?? 'Download failed',
      const NotificationDetails(android: androidDetails),
    );
  }

  /// Cancel / dismiss notification
  Future<void> cancel(int id) async {
    if (!_initialized) return;
    await _plugin.cancel(id);
  }
}
