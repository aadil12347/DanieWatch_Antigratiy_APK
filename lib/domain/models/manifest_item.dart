/// Represents a single item in the Supabase db_manifest_v1.json.
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
  });

  factory ManifestItem.fromJson(Map<String, dynamic> json) {
    return ManifestItem(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.parse(json['id'].toString()),
      mediaType: json['media_type'].toString(),
      title: json['title'].toString(),
      posterUrl: json['poster_url']?.toString(),
      backdropUrl: json['backdrop_url']?.toString(),
      logoUrl: json['logo_url']?.toString(),
      hoverImageUrl: json['hover_image_url']?.toString(),
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: (json['vote_count'] as num?)?.toInt() ?? 0,
      releaseYear: (json['release_year'] as num?)?.toInt() ??
          int.tryParse(json['release_year']?.toString() ?? ''),
      originalLanguage: json['original_language']?.toString(),
      originCountry: (json['origin_country'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      genreIds: (json['genre_ids'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
      overview: json['overview']?.toString(),
      tagline: json['tagline']?.toString(),
      runtime: (json['runtime'] as num?)?.toInt() ??
          int.tryParse(json['runtime']?.toString() ?? ''),
      numberOfSeasons: (json['number_of_seasons'] as num?)?.toInt() ??
          int.tryParse(json['number_of_seasons']?.toString() ?? ''),
      numberOfEpisodes: (json['number_of_episodes'] as num?)?.toInt() ??
          int.tryParse(json['number_of_episodes']?.toString() ?? ''),
      status: json['status']?.toString(),
      imdbId: json['imdb_id']?.toString(),
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
    };
  }
}

/// Full manifest envelope from Supabase Storage
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
    return Manifest(
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      generatedAt: json['generated_at'] as String?,
      version: json['version']?.toString(),
      totalCount: json['total_count'] as int?,
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
