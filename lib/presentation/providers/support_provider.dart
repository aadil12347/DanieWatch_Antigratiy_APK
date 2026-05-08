import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/support_ticket.dart';
import '../../domain/models/support_message.dart';

final _supabase = Supabase.instance.client;

// ─── Support Service (mutations) ──────────────────────────────────────────

class SupportService {
  SupportService._();
  static final instance = SupportService._();

  /// Create a new ticket with an initial message
  Future<SupportTicket?> createTicket({
    required String subject,
    required String description,
    required String category,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      // 1. Insert the ticket
      final ticketData = await _supabase.from('support_tickets').insert({
        'user_id': user.id,
        'subject': subject,
        'description': description,
        'category': category,
        'status': 'new',
        'last_message_at': DateTime.now().toIso8601String(),
        'last_message_preview': description.length > 100
            ? '${description.substring(0, 100)}...'
            : description,
        'last_message_by': user.id,
        'unread_by_admin': true,
        'unread_by_user': false,
      }).select().single();

      final ticket = SupportTicket.fromJson(ticketData);

      // 2. Insert the initial message
      await _supabase.from('support_messages').insert({
        'ticket_id': ticket.id,
        'sender_id': user.id,
        'body': description,
        'is_admin': false,
      });

      // 3. Notify all admins about the new ticket
      try {
        final preview = description.length > 80
            ? '${description.substring(0, 80)}...'
            : description;
        await _supabase.functions.invoke(
          'send-push-notification',
          body: {
            'type': 'support_admin_notify',
            'sender_id': user.id,
            'ticket_id': ticket.id,
            'title': '🆕 New Support Request',
            'body': '$subject: $preview',
            'data': {
              'type': 'support_ticket',
              'ticket_id': ticket.id,
            },
          },
        );
      } catch (e) {
        debugPrint('Push notification failed (ticket still created): $e');
      }

      return ticket;
    } catch (e) {
      debugPrint('Error creating ticket: $e');
      return null;
    }
  }

