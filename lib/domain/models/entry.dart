/// Entry data model for movie/TV content.
/// Uses simple JSON serialization instead of Freezed for easier maintenance.
class EntryData {
  final String id;
  final String type; // 'movie' | 'series'
  final String title;
  final String? posterUrl;
  final String? backdropUrl;
  final String? logoUrl;
  final String? hoverImageUrl;
  final double voteAverage;
  final int voteCount;
  final int? releaseYear;
  final String? originalLanguage;
  final List<String> originCountry;
  final List<int> genreIds;
  final String? overview;
  final String? tagline;
  final int? runtime;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;
  final String? status;
  final String? imdbId;
  final List<Genre> genres;
  final List<CastMember> castData;
  final Map<String, dynamic>? content;
  final String? mediaUpdatedAt;

  EntryData({
    required this.id,
    required this.type,
    required this.title,
    this.posterUrl,
    this.backdropUrl,
    this.logoUrl,
    this.hoverImageUrl,
    this.voteAverage = 0.0,
    this.voteCount = 0,
    this.releaseYear,
    this.originalLanguage,
    this.originCountry = const [],
    this.genreIds = const [],
    this.overview,
    this.tagline,
    this.runtime,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.status,
    this.imdbId,
    this.genres = const [],
    this.castData = const [],
    this.content,
    this.mediaUpdatedAt,
  });

  factory EntryData.fromJson(Map<String, dynamic> json) {
    return EntryData(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      posterUrl: json['poster_url'] as String?,
      backdropUrl: json['backdrop_url'] as String?,
      logoUrl: json['logo_url'] as String?,
      hoverImageUrl: json['hover_image_url'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: json['vote_count'] as int? ?? 0,
      releaseYear: json['release_year'] as int?,
      originalLanguage: json['original_language'] as String?,
      originCountry: (json['origin_country'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      genreIds: (json['genre_ids'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      overview: json['overview'] as String?,
      tagline: json['tagline'] as String?,
      runtime: json['runtime'] as int?,
      numberOfSeasons: json['number_of_seasons'] as int?,
      numberOfEpisodes: json['number_of_episodes'] as int?,
      status: json['status'] as String?,
      imdbId: json['imdb_id'] as String?,
      genres: (json['genres'] as List<dynamic>?)
              ?.map((e) => Genre.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      castData: (json['cast_data'] as List<dynamic>?)
              ?.map((e) => CastMember.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      content: json['content'] as Map<String, dynamic>?,
      mediaUpdatedAt: json['media_updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'poster_url': posterUrl,
      'backdrop_url': backdropUrl,
      'logo_url': logoUrl,
      'hover_image_url': hoverImageUrl,
      'vote_average': voteAverage,
      'vote_count': voteCount,
      'release_year': releaseYear,
      'original_language': originalLanguage,
      'origin_country': originCountry,
      'genre_ids': genreIds,
      'overview': overview,
      'tagline': tagline,
      'runtime': runtime,
      'number_of_seasons': numberOfSeasons,
      'number_of_episodes': numberOfEpisodes,
      'status': status,
      'imdb_id': imdbId,
      'genres': genres.map((e) => e.toJson()).toList(),
      'cast_data': castData.map((e) => e.toJson()).toList(),
      'content': content,
      'media_updated_at': mediaUpdatedAt,
    };
  }
}

class Genre {
  final int id;
  final String name;

  Genre({required this.id, required this.name});

  factory Genre.fromJson(Map<String, dynamic> json) {
    return Genre(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name};
  }
}

class CastMember {
  final int id;
  final String name;
  final String? character;
  final String? profilePath;

  CastMember({
    required this.id,
    required this.name,
    this.character,
    this.profilePath,
  });

  factory CastMember.fromJson(Map<String, dynamic> json) {
    return CastMember(
      id: json['id'] as int,
      name: json['name'] as String,
      character: json['character'] as String?,
      profilePath: json['profile_path'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'character': character,
      'profile_path': profilePath,
    };
  }
}

class WatchlistItem {
  final int tmdbId;
  final String mediaType;
  final String title;
  final String? posterPath;
  final double voteAverage;
  final DateTime? addedAt;

  WatchlistItem({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.posterPath,
    this.voteAverage = 0.0,
    this.addedAt,
  });

  factory WatchlistItem.fromJson(Map<String, dynamic> json) {
    return WatchlistItem(
      tmdbId: json['tmdb_id'] as int,
      mediaType: json['media_type'] as String,
      title: json['title'] as String,
      posterPath: json['poster_path'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      addedAt: json['added_at'] != null
          ? DateTime.parse(json['added_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tmdb_id': tmdbId,
      'media_type': mediaType,
      'title': title,
      'poster_path': posterPath,
      'vote_average': voteAverage,
      'added_at': addedAt?.toIso8601String(),
    };
  }
}

class ContinueWatchingItem {
  final int tmdbId;
  final String mediaType;
  final String title;
  final String? posterPath;
  final int? season;
  final int? episode;
  final int progressSeconds;
  final int totalSeconds;
  final DateTime? updatedAt;

  ContinueWatchingItem({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.posterPath,
    this.season,
    this.episode,
    this.progressSeconds = 0,
    this.totalSeconds = 0,
    this.updatedAt,
  });

  factory ContinueWatchingItem.fromJson(Map<String, dynamic> json) {
    return ContinueWatchingItem(
      tmdbId: json['tmdb_id'] as int,
      mediaType: json['media_type'] as String,
      title: json['title'] as String,
      posterPath: json['poster_path'] as String?,
      season: json['season'] as int?,
      episode: json['episode'] as int?,
      progressSeconds: json['progress_seconds'] as int? ?? 0,
      totalSeconds: json['total_seconds'] as int? ?? 0,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tmdb_id': tmdbId,
      'media_type': mediaType,
      'title': title,
      'poster_path': posterPath,
      'season': season,
      'episode': episode,
      'progress_seconds': progressSeconds,
      'total_seconds': totalSeconds,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  double get progressFraction =>
      totalSeconds > 0 ? progressSeconds / totalSeconds : 0.0;
}

/// A categorized section of content for home display
class DbSection {
  final String title;
  final List<ManifestItemRef> items;

  const DbSection({required this.title, required this.items});
}

class ManifestItemRef {
  final int id;
  final String mediaType;

  const ManifestItemRef(this.id, this.mediaType);
}
