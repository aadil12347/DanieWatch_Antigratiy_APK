import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/notification_service.dart';
import '../../data/local/notification_storage.dart';
import '../../domain/models/local_notification.dart';

/// Manages local notification inbox state with Supabase sync + real-time updates.
/// Strategy: Keep old cache → fetch fresh from Supabase in background → 
/// replace only when fresh data fully loads.
class NotificationInboxNotifier extends StateNotifier<List<LocalNotification>> {
  StreamSubscription? _realtimeSubscription;
  StreamSubscription<LocalNotification>? _foregroundSubscription;

  NotificationInboxNotifier() : super([]) {
    _initialize();
  }

  /// Load cached notifications first, then sync from Supabase in background
  Future<void> _initialize() async {
    // 1. Show cached data immediately
    await loadNotifications();
    
    // 2. Sync from Supabase in background (replaces cache only when fully loaded)
    syncFromSupabase();

    // 3. Start real-time subscription for instant updates
    _startRealtimeSubscription();
  }



  /// Load notifications from local storage (instant)
  Future<void> loadNotifications() async {
    final notifications = await NotificationStorage.instance.loadNotifications();
    if (mounted) {
      state = notifications;
    }
  }

  /// Sync from Supabase — fetches last 7 days, replaces cache only when fully loaded
  Future<void> syncFromSupabase() async {
    try {
      final supabase = Supabase.instance.client;
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      
      final data = await supabase
          .from('notifications')
          .select()
          .gte('created_at', sevenDaysAgo.toIso8601String())
          .order('created_at', ascending: false)
          .limit(100);

      if (data == null || data is! List) return;

      // Convert Supabase rows → LocalNotification objects
      final freshNotifications = <LocalNotification>[];
      for (final row in data) {
        try {
          final notification = LocalNotification(
            id: row['id'] ?? '',
            type: row['type'] ?? 'admin_message',
            title: row['title'] ?? '',
            body: row['body'] ?? '',
            data: (row['data'] is Map) ? Map<String, dynamic>.from(row['data']) : {},
            createdAt: DateTime.tryParse(row['created_at'] ?? '') ?? DateTime.now(),
            isRead: false, // We don't track read state in Supabase
          );
          freshNotifications.add(notification);
        } catch (e) {
          debugPrint('⚠️ Failed to parse notification row: $e');
        }
      }

      if (freshNotifications.isEmpty && state.isNotEmpty) {
        // Don't replace existing cache with empty data
        return;
      }

      // Preserve read state from existing cache
      final existingReadIds = <String>{};
      for (final n in state) {
        if (n.isRead) existingReadIds.add(n.id);
      }

      final mergedNotifications = freshNotifications.map((n) {
        if (existingReadIds.contains(n.id)) {
          return n.copyWith(isRead: true);
        }
        return n;
      }).toList();

      // ── Deduplicate "newly_added" (Latest Released) by content identity ──
      // If admin sends the same latest release notification multiple times,
      // keep only the newest one per (tmdb_id, title, type) combination.
      final deduped = <LocalNotification>[];
      final seenLatestKeys = <String>{};
      // mergedNotifications is already sorted newest-first
      for (final n in mergedNotifications) {
        if (n.type == 'newly_added' && n.tmdbId != null) {
          final key = '${n.tmdbId}_${n.title}_${n.type}';
          if (seenLatestKeys.contains(key)) continue; // skip older duplicate
          seenLatestKeys.add(key);
        }
        deduped.add(n);
      }

      // Replace cache with fresh data
      await NotificationStorage.instance.replaceAll(deduped);
      if (mounted) {
        state = deduped;
      }
      debugPrint('✅ Synced ${deduped.length} notifications from Supabase (deduped from ${mergedNotifications.length})');
    } catch (e) {
      debugPrint('⚠️ Supabase notification sync failed (keeping cache): $e');
      // Keep existing cache — don't clear
    }
  }

  /// Start real-time subscription for instant bell updates
  void _startRealtimeSubscription() {
    try {
      final supabase = Supabase.instance.client;
      final channel = supabase.channel('notifications_realtime');
      
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        callback: (payload) {
          debugPrint('🔔 Real-time notification received!');
          final row = payload.newRecord;
          if (row.isEmpty) return;

          try {
            final notification = LocalNotification(
              id: row['id'] ?? '',
              type: row['type'] ?? 'admin_message',
              title: row['title'] ?? '',
              body: row['body'] ?? '',
              data: (row['data'] is Map) ? Map<String, dynamic>.from(row['data']) : {},
              createdAt: DateTime.tryParse(row['created_at'] ?? '') ?? DateTime.now(),
              isRead: false,
            );

            // Add to local storage + state immediately
            _addNotificationLocally(notification);
          } catch (e) {
            debugPrint('⚠️ Failed to parse real-time notification: $e');
          }
        },
      ).subscribe();

      debugPrint('✅ Real-time notification subscription started');
    } catch (e) {
      debugPrint('⚠️ Real-time subscription failed: $e');
    }
  }

  /// Add a notification locally (from real-time or FCM)
  Future<void> _addNotificationLocally(LocalNotification notification) async {
    // Avoid duplicates — check by ID first
    if (state.any((n) => n.id == notification.id)) return;

    // Also dedup by tmdb_id + type for rich notifications (FCM ID ≠ Supabase UUID)
    final tmdbId = notification.tmdbId;
    if (tmdbId != null) {
      final isDuplicate = state.any((n) =>
        n.tmdbId == tmdbId &&
        n.type == notification.type &&
        n.title == notification.title &&
        n.createdAt.difference(notification.createdAt).inMinutes.abs() < 5
      );
      if (isDuplicate) {
        debugPrint('⚠️ Skipping duplicate notification (tmdb_id=$tmdbId, type=${notification.type})');
        return;
      }
    }
    
    await NotificationStorage.instance.addNotification(notification);
    if (mounted) {
      state = [notification, ...state];
    }
  }

  /// Add a new notification and refresh state
  Future<void> addNotification(LocalNotification notification) async {
    await _addNotificationLocally(notification);
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

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    _foregroundSubscription?.cancel();
    super.dispose();
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