  /// Send a message in a ticket
  Future<bool> sendMessage({
    required String ticketId,
    required String body,
    required bool isAdmin,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      // 1. Insert message
      await _supabase.from('support_messages').insert({
        'ticket_id': ticketId,
        'sender_id': user.id,
        'body': body,
        'is_admin': isAdmin,
      });

      // 2. Update ticket metadata
      final preview = body.length > 100 ? '${body.substring(0, 100)}...' : body;
      await _supabase.from('support_tickets').update({
        'last_message_at': DateTime.now().toIso8601String(),
        'last_message_preview': preview,
        'last_message_by': user.id,
        'unread_by_admin': !isAdmin,
        'unread_by_user': isAdmin,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', ticketId);

      // 3. Send push notification to the other party
      try {
        if (isAdmin) {
          // Admin sending → notify the ticket owner via targeted device push
          final ticketData = await _supabase
              .from('support_tickets')
              .select('user_id')
              .eq('id', ticketId)
              .single();
          final targetUserId = ticketData['user_id'] as String;

          await _supabase.functions.invoke(
            'send-push-notification',
            body: {
              'target_user_id': targetUserId,
              'sender_id': user.id,
              'ticket_id': ticketId,
              'title': '💬 Support Reply',
              'body': preview,
              'data': {
                'type': 'support_ticket',
                'ticket_id': ticketId,
              },
            },
          );
        } else {
          // User sending → notify all admins via topic-based push
          // This targets the 'daniewatch_support_admin' topic that all admins subscribe to
          await _supabase.functions.invoke(
            'send-push-notification',
            body: {
              'type': 'support_admin_notify',
              'topic': 'daniewatch_support_admin',
              'sender_id': user.id,
              'ticket_id': ticketId,
              'title': '📩 New Support Message',
              'body': preview,
              'data': {
                'type': 'support_ticket',
                'ticket_id': ticketId,
              },
            },
          );
        }
      } catch (e) {
        debugPrint('Push notification failed (message still sent): $e');
      }

      return true;
    } catch (e) {
      debugPrint('Error sending message: $e');
      return false;
    }
  }

  /// Update ticket status (admin only)
  Future<bool> updateTicketStatus(String ticketId, String newStatus) async {
    try {
      await _supabase.from('support_tickets').update({
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
        'unread_by_user': true,
      }).eq('id', ticketId);

      // Insert a system-like message about the status change
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final statusLabel = _statusLabel(newStatus);
        await _supabase.from('support_messages').insert({
          'ticket_id': ticketId,
          'sender_id': user.id,
          'body': '📋 Ticket status changed to "$statusLabel"',
          'is_admin': true,
        });

        // Update last message preview
        await _supabase.from('support_tickets').update({
          'last_message_at': DateTime.now().toIso8601String(),
          'last_message_preview': 'Status changed to $statusLabel',
          'last_message_by': user.id,
        }).eq('id', ticketId);

        // Notify the ticket owner about the status change
        try {
          final ticketData = await _supabase
              .from('support_tickets')
              .select('user_id')
              .eq('id', ticketId)
              .single();
          final targetUserId = ticketData['user_id'] as String;

          await _supabase.functions.invoke(
            'send-push-notification',
            body: {
              'target_user_id': targetUserId,
              'sender_id': user.id,
              'ticket_id': ticketId,
              'title': '📋 Ticket $statusLabel',
              'body': 'Your support request status changed to "$statusLabel"',
              'data': {
                'type': 'support_ticket',
                'ticket_id': ticketId,
              },
            },
          );
        } catch (e) {
          debugPrint('Status change push failed: $e');
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error updating ticket status: $e');
      return false;
    }
  }

  /// Bulk update status for multiple tickets
  Future<bool> bulkUpdateStatus(List<String> ticketIds, String newStatus) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      for (final ticketId in ticketIds) {
        await updateTicketStatus(ticketId, newStatus);
      }
      return true;
    } catch (e) {
      debugPrint('Error bulk updating: $e');
      return false;
    }
  }

  /// Bulk reply to multiple tickets
  Future<bool> bulkReply(List<String> ticketIds, String message) async {
    try {
      for (final ticketId in ticketIds) {
        await sendMessage(ticketId: ticketId, body: message, isAdmin: true);
      }
      return true;
    } catch (e) {
      debugPrint('Error bulk replying: $e');
      return false;
    }
  }

  /// Mark ticket as read
  Future<void> markTicketRead(String ticketId, {required bool isAdmin}) async {
    try {
      if (isAdmin) {
        await _supabase.from('support_tickets').update({
          'unread_by_admin': false,
        }).eq('id', ticketId);
      } else {
        await _supabase.from('support_tickets').update({
          'unread_by_user': false,
        }).eq('id', ticketId);
      }
    } catch (e) {
      debugPrint('Error marking ticket read: $e');
    }
  }

  /// Mark all messages from the other party as read (WhatsApp-style blue ticks)
  Future<void> markMessagesRead(String ticketId, {required bool isAdmin}) async {
    try {
      // Mark messages from the OTHER party as read
      await _supabase
          .from('support_messages')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('ticket_id', ticketId)
          .eq('is_admin', !isAdmin)
          .isFilter('read_at', null);
    } catch (e) {
      debugPrint('Error marking messages read: $e');
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'new': return 'New';
      case 'pending': return 'Pending';
      case 'completed': return 'Completed';
      case 'rejected': return 'Rejected';
      default: return status;
    }
  }

  /// Hide tickets locally (only from this user's view)
  Future<void> hideTickets(List<String> ticketIds, {required bool isAdmin}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = isAdmin ? 'hidden_tickets_admin' : 'hidden_tickets_user';
    final existing = prefs.getStringList(key) ?? [];
    final updated = {...existing, ...ticketIds}.toList();
    await prefs.setStringList(key, updated);
  }

  /// Get hidden ticket IDs for this role
  Future<Set<String>> getHiddenTicketIds({required bool isAdmin}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = isAdmin ? 'hidden_tickets_admin' : 'hidden_tickets_user';
    return (prefs.getStringList(key) ?? []).toSet();
  }
}

// ─── Providers ────────────────────────────────────────────────────────────

final supportServiceProvider = Provider<SupportService>((_) => SupportService.instance);

/// Hidden ticket IDs provider (triggers re-filter when updated)
final hiddenUserTicketIdsProvider = StateProvider<Set<String>>((ref) => {});
final hiddenAdminTicketIdsProvider = StateProvider<Set<String>>((ref) => {});

/// Initialize hidden ticket IDs from SharedPreferences
Future<void> loadHiddenTicketIds(WidgetRef ref, {required bool isAdmin}) async {
  final service = ref.read(supportServiceProvider);
  final hiddenIds = await service.getHiddenTicketIds(isAdmin: isAdmin);
  if (isAdmin) {
    ref.read(hiddenAdminTicketIdsProvider.notifier).state = hiddenIds;
  } else {
    ref.read(hiddenUserTicketIdsProvider.notifier).state = hiddenIds;
  }
}

/// Stream of current user's tickets (real-time) with hidden filter
final userTicketsProvider = StreamProvider<List<SupportTicket>>((ref) {
  final user = _supabase.auth.currentUser;
  if (user == null) return Stream.value([]);
  final hiddenIds = ref.watch(hiddenUserTicketIdsProvider);

  return _supabase
      .from('support_tickets')
      .stream(primaryKey: ['id'])
      .eq('user_id', user.id)
      .order('last_message_at', ascending: false)
      .map((data) => data
          .map((e) => SupportTicket.fromJson(e))
          .where((t) => !hiddenIds.contains(t.id))
          .toList());
});

/// Stream of ALL tickets for admin (real-time) — with profile join and hidden filter
final allTicketsProvider = StreamProvider<List<SupportTicket>>((ref) {
  final hiddenIds = ref.watch(hiddenAdminTicketIdsProvider);
  return _supabase
      .from('support_tickets')
      .stream(primaryKey: ['id'])
      .order('last_message_at', ascending: false)
      .asyncMap((tickets) async {
        final userIds = tickets.map((t) => t['user_id'] as String).toSet().toList();
        if (userIds.isEmpty) return <SupportTicket>[];

        try {
          final profiles = await _supabase
              .from('profiles')
              .select('id, username, avatar_url, email')
              .inFilter('id', userIds);

          final profileMap = <String, Map<String, dynamic>>{};
          for (final p in profiles) {
            profileMap[p['id'] as String] = p;
          }

          return tickets.map((t) {
            final userId = t['user_id'] as String;
            final profile = profileMap[userId];
            if (profile != null) {
              t['profiles'] = profile;
            }
            return SupportTicket.fromJson(t);
          }).where((t) => !hiddenIds.contains(t.id)).toList();
        } catch (e) {
          return tickets.map((t) => SupportTicket.fromJson(t))
              .where((t) => !hiddenIds.contains(t.id)).toList();
        }
      });
});

/// Stream of messages for a specific ticket (real-time)
final ticketMessagesProvider = StreamProvider.family<List<SupportMessage>, String>((ref, ticketId) {
  return _supabase
      .from('support_messages')
      .stream(primaryKey: ['id'])
      .eq('ticket_id', ticketId)
      .order('created_at', ascending: true)
      .map((data) => data.map((e) => SupportMessage.fromJson(e)).toList());
});

/// Count of unread tickets for admin
final adminUnreadCountProvider = Provider<int>((ref) {
  final ticketsAsync = ref.watch(allTicketsProvider);
  return ticketsAsync.whenOrNull(
    data: (tickets) => tickets.where((t) => t.unreadByAdmin).length,
  ) ?? 0;
});

/// Count of unread tickets for user
final userUnreadCountProvider = Provider<int>((ref) {
  final ticketsAsync = ref.watch(userTicketsProvider);
  return ticketsAsync.whenOrNull(
    data: (tickets) => tickets.where((t) => t.unreadByUser).length,
  ) ?? 0;
});
