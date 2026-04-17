import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/notification_entry.dart';
import '../../domain/models/app_notification.dart';
import '../../core/services/notification_service.dart';

final _supabase = Supabase.instance.client;

// ─── Admin Status Provider ────────────────────────────────────────────────
/// Checks if current user is an admin (database-backed)
final isAdminProvider = FutureProvider<bool>((ref) async {
  final user = _supabase.auth.currentUser;
  if (user == null) return false;

  try {
    final data = await _supabase
        .from('admins')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle();
    return data != null;
  } catch (e) {
    debugPrint('Admin check error: $e');
    return false;
  }
});

// ─── Notification Entries Provider ────────────────────────────────────────
/// Provides entries for a specific category ('newly_added' or 'recently_released')
final notificationEntriesProvider = FutureProvider.family<List<NotificationEntry>, String>(
  (ref, category) async {
    try {
      final data = await _supabase
          .from('notification_entries')
          .select()
          .eq('category', category)
          .order('created_at', ascending: false);

      return (data as List).map((e) => NotificationEntry.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Error loading entries: $e');
      return [];
    }
  },
);

// ─── Notification History Provider ────────────────────────────────────────
final notificationHistoryProvider = FutureProvider<List<AppNotification>>((ref) async {
  try {
    final data = await _supabase
        .from('notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(50);

    return (data as List).map((e) => AppNotification.fromJson(e)).toList();
  } catch (e) {
    debugPrint('Error loading notification history: $e');
    return [];
  }
});

// ─── Admin List Provider ──────────────────────────────────────────────────
final adminListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final data = await _supabase
        .from('admins')
        .select('id, user_id, email, created_at')
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  } catch (e) {
    debugPrint('Error loading admin list: $e');
    return [];
  }
});

// ─── User Notification Preferences ────────────────────────────────────────
class NotificationPrefs {
  final bool newlyAdded;
  final bool recentlyReleased;
  final bool adminMessages;

  const NotificationPrefs({
    this.newlyAdded = true,
    this.recentlyReleased = true,
    this.adminMessages = true,
  });

  factory NotificationPrefs.fromJson(Map<String, dynamic> json) {
    return NotificationPrefs(
      newlyAdded: json['newly_added'] ?? true,
      recentlyReleased: json['recently_released'] ?? true,
      adminMessages: json['admin_messages'] ?? true,
    );
  }
}

class NotificationPrefsNotifier extends AsyncNotifier<NotificationPrefs> {
  @override
  Future<NotificationPrefs> build() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return const NotificationPrefs();

    try {
      final data = await _supabase
          .from('user_notification_prefs')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (data != null) {
        return NotificationPrefs.fromJson(data);
      }
      return const NotificationPrefs();
    } catch (e) {
      return const NotificationPrefs();
    }
  }

  Future<void> updatePref(String field, bool value) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('user_notification_prefs').upsert({
        'user_id': user.id,
        field: value,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

      // Update FCM topic subscription
      final topicMap = {
        'newly_added': 'daniewatch_newly_added',
        'recently_released': 'daniewatch_recently_released',
        'admin_messages': 'daniewatch_admin_messages',
      };

      final topic = topicMap[field];
      if (topic != null) {
        if (value) {
          await NotificationService.instance.subscribeToTopic(topic);
        } else {
          await NotificationService.instance.unsubscribeFromTopic(topic);
        }
      }

      ref.invalidateSelf();
    } catch (e) {
      debugPrint('Error updating notification pref: $e');
    }
  }
}

final notificationPrefsProvider =
    AsyncNotifierProvider<NotificationPrefsNotifier, NotificationPrefs>(
  () => NotificationPrefsNotifier(),
);

// ─── Admin Actions Service ────────────────────────────────────────────────
class AdminService {
  static final AdminService instance = AdminService._();
  AdminService._();

  /// Add a content entry to a category
  Future<void> addEntry(NotificationEntry entry) async {
    await _supabase.from('notification_entries').insert(entry.toInsertJson());
  }

  /// Remove a single entry
  Future<void> removeEntry(String entryId) async {
    await _supabase.from('notification_entries').delete().eq('id', entryId);
  }

  /// Remove multiple entries
  Future<void> removeEntries(List<String> entryIds) async {
    await _supabase.from('notification_entries').delete().inFilter('id', entryIds);
  }

  /// Add a new admin by email
  Future<bool> addAdmin(String email) async {
    // Lookup user by email in profiles table
    final userData = await _supabase
        .from('profiles')
        .select('id, email')
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();

    if (userData == null) return false;

    await _supabase.from('admins').insert({
      'user_id': userData['id'],
      'email': email.trim().toLowerCase(),
      'added_by': _supabase.auth.currentUser?.id,
    });
    return true;
  }

  /// Remove an admin
  Future<void> removeAdmin(String adminId) async {
    await _supabase.from('admins').delete().eq('id', adminId);
  }

  /// Send a notification (records it in DB and calls Edge Function for FCM)
  Future<bool> sendNotification({
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      // 1. Record in database
      await _supabase.from('notifications').insert({
        'type': type,
        'title': title,
        'body': body,
        'data': data ?? {},
        'sent_by': _supabase.auth.currentUser?.id,
      });

      // 2. Call Edge Function for FCM push
      try {
        await _supabase.functions.invoke(
          'send-push-notification',
          body: {
            'type': type,
            'title': title,
            'body': body,
            'data': data ?? {},
          },
        );
      } catch (e) {
        debugPrint('Edge function call failed (notification still recorded): $e');
        // Notification is still recorded even if FCM push fails
      }

      return true;
    } catch (e) {
      debugPrint('Error sending notification: $e');
      return false;
    }
  }
}
