/// Represents a single item in the GitHub index.json manifest.
/// This is the single source of truth for what's available in the app.
/// Items NOT in the manifest are NEVER rendered (DB-only visibility policy).
class ManifestItem {
  final int id;
  final String mediaType;
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
  final List<String> genres;
  final String? overview;
  final String? tagline;
  final int? runtime;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;
  final String? status;
  final String? imdbId;
  final List<String> language;
  final String? result;
  final bool isTrending;
  final bool isPopular;
  final String? tmdbPosterPath;
  final String? tmdbBackdropPath;

  ManifestItem({
    required this.id,
    required this.mediaType,
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
    this.genres = const [],
    this.overview,
    this.tagline,
    this.runtime,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.status,
    this.imdbId,
    this.language = const [],
    this.result,
    this.isTrending = false,
    this.isPopular = false,
    this.tmdbPosterPath,
    this.tmdbBackdropPath,
  });

  /// Safe int parser — handles both int and String values from JSON
  static int? _safeInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  /// Safe double parser — handles both num and String values from JSON
  static double _safeDouble(dynamic value, [double fallback = 0.0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  /// Filter out empty image URLs — keep all formats, let widget handle fallbacks
  static String? _sanitizePosterUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return url;
  }

  factory ManifestItem.fromJson(Map<String, dynamic> json) {
    return ManifestItem(
      id: _safeInt(json['id']) ?? 0,
      mediaType: (json['media_type'] ?? json['type'] ?? 'movie').toString(),
      title: (json['title'] ?? '').toString(),
      posterUrl: _sanitizePosterUrl((json['poster_url'] ?? json['poster'])?.toString()),
      backdropUrl: _sanitizePosterUrl((json['backdrop_url'] ?? json['backdrop'])?.toString()),
      logoUrl: json['logo_url']?.toString(),
      hoverImageUrl: json['hover_image_url']?.toString(),
      voteAverage: _safeDouble(json['vote_average']),
      voteCount: _safeInt(json['vote_count']) ?? 0,
      releaseYear: _safeInt(json['release_year'] ?? json['year']),
      originalLanguage: json['original_language']?.toString().trim().toLowerCase(),
      originCountry: ((json['origin_country'] ?? json['country']) as List<dynamic>?)
              ?.map((e) => e.toString().trim().toUpperCase())
              .toList() ??
          [],
      genreIds: (json['genre_ids'] as List<dynamic>?)
              ?.map((e) => _safeInt(e) ?? 0)
              .toList() ??
          [],
      genres: (json['genres'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      overview: json['overview']?.toString(),
      tagline: json['tagline']?.toString(),
      runtime: _safeInt(json['runtime']),
      numberOfSeasons: _safeInt(json['number_of_seasons']),
      numberOfEpisodes: _safeInt(json['number_of_episodes']),
      status: json['status']?.toString(),
      imdbId: json['imdb_id']?.toString(),
      language: (json['language'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      result: json['result']?.toString(),
      isTrending: json['is_trending'] == true,
      isPopular: json['is_popular'] == true,
      tmdbPosterPath: json['tmdb_poster_path']?.toString(),
      tmdbBackdropPath: json['tmdb_backdrop_path']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'media_type': mediaType,
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
      'genres': genres,
      'overview': overview,
      'tagline': tagline,
      'runtime': runtime,
      'number_of_seasons': numberOfSeasons,
      'number_of_episodes': numberOfEpisodes,
      'status': status,
      'imdb_id': imdbId,
      'language': language,
      'result': result,
      'is_trending': isTrending,
      'is_popular': isPopular,
      'tmdb_poster_path': tmdbPosterPath,
      'tmdb_backdrop_path': tmdbBackdropPath,
    };
  }

  /// Effective poster URL: skip .avif (unsupported), prefer TMDB fallback
  String? get effectivePosterUrl {
    if (posterUrl != null && posterUrl!.isNotEmpty && !posterUrl!.toLowerCase().endsWith('.avif')) {
      return posterUrl;
    }
    if (tmdbPosterPath != null) {
      return 'https://image.tmdb.org/t/p/w342$tmdbPosterPath';
    }
    return null;
  }

  /// Effective backdrop URL: skip .avif, prefer TMDB fallback
  String? get effectiveBackdropUrl {
    if (backdropUrl != null && backdropUrl!.isNotEmpty && !backdropUrl!.toLowerCase().endsWith('.avif')) {
      return backdropUrl;
    }
    if (tmdbBackdropPath != null) {
      return 'https://image.tmdb.org/t/p/w780$tmdbBackdropPath';
    }
    return null;
  }

  ManifestItem copyWith({
    int? id,
    String? mediaType,
    String? title,
    String? posterUrl,
    String? backdropUrl,
    String? logoUrl,
    double? voteAverage,
    int? voteCount,
    int? releaseYear,
    String? originalLanguage,
    List<String>? originCountry,
    List<int>? genreIds,
    List<String>? genres,
    String? overview,
    bool? isTrending,
    bool? isPopular,
    String? tmdbPosterPath,
    String? tmdbBackdropPath,
  }) {
    return ManifestItem(
      id: id ?? this.id,
      mediaType: mediaType ?? this.mediaType,
      title: title ?? this.title,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      logoUrl: logoUrl ?? this.logoUrl,
      hoverImageUrl: hoverImageUrl,
      voteAverage: voteAverage ?? this.voteAverage,
      voteCount: voteCount ?? this.voteCount,
      releaseYear: releaseYear ?? this.releaseYear,
      originalLanguage: originalLanguage ?? this.originalLanguage,
      originCountry: originCountry ?? this.originCountry,
      genreIds: genreIds ?? this.genreIds,
      genres: genres ?? this.genres,
      overview: overview ?? this.overview,
      tagline: tagline,
      runtime: runtime,
      numberOfSeasons: numberOfSeasons,
      numberOfEpisodes: numberOfEpisodes,
      status: status,
      imdbId: imdbId,
      language: language,
      result: result,
      isTrending: isTrending ?? this.isTrending,
      isPopular: isPopular ?? this.isPopular,
      tmdbPosterPath: tmdbPosterPath ?? this.tmdbPosterPath,
      tmdbBackdropPath: tmdbBackdropPath ?? this.tmdbBackdropPath,
    );
  }
}

/// Full manifest envelope — supports both GitHub (posts/total/last_updated)
/// and internal cache (items/total_count/generated_at) formats.
class Manifest {
  final List<ManifestItem> items;
  final String? generatedAt;
  final String? version;
  final int? totalCount;

  Manifest({
    required this.items,
    this.generatedAt,
    this.version,
    this.totalCount,
  });

  factory Manifest.fromJson(Map<String, dynamic> json) {
    // Support both GitHub format (posts) and cache format (items)
    final rawList = (json['items'] ?? json['posts']) as List<dynamic>?;

    return Manifest(
      items: rawList
              ?.map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      generatedAt: (json['generated_at'] ?? json['last_updated'])?.toString(),
      version: json['version']?.toString(),
      totalCount: ManifestItem._safeInt(json['total_count'] ?? json['total']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'items': items.map((e) => e.toJson()).toList(),
      'generated_at': generatedAt,
      'version': version,
      'total_count': totalCount,
    };
  }
}

