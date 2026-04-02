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
  final String? overview;
  final String? tagline;
  final int? runtime;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;
  final String? status;
  final String? imdbId;
  final List<String> language;
  final String? result;

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
    this.overview,
    this.tagline,
    this.runtime,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.status,
    this.imdbId,
    this.language = const [],
    this.result,
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

  factory ManifestItem.fromJson(Map<String, dynamic> json) {
    return ManifestItem(
      id: _safeInt(json['id']) ?? 0,
      mediaType: (json['media_type'] ?? json['type'] ?? 'movie').toString(),
      title: (json['title'] ?? '').toString(),
      posterUrl: (json['poster_url'] ?? json['poster'])?.toString(),
      backdropUrl: (json['backdrop_url'] ?? json['backdrop'])?.toString(),
      logoUrl: json['logo_url']?.toString(),
      hoverImageUrl: json['hover_image_url']?.toString(),
      voteAverage: _safeDouble(json['vote_average']),
      voteCount: _safeInt(json['vote_count']) ?? 0,
      releaseYear: _safeInt(json['release_year'] ?? json['year']),
      originalLanguage: json['original_language']?.toString(),
      originCountry: (json['origin_country'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      genreIds: (json['genre_ids'] as List<dynamic>?)
              ?.map((e) => _safeInt(e) ?? 0)
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
      'overview': overview,
      'tagline': tagline,
      'runtime': runtime,
      'number_of_seasons': numberOfSeasons,
      'number_of_episodes': numberOfEpisodes,
      'status': status,
      'imdb_id': imdbId,
      'language': language,
      'result': result,
    };
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

