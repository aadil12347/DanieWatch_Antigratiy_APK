/// Model for locally stored notifications (SharedPreferences).
/// Tracks read/unread state and contains rich data for entry-based notifications.
class LocalNotification {
  final String id;
  final String type; // 'newly_added', 'recently_released', 'admin_message'
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final bool isRead;

  LocalNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    required this.createdAt,
    this.isRead = false,
  });

  // ─── Rich data getters (from FCM data payload) ──────────────────────────
  String? get posterUrl => data['poster_url']?.toString();
  String? get mediaType => data['media_type']?.toString();
  int? get tmdbId => int.tryParse(data['tmdb_id']?.toString() ?? '');
  int? get releaseYear => int.tryParse(data['release_year']?.toString() ?? '');
  double? get voteAverage => double.tryParse(data['vote_average']?.toString() ?? '');

  /// Whether this notification has rich entry data (poster, title, media type)
  bool get isRichNotification => posterUrl != null && tmdbId != null;

  /// UI label for the notification type
  String get categoryLabel {
    switch (type) {
      case 'newly_added':
        return 'Latest Released';
      case 'recently_released':
        return 'Recently Added';
      case 'admin_message':
        return 'Admin Message';
      default:
        return 'Notification';
    }
  }

  LocalNotification copyWith({bool? isRead}) {
    return LocalNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      data: data,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'body': body,
      'data': data,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
    };
  }

  factory LocalNotification.fromJson(Map<String, dynamic> json) {
    return LocalNotification(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      data: (json['data'] is Map) ? Map<String, dynamic>.from(json['data']) : {},
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      isRead: json['is_read'] ?? false,
    );
  }
}
