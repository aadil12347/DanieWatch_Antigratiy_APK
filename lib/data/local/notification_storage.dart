import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/local_notification.dart';

/// Local notification storage using SharedPreferences.
/// Persists notifications on-device until the user clears them.
class NotificationStorage {
  static const String _key = 'local_notifications';
  static final NotificationStorage instance = NotificationStorage._();
  NotificationStorage._();

  /// Load all notifications from local storage
  Future<List<LocalNotification>> loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_key);
      if (jsonStr == null || jsonStr.isEmpty) return [];

      final List<dynamic> jsonList = json.decode(jsonStr);
      return jsonList
          .map((e) => LocalNotification.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      return [];
    }
  }

  /// Save the full list of notifications
  Future<void> saveNotifications(List<LocalNotification> notifications) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = json.encode(notifications.map((n) => n.toJson()).toList());
      await prefs.setString(_key, jsonStr);
    } catch (_) {}
  }

  /// Add a new notification (prepends to list, marks as unread)
  Future<void> addNotification(LocalNotification notification) async {
    final existing = await loadNotifications();
    // Avoid duplicates by ID
    if (existing.any((n) => n.id == notification.id)) return;
    existing.insert(0, notification);
    // Cap at 100 notifications to prevent unbounded growth
    if (existing.length > 100) {
      existing.removeRange(100, existing.length);
    }
    await saveNotifications(existing);
  }

  /// Mark a specific notification as read
  Future<void> markAsRead(String id) async {
    final notifications = await loadNotifications();
    final updated = notifications.map((n) {
      if (n.id == id) return n.copyWith(isRead: true);
      return n;
    }).toList();
    await saveNotifications(updated);
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    final notifications = await loadNotifications();
    final updated = notifications.map((n) => n.copyWith(isRead: true)).toList();
    await saveNotifications(updated);
  }

  /// Clear all notifications
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Get count of unread notifications
  Future<int> getUnreadCount() async {
    final notifications = await loadNotifications();
    return notifications.where((n) => !n.isRead).length;
  }
}
