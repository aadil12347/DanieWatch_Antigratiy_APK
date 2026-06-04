class UserProfile {
  final String id;
  final String username;
  final String email;
  final String? fullName;
  final String? avatarUrl;

  UserProfile({
    required this.id,
    required this.username,
    required this.email,
    this.fullName,
    this.avatarUrl,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'full_name': fullName,
      'avatar_url': avatarUrl,
    };
  }

  UserProfile copyWith({
    String? username,
    String? fullName,
    String? avatarUrl,
  }) {
    return UserProfile(
      id: id,
      username: username ?? this.username,
      email: email,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
