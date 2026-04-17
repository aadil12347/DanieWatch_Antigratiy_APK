/// Represents a sent push notification record.
/// These are stored in the database for 7 days before auto-cleanup.
class AppNotification {
  final String id;
  final String type; // 'newly_added', 'recently_released', 'admin_message'
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final String? sentBy;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    this.sentBy,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'admin_message',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      data: json['data'] is Map<String, dynamic> ? json['data'] : {},
      sentBy: json['sent_by']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  String get typeLabel {
    switch (type) {
      case 'newly_added':
        return 'Newly Added';
      case 'recently_released':
        return 'Recently Released';
      case 'admin_message':
        return 'Admin Message';
      default:
        return type;
    }
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}
