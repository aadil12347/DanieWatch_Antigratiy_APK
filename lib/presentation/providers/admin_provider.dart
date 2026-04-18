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

/// Alias for notificationEntriesProvider — used by send_notification_screen
final categoryEntriesProvider = notificationEntriesProvider;

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

  /// Category label mapping: DB value → UI label
  static String getCategoryLabel(String dbCategory) {
    switch (dbCategory) {
      case 'newly_added':
        return 'Latest Released';
      case 'recently_released':
        return 'Recently Added';
      default:
        return dbCategory;
    }
  }

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

  /// Send category-based notifications with smart grouping:
  /// - 'recently_released' (UI: "Recently Added") → single combined summary push
  /// - 'newly_added' (UI: "Latest Released") → separate per-entry pushes
  Future<int> sendCategoryNotifications(String category) async {
    try {
      // 1. Fetch all entries for this category
      final data = await _supabase
          .from('notification_entries')
          .select()
          .eq('category', category)
          .order('created_at', ascending: false);

      final entries = (data as List).map((e) => NotificationEntry.fromJson(e)).toList();
      if (entries.isEmpty) return 0;

      final uiLabel = getCategoryLabel(category);

      if (category == 'recently_released') {
        // ── COMBINED SUMMARY PUSH ──────────────────────────────────────
        // Record individual entries in DB for rich inbox cards
        for (final entry in entries) {
          await _supabase.from('notifications').insert({
            'type': category,
            'title': '🎬 $uiLabel',
            'body': '${entry.title} (${entry.releaseYear ?? ""})',
            'data': {
              'poster_url': entry.posterUrl ?? '',
              'media_type': entry.mediaType,
              'release_year': (entry.releaseYear ?? '').toString(),
              'tmdb_id': entry.tmdbId.toString(),
              'vote_average': (entry.voteAverage ?? 0).toString(),
            },
            'sent_by': _supabase.auth.currentUser?.id,
          });
        }

        // Send ONE combined FCM push
        final titles = entries.map((e) => e.title).take(3).join(', ');
        final summaryBody = entries.length > 3
            ? '$titles and ${entries.length - 3} more'
            : titles;
        try {
          await _supabase.functions.invoke(
            'send-push-notification',
            body: {
              'type': category,
              'title': '🎬 ${entries.length} $uiLabel',
              'body': summaryBody,
              'data': {'type': category},
            },
          );
        } catch (e) {
          debugPrint('Summary FCM push failed: $e');
        }
      } else if (category == 'newly_added') {
        // ── SEPARATE PER-ENTRY PUSHES ─────────────────────────────────
        for (final entry in entries) {
          final entryData = {
            'poster_url': entry.posterUrl ?? '',
            'media_type': entry.mediaType,
            'release_year': (entry.releaseYear ?? '').toString(),
            'tmdb_id': entry.tmdbId.toString(),
            'vote_average': (entry.voteAverage ?? 0).toString(),
            'type': category,
          };

          // Record in DB
          await _supabase.from('notifications').insert({
            'type': category,
            'title': '🎬 ${entry.title}${entry.releaseYear != null ? " (${entry.releaseYear})" : ""}',
            'body': '$uiLabel • ${entry.mediaType == "tv" ? "TV Show" : "Movie"}',
            'data': entryData,
            'sent_by': _supabase.auth.currentUser?.id,
          });

          // Send individual FCM push
          try {
            await _supabase.functions.invoke(
              'send-push-notification',
              body: {
                'type': category,
                'title': '🎬 ${entry.title}${entry.releaseYear != null ? " (${entry.releaseYear})" : ""}',
                'body': '$uiLabel • ${entry.mediaType == "tv" ? "TV Show" : "Movie"}',
                'image': entry.posterUrl,
                'data': entryData,
              },
            );
          } catch (e) {
            debugPrint('Individual FCM push failed for ${entry.title}: $e');
          }
        }
      }

      return entries.length;
    } catch (e) {
      debugPrint('Error sending category notifications: $e');
      return 0;
    }
  }
}

