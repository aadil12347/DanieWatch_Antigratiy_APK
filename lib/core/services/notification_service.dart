import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Top-level function to handle background messages (required by Firebase)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized before processing
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  debugPrint("Handling a background message: ${message.messageId}");
}

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

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
        ).timeout(const Duration(seconds: 5));
        debugPrint(
            'User granted permission: ${settings.authorizationStatus}');
      } catch (e) {
        debugPrint('⚠️ Permission request failed/timed out: $e');
      }

      // 4. Initialize Local Notifications
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/launcher_icon');

      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await _localNotifications.initialize(initializationSettings);

      // 5. Subscribe to default topic — DO NOT AWAIT (can hang on devices
      //    without Google Play Services). Fire-and-forget with error catch.
      _subscribeToTopicsSafely();

      // 6. Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        debugPrint('Message data: ${message.data}');

        if (message.notification != null) {
          debugPrint(
              'Message also contained a notification: ${message.notification}');
          _showLocalNotification(message);
        }
      });

      _initialized = true;
      debugPrint('✅ NotificationService initialized successfully');
    } catch (e, stackTrace) {
      // Don't crash the app if notifications fail to initialize
      debugPrint(
          '⚠️ NotificationService initialization failed (app will continue without notifications): $e');
      debugPrint('Stack trace: $stackTrace');
      _initialized = false;
    }
  }

  /// Subscribe to FCM topics in the background — never blocks app startup.
  void _subscribeToTopicsSafely() {
    if (_messaging == null) return;

    Future(() async {
      try {
        await _messaging!
            .subscribeToTopic('daniewatch_all')
            .timeout(const Duration(seconds: 10));
        debugPrint('✅ Subscribed to daniewatch_all topic');
      } catch (e) {
        debugPrint('⚠️ Topic subscription failed (non-fatal): $e');
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

  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            channelDescription:
                'This channel is used for important notifications.',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/launcher_icon',
          ),
        ),
      );
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
