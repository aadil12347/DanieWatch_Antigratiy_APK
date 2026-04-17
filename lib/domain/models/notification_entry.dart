/// Represents a content entry in the admin notification system.
/// Entries are content items (movies/shows) that admins curate for
/// "Newly Added" or "Recently Released" notification lists.
class NotificationEntry {
  final String id;
  final int tmdbId;
  final String mediaType;
  final String title;
  final String? posterUrl;
  final String? backdropUrl;
  final int? releaseYear;
  final double voteAverage;
  final String category; // 'newly_added' or 'recently_released'
  final String? addedBy;
  final DateTime createdAt;

  const NotificationEntry({
    required this.id,
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.posterUrl,
    this.backdropUrl,
    this.releaseYear,
    this.voteAverage = 0,
    required this.category,
    this.addedBy,
    required this.createdAt,
  });

  factory NotificationEntry.fromJson(Map<String, dynamic> json) {
    return NotificationEntry(
      id: json['id']?.toString() ?? '',
      tmdbId: json['tmdb_id'] is int ? json['tmdb_id'] : int.tryParse(json['tmdb_id'].toString()) ?? 0,
      mediaType: json['media_type']?.toString() ?? 'movie',
      title: json['title']?.toString() ?? '',
      posterUrl: json['poster_url']?.toString(),
      backdropUrl: json['backdrop_url']?.toString(),
      releaseYear: json['release_year'] is int ? json['release_year'] : int.tryParse(json['release_year']?.toString() ?? ''),
      voteAverage: (json['vote_average'] is num ? json['vote_average'].toDouble() : double.tryParse(json['vote_average']?.toString() ?? '0')) ?? 0,
      category: json['category']?.toString() ?? 'newly_added',
      addedBy: json['added_by']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'tmdb_id': tmdbId,
      'media_type': mediaType,
      'title': title,
      'poster_url': posterUrl,
      'backdrop_url': backdropUrl,
      'release_year': releaseYear,
      'vote_average': voteAverage,
      'category': category,
    };
  }
}
