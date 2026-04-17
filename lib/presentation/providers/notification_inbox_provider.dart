import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/notification_storage.dart';
import '../../domain/models/local_notification.dart';

/// Manages local notification inbox state
class NotificationInboxNotifier extends StateNotifier<List<LocalNotification>> {
  NotificationInboxNotifier() : super([]) {
    loadNotifications();
  }

  /// Load notifications from local storage
  Future<void> loadNotifications() async {
    final notifications = await NotificationStorage.instance.loadNotifications();
    if (mounted) {
      state = notifications;
    }
  }

  /// Add a new notification and refresh state
  Future<void> addNotification(LocalNotification notification) async {
    await NotificationStorage.instance.addNotification(notification);
    await loadNotifications();
  }

  /// Mark a specific notification as read
  Future<void> markAsRead(String id) async {
    await NotificationStorage.instance.markAsRead(id);
    // Optimistic update
    state = state.map((n) {
      if (n.id == id) return n.copyWith(isRead: true);
      return n;
    }).toList();
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    await NotificationStorage.instance.markAllAsRead();
    state = state.map((n) => n.copyWith(isRead: true)).toList();
  }

  /// Clear all notifications
  Future<void> clearAll() async {
    await NotificationStorage.instance.clearAll();
    state = [];
  }
}

/// Provider for the notification inbox
final notificationInboxProvider =
    StateNotifierProvider<NotificationInboxNotifier, List<LocalNotification>>(
  (ref) => NotificationInboxNotifier(),
);

/// Derived provider for unread count (used on bell icon badge)
final unreadCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationInboxProvider);
  return notifications.where((n) => !n.isRead).length;
});
