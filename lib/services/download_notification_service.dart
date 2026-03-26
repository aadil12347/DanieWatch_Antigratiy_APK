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

  /// Callback for notification action buttons
  /// actionId: 'pause', 'resume', or 'cancel'
  /// notificationId: the id of the notification
  Function(String actionId, int notificationId)? onNotificationAction;

  Future<void> init() async {
    if (_initialized || kIsWeb || !Platform.isAndroid) return;

    const android = AndroidInitializationSettings('@mipmap/launcher_icon');
    const settings = InitializationSettings(android: android);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

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

  void _handleNotificationResponse(NotificationResponse response) {
    final actionId = response.actionId;
    final notifId = response.id;
    if (actionId != null && notifId != null) {
      onNotificationAction?.call(actionId, notifId);
    }
  }

  /// Show / update a progress notification with Pause/Cancel actions
  Future<void> showProgress({
    required int id,
    required String title,
    required int progress, // 0 – 100
    String? body,
    bool isPaused = false,
  }) async {
    if (!_initialized) return;

    final actions = <AndroidNotificationAction>[
      AndroidNotificationAction(
        isPaused ? 'resume' : 'pause',
        isPaused ? 'Resume' : 'Pause',
        showsUserInterface: false,
      ),
      const AndroidNotificationAction(
        'cancel',
        'Cancel',
        showsUserInterface: false,
      ),
    ];

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
      actions: actions,
    );

    await _plugin.show(
      id,
      title,
      body ?? '$progress%',
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
