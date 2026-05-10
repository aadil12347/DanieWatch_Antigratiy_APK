import 'package:flutter/material.dart';

class SupportTicket {
  final String id;
  final String userId;
  final String subject;
  final String description;
  final String category;
  final String status;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final String? lastMessageBy;
  final bool unreadByAdmin;
  final bool unreadByUser;
  final DateTime createdAt;
  // Joined from profiles (for admin view)
  final String? username;
  final String? userAvatarUrl;
  final String? userEmail;

  const SupportTicket({
    required this.id,
    required this.userId,
    required this.subject,
    this.description = '',
    required this.category,
    required this.status,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.lastMessageBy,
    this.unreadByAdmin = true,
    this.unreadByUser = false,
    required this.createdAt,
    this.username,
    this.userAvatarUrl,
    this.userEmail,
  });

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    // Handle joined profile data
    final profile = json['profiles'];
    return SupportTicket(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      subject: json['subject'] as String,
      description: (json['description'] as String?) ?? '',
      category: json['category'] as String,
      status: json['status'] as String,
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'] as String)
          : null,
      lastMessagePreview: json['last_message_preview'] as String?,
      lastMessageBy: json['last_message_by'] as String?,
      unreadByAdmin: (json['unread_by_admin'] as bool?) ?? true,
      unreadByUser: (json['unread_by_user'] as bool?) ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      username: profile != null ? profile['username'] as String? : null,
      userAvatarUrl: profile != null ? profile['avatar_url'] as String? : null,
      userEmail: profile != null ? profile['email'] as String? : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'subject': subject,
        'description': description,
        'category': category,
        'status': status,
      };

  SupportTicket copyWith({
    String? status,
    DateTime? lastMessageAt,
    String? lastMessagePreview,
    String? lastMessageBy,
    bool? unreadByAdmin,
    bool? unreadByUser,
  }) {
    return SupportTicket(
      id: id,
      userId: userId,
      subject: subject,
      description: description,
      category: category,
      status: status ?? this.status,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageBy: lastMessageBy ?? this.lastMessageBy,
      unreadByAdmin: unreadByAdmin ?? this.unreadByAdmin,
      unreadByUser: unreadByUser ?? this.unreadByUser,
      createdAt: createdAt,
      username: username,
      userAvatarUrl: userAvatarUrl,
      userEmail: userEmail,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────

  String get categoryLabel {
    switch (category) {
      case 'add_movie_series':
        return 'Add Movie or Series';
      case 'add_movie':
        return 'Add Movie';
      case 'add_tv_show':
        return 'Add TV Show';
      case 'bug_report':
        return 'Bug Report';
      case 'feature_request':
        return 'Feature Request';
      default:
        return 'Other';
    }
  }

  IconData get categoryIcon {
    switch (category) {
      case 'add_movie_series':
        return Icons.movie_filter_rounded;
      case 'add_movie':
        return Icons.movie_rounded;
      case 'add_tv_show':
        return Icons.tv_rounded;
      case 'bug_report':
        return Icons.bug_report_rounded;
      case 'feature_request':
        return Icons.lightbulb_rounded;
      default:
        return Icons.chat_bubble_rounded;
    }
  }

  Color get categoryColor {
    switch (category) {
      case 'add_movie_series':
        return const Color(0xFF7C3AED);
      case 'add_movie':
        return const Color(0xFF7C3AED);
      case 'add_tv_show':
        return const Color(0xFF0891B2);
      case 'bug_report':
        return const Color(0xFFEF4444);
      case 'feature_request':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String get statusLabel {
    switch (status) {
      case 'new':
        return 'New';
      case 'open':
        return 'Open';
      case 'pending':
        return 'Pending';
      case 'completed':
        return 'Completed';
      case 'rejected':
        return 'Rejected';
      default:
        return status;
    }
  }

  /// Whether the status badge should be visible in the UI.
  /// 'open' status (admin has seen the ticket) shows no badge.
  bool get showStatusBadge => status != 'open';

  Color get statusColor {
    switch (status) {
      case 'new':
        return const Color(0xFF3B82F6);
      case 'open':
        return const Color(0xFF6B7280);
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'completed':
        return const Color(0xFF10B981);
      case 'rejected':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF6B7280);
    }
  }

  bool get isClosed => status == 'completed' || status == 'rejected';

  String get timeAgo {
    final now = DateTime.now();
    final target = (lastMessageAt ?? createdAt).toLocal();
    final diff = now.difference(target);
    if (diff.isNegative) return 'now';
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}
