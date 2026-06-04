class SupportMessage {
  final String id;
  final String ticketId;
  final String senderId;
  final String body;
  final bool isAdmin;
  final DateTime createdAt;
  final DateTime? readAt;

  const SupportMessage({
    required this.id,
    required this.ticketId,
    required this.senderId,
    required this.body,
    this.isAdmin = false,
    required this.createdAt,
    this.readAt,
  });

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    return SupportMessage(
      id: json['id'] as String,
      ticketId: json['ticket_id'] as String,
      senderId: json['sender_id'] as String,
      body: json['body'] as String,
      isAdmin: (json['is_admin'] as bool?) ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'ticket_id': ticketId,
        'sender_id': senderId,
        'body': body,
        'is_admin': isAdmin,
      };

  /// WhatsApp-style message status
  /// - sent: message exists in DB
  /// - read: readAt is set (recipient opened the chat)
  MessageStatus get status {
    if (readAt != null) return MessageStatus.read;
    return MessageStatus.delivered;
  }

  String get timeFormatted {
    final h = createdAt.hour;
    final m = createdAt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final hour12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$hour12:$m $period';
  }

  String get dateFormatted {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[createdAt.month - 1]} ${createdAt.day}';
  }
}

enum MessageStatus { delivered, read }
