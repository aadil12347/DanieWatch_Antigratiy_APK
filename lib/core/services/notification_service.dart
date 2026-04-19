import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import '../../data/local/notification_storage.dart';
import '../../domain/models/local_notification.dart';
import '../router/app_router.dart';

/// Top-level function to handle background messages (required by Firebase)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized before processing
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  debugPrint("Handling a background message: ${message.messageId}");
  // Save to local storage for the inbox
  _saveMessageToLocalStorage(message);
}

/// Helper to save FCM message to local notification storage
Future<void> _saveMessageToLocalStorage(RemoteMessage message) async {
  try {
    final notification = LocalNotification(
      id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type: message.data['type'] ?? 'admin_message',
      title: message.notification?.title ?? message.data['title'] ?? '',
      body: message.notification?.body ?? message.data['body'] ?? '',
      data: Map<String, dynamic>.from(message.data),
      createdAt: DateTime.now(),
      isRead: false,
    );
    await NotificationStorage.instance.addNotification(notification);
  } catch (e) {
    debugPrint('⚠️ Failed to save notification to local storage: $e');
  }
}

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Pending deep link data from notification tap (set before app navigates)
  Map<String, dynamic>? pendingNotificationPayload;

  /// Stream controller for foreground notifications (instant in-app updates)
  final _foregroundNotificationController = StreamController<LocalNotification>.broadcast();
  Stream<LocalNotification> get foregroundNotificationStream => _foregroundNotificationController.stream;

  /// TMDB ID to highlight when opening the notifications page from a tap
  String? highlightTmdbId;

  /// The Android notification channel used for all notifications
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  /// Initialize Firebase + FCM + Local Notifications.
  /// This method is designed to NEVER hang or crash — the app will still work
  /// without notifications if Firebase/GMS is misconfigured.
  Future<void> initialize() async {
    try {
      // 1. Initialize Firebase (with timeout to prevent hang)
      await Firebase.initializeApp().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⚠️ Firebase.initializeApp() timed out');
          throw Exception('Firebase init timeout');
        },
      );
      _messaging = FirebaseMessaging.instance;

      // 2. Set background handler
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      // 3. Request permissions (with timeout)
      try {
        final settings = await _messaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        ).timeout(const Duration(seconds: 5));
        debugPrint(
            'User granted permission: ${settings.authorizationStatus}');
      } catch (e) {
        debugPrint('⚠️ Permission request failed/timed out: $e');
      }

      // 4. Create the notification channel FIRST (critical for Android 8+)
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(_channel);
        debugPrint('✅ Notification channel created: ${_channel.id}');
      }

      // 5. Initialize Local Notifications with deep link tap handler
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/launcher_icon');

      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await _localNotifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // 6. Set foreground notification presentation options
      await _messaging!.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 6.5. Check if app was launched by tapping a LOCAL notification (cold start)
      try {
        final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
        if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
          final payload = launchDetails.notificationResponse?.payload;
          if (payload != null && payload.isNotEmpty) {
            Map<String, dynamic>? data;
            try {
              data = Map<String, dynamic>.from(json.decode(payload));
            } catch (_) {
              data = _parseDartMapString(payload);
            }
            if (data != null) {
              final tmdbId = data['tmdb_id']?.toString();
              highlightTmdbId = tmdbId;
              pendingNotificationPayload = {
                'navigate_to': 'notifications',
                'highlight_tmdb_id': tmdbId,
              };
              debugPrint('📱 App launched from local notification tap (cold start), tmdbId=$tmdbId');
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ getNotificationAppLaunchDetails failed: $e');
      }

      // 7. Subscribe to default topic — DO NOT AWAIT (can hang on devices
      //    without Google Play Services). Fire-and-forget with error catch.
      _subscribeToTopicsSafely();

      // 8. Handle foreground messages — show as local notification + save to inbox
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        debugPrint('Message data: ${message.data}');

        // Save to local storage for the notification inbox
        _saveMessageToLocalStorage(message);

        // Broadcast to in-app listeners for instant UI update (no app restart needed)
        try {
          final localNotif = LocalNotification(
            id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
            type: message.data['type'] ?? 'admin_message',
            title: message.notification?.title ?? message.data['title'] ?? '',
            body: message.notification?.body ?? message.data['body'] ?? '',
            data: Map<String, dynamic>.from(message.data),
            createdAt: DateTime.now(),
            isRead: false,
          );
          _foregroundNotificationController.add(localNotif);
          debugPrint('📱 Broadcasted foreground notification to in-app listeners');
        } catch (e) {
          debugPrint('⚠️ Failed to broadcast foreground notification: $e');
        }

        if (message.notification != null) {
          debugPrint(
              'Message also contained a notification: ${message.notification}');
          _showLocalNotification(message);
        }
      });

      // 9. Handle notification taps when app is in background (not killed)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('Notification opened app from background: ${message.messageId}');
        final tmdbId = message.data['tmdb_id']?.toString();
        highlightTmdbId = tmdbId;
        // Navigate to notifications page after a brief delay (app coming from background)
        Future.delayed(const Duration(milliseconds: 500), () {
          try {
            final ctx = AppRouter.rootNavKey.currentContext;
            if (ctx != null) {
              GoRouter.of(ctx).go('/notifications');
              debugPrint('📱 Navigated to /notifications from background tap');
            }
          } catch (e) {
            debugPrint('⚠️ Background tap navigation failed: $e');
          }
        });
      });

      // 10. Check if app was opened from a terminated state by notification
      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('App opened from terminated by notification: ${initialMessage.messageId}');
        final tmdbId = initialMessage.data['tmdb_id']?.toString();
        highlightTmdbId = tmdbId;
        pendingNotificationPayload = {
          'navigate_to': 'notifications',
          'highlight_tmdb_id': tmdbId,
        };
      }

      _initialized = true;
      debugPrint('✅ NotificationService initialized successfully');

      // Log the FCM token for debugging
      try {
        final token = await _messaging!
            .getToken()
            .timeout(const Duration(seconds: 10));
        debugPrint('📱 FCM Token: $token');
      } catch (e) {
        debugPrint('⚠️ Could not get FCM token: $e');
      }
    } catch (e, stackTrace) {
      // Don't crash the app if notifications fail to initialize
      debugPrint(
          '⚠️ NotificationService initialization failed (app will continue without notifications): $e');
      debugPrint('Stack trace: $stackTrace');
      _initialized = false;
    }
  }

  /// Handle notification tap from local notifications plugin
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    if (response.payload != null && response.payload!.isNotEmpty) {
      try {
        // Parse the payload to extract navigation data
        final payloadStr = response.payload!;
        Map<String, dynamic>? data;
        
        // Try JSON parse first
        try {
          data = Map<String, dynamic>.from(json.decode(payloadStr));
        } catch (_) {
          // Fallback: parse the Dart map toString format
          data = _parseDartMapString(payloadStr);
        }

        if (data != null) {
          // Set highlight data for the notifications page
          highlightTmdbId = data['tmdb_id']?.toString();

          // Navigate to notifications page (bell icon) immediately
          try {
            final ctx = AppRouter.rootNavKey.currentContext;
            if (ctx != null) {
              GoRouter.of(ctx).go('/notifications');
              debugPrint('📱 Navigated to /notifications from notification tap');
            } else {
              // Cold start: context not available yet, set pending payload
              // so splash screen will navigate after initialization
              pendingNotificationPayload = {
                'navigate_to': 'notifications',
                'highlight_tmdb_id': data['tmdb_id']?.toString(),
              };
              debugPrint('📱 Set pending notification payload (cold start, no context yet)');
            }
          } catch (e) {
            debugPrint('⚠️ Notification tap navigation failed: $e');
            // Fallback: set pending payload
            pendingNotificationPayload = {
              'navigate_to': 'notifications',
              'highlight_tmdb_id': data['tmdb_id']?.toString(),
            };
          }
        }
      } catch (e) {
        debugPrint('⚠️ Failed to parse notification payload: $e');
      }
    }
  }

  /// Parse a Dart Map.toString() format like {key: value, key2: value2}
  Map<String, dynamic>? _parseDartMapString(String str) {
    try {
      // Remove outer braces
      var s = str.trim();
      if (s.startsWith('{') && s.endsWith('}')) {
        s = s.substring(1, s.length - 1);
      }
      final map = <String, dynamic>{};
      final parts = s.split(', ');
      for (final part in parts) {
        final idx = part.indexOf(': ');
        if (idx > 0) {
          final key = part.substring(0, idx).trim();
          final value = part.substring(idx + 2).trim();
          map[key] = value;
        }
      }
      return map.isNotEmpty ? map : null;
    } catch (_) {
      return null;
    }
  }



  /// Check and consume pending notification payload
  Map<String, dynamic>? consumePendingPayload() {
    final payload = pendingNotificationPayload;
    pendingNotificationPayload = null;
    return payload;
  }

  /// Subscribe to FCM topics in the background — never blocks app startup.
  /// Subscribes to ALL category topics so push notifications are always received.
  void _subscribeToTopicsSafely() {
    if (_messaging == null) return;

    const topics = [
      'daniewatch_all',
      'daniewatch_newly_added',
      'daniewatch_recently_released',
      'daniewatch_admin_messages',
    ];

    Future(() async {
      for (final topic in topics) {
        try {
          await _messaging!
              .subscribeToTopic(topic)
              .timeout(const Duration(seconds: 10));
          debugPrint('✅ Subscribed to $topic topic');
        } catch (e) {
          debugPrint('⚠️ Topic subscription for $topic failed (non-fatal): $e');
        }
      }
    });
  }

  /// Subscribe to a specific notification topic
  Future<void> subscribeToTopic(String topic) async {
    if (!_initialized || _messaging == null) return;
    try {
      await _messaging!
          .subscribeToTopic(topic)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('⚠️ Subscribe to $topic failed: $e');
    }
  }

  /// Unsubscribe from a specific notification topic
  Future<void> unsubscribeFromTopic(String topic) async {
    if (!_initialized || _messaging == null) return;
    try {
      await _messaging!
          .unsubscribeFromTopic(topic)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('⚠️ Unsubscribe from $topic failed: $e');
    }
  }

  /// Show a local notification for foreground FCM messages
  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;

    if (notification != null) {
      BigPictureStyleInformation? bigPictureStyleInformation;

      if (message.data['type'] == 'newly_added') {
        final posterUrl = message.data['poster_url'];
        if (posterUrl != null && posterUrl.toString().isNotEmpty) {
          try {
            final response = await http.get(Uri.parse(posterUrl));
            if (response.statusCode == 200) {
              final directory = await getTemporaryDirectory();
              final filePath = '${directory.path}/notification_image_${message.messageId ?? DateTime.now().millisecondsSinceEpoch}.jpg';
              final file = File(filePath);
              await file.writeAsBytes(response.bodyBytes);

              bigPictureStyleInformation = BigPictureStyleInformation(
                FilePathAndroidBitmap(filePath),
                contentTitle: notification.title,
                summaryText: notification.body,
                hideExpandedLargeIcon: false,
              );
            }
          } catch (e) {
            debugPrint('Error downloading notification image: $e');
          }
        }
      }

      // Encode data as JSON payload for deep link on tap
      final payloadJson = json.encode(message.data);

      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/launcher_icon',
            playSound: true,
            enableVibration: true,
            showWhen: true,
            styleInformation: bigPictureStyleInformation,
          ),
        ),
        payload: payloadJson,
      );
      debugPrint('✅ Local notification shown: ${notification.title}');
    }
  }

  Future<String?> getToken() async {
    if (!_initialized || _messaging == null) return null;
    try {
      return await _messaging!
          .getToken()
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  bool get isInitialized => _initialized;
}
