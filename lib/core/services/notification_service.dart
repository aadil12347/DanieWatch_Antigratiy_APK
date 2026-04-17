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
  // Background messages with a 'notification' payload are shown automatically
  // by the system. We only need to handle data-only messages here if needed.
}

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

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

      // 5. Initialize Local Notifications
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/launcher_icon');

      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await _localNotifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('Notification tapped: ${response.payload}');
        },
      );

      // 6. Set foreground notification presentation options
      await _messaging!.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 7. Subscribe to default topic — DO NOT AWAIT (can hang on devices
      //    without Google Play Services). Fire-and-forget with error catch.
      _subscribeToTopicsSafely();

      // 8. Handle foreground messages — show as local notification
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        debugPrint('Message data: ${message.data}');

        if (message.notification != null) {
          debugPrint(
              'Message also contained a notification: ${message.notification}');
          _showLocalNotification(message);
        }
      });

      // 9. Handle notification taps when app is in background (not killed)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('Notification opened app: ${message.messageId}');
      });

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

  /// Show a local notification for foreground FCM messages
  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;

    if (notification != null) {
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
          ),
        ),
        payload: message.data.toString(),
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
