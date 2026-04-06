import 'dart:convert';
import '../models/entry.dart';

/// Safe int parser — handles both int/num and String values from JSON
int? _safeInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

/// Safe double parser — handles both num and String values from JSON
double? _safeDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

class ContentDetail {
  final int id;
  final String title;
  final String? description;
  final String? overview;
  final String mediaType;
  final double voteAverage;
  final int? voteCount;
  final String? posterUrl;
  final String? backdropUrl;
  final String? logoUrl;
  final String? releaseDate;
  final int? releaseYear;
  final List<int> genreIds;
  final List<String>? genres;
  final List<CastMember> castMembers;
  final String? tagline;
  final int? runtime;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;
  final String? status;
  final String? imdbId;
  final String? playUrl;
  final String? downloadUrl;
  final String? trailerUrl;
  final List<EpisodeData>? episodesData;
  final String? result;
  final String? language;

  // Supabase entries table fields
  final String? watchLink;
  final String? downloadLink;
  final Map<String, List<String>>? seasonsData;
  final Map<String, List<EpisodeData>>? metadataEpisodes;

  // TMDB enriched data
  final List<TmdbSeason>? tmdbSeasons;
  final String? tmdbLogoUrl;

  // Similar items
  final List<SimilarItem>? similarItems;

  // Admin flag — when true, all data comes from GitHub, not TMDB
  final bool isAdmin;

  ContentDetail({
    required this.id,
    required this.title,
    this.description,
    this.overview,
    required this.mediaType,
    this.voteAverage = 0.0,
    this.voteCount,
    this.posterUrl,
    this.backdropUrl,
    this.logoUrl,
    this.releaseDate,
    this.releaseYear,
    this.genreIds = const [],
    this.genres,
    this.castMembers = const [],
    this.tagline,
    this.runtime,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.status,
    this.imdbId,
    this.playUrl,
    this.downloadUrl,
    this.trailerUrl,
    this.episodesData,
    this.watchLink,
    this.downloadLink,
    this.seasonsData,
    this.metadataEpisodes,
    this.tmdbSeasons,
    this.tmdbLogoUrl,
    this.similarItems,
    this.result,
    this.language,
    this.isAdmin = false,
  });

  ContentDetail copyWith({
    int? id,
    String? title,
    String? description,
    String? overview,
    String? mediaType,
    double? voteAverage,
    int? voteCount,
    String? posterUrl,
    String? backdropUrl,
    String? logoUrl,
    String? releaseDate,
    int? releaseYear,
    List<int>? genreIds,
    List<String>? genres,
    List<CastMember>? castMembers,
    String? tagline,
    int? runtime,
    int? numberOfSeasons,
    int? numberOfEpisodes,
    String? status,
    String? imdbId,
    String? playUrl,
    String? downloadUrl,
    String? trailerUrl,
    List<EpisodeData>? episodesData,
    String? watchLink,
    String? downloadLink,
    Map<String, List<String>>? seasonsData,
    Map<String, List<EpisodeData>>? metadataEpisodes,
    List<TmdbSeason>? tmdbSeasons,
    String? tmdbLogoUrl,
    List<SimilarItem>? similarItems,
    String? result,
    String? language,
  }) {
    return ContentDetail(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      overview: overview ?? this.overview,
      mediaType: mediaType ?? this.mediaType,
      voteAverage: voteAverage ?? this.voteAverage,
      voteCount: voteCount ?? this.voteCount,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      logoUrl: logoUrl ?? this.logoUrl,
      releaseDate: releaseDate ?? this.releaseDate,
      releaseYear: releaseYear ?? this.releaseYear,
      genreIds: genreIds ?? this.genreIds,
      genres: genres ?? this.genres,
      castMembers: castMembers ?? this.castMembers,
      tagline: tagline ?? this.tagline,
      runtime: runtime ?? this.runtime,
      numberOfSeasons: numberOfSeasons ?? this.numberOfSeasons,
      numberOfEpisodes: numberOfEpisodes ?? this.numberOfEpisodes,
      status: status ?? this.status,
      imdbId: imdbId ?? this.imdbId,
      playUrl: playUrl ?? this.playUrl,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      trailerUrl: trailerUrl ?? this.trailerUrl,
      episodesData: episodesData ?? this.episodesData,
      watchLink: watchLink ?? this.watchLink,
      downloadLink: downloadLink ?? this.downloadLink,
      seasonsData: seasonsData ?? this.seasonsData,
      metadataEpisodes: metadataEpisodes ?? this.metadataEpisodes,
      tmdbSeasons: tmdbSeasons ?? this.tmdbSeasons,
      tmdbLogoUrl: tmdbLogoUrl ?? this.tmdbLogoUrl,
      similarItems: similarItems ?? this.similarItems,
      result: result ?? this.result,
      language: language ?? this.language,
    );
  }

  factory ContentDetail.fromJson(Map<String, dynamic> json) {
    List<EpisodeData>? episodes;

    if (json['episodes_data'] != null) {
      if (json['episodes_data'] is String) {
        try {
          final decoded = jsonDecode(json['episodes_data'] as String);
          if (decoded is List) {
            episodes = decoded.map((e) => EpisodeData.fromJson(e)).toList();
          }
        } catch (_) {}
      } else if (json['episodes_data'] is List) {
        episodes = (json['episodes_data'] as List)
            .map((e) => EpisodeData.fromJson(e))
            .toList();
      }
    }

    List<String>? genresList;
    if (json['genres'] != null) {
      if (json['genres'] is String) {
        genresList =
            (json['genres'] as String).split(',').map((e) => e.trim()).toList();
      } else if (json['genres'] is List) {
        genresList = (json['genres'] as List).map((e) {
          if (e is Map) return e['name']?.toString() ?? e.toString();
          return e.toString();
        }).toList();
      }
    }

    List<int> genreIdsList = [];
    if (json['genre_ids'] != null) {
      if (json['genre_ids'] is String) {
        try {
          final decoded = jsonDecode(json['genre_ids'] as String);
          if (decoded is List) {
            genreIdsList =
                decoded.map((e) => int.tryParse(e.toString()) ?? 0).toList();
          }
        } catch (_) {
          genreIdsList = (json['genre_ids'] as String)
              .split(',')
              .map((e) => int.tryParse(e.trim()) ?? 0)
              .toList();
        }
      } else if (json['genre_ids'] is List) {
        genreIdsList = (json['genre_ids'] as List)
            .map((e) => int.tryParse(e.toString()) ?? 0)
            .toList();
      }
    }

    int? year;
    if (json['release_date'] != null) {
      final dateStr = json['release_date'].toString();
      if (dateStr.length >= 4) {
        year = int.tryParse(dateStr.substring(0, 4));
      }
    } else if (json['first_air_date'] != null) {
      final dateStr = json['first_air_date'].toString();
      if (dateStr.length >= 4) {
        year = int.tryParse(dateStr.substring(0, 4));
      }
    } else if (json['release_year'] != null) {
      year = int.tryParse(json['release_year'].toString());
    }

    // Parse cast_data as List<CastMember>
    List<CastMember> castMembers = [];
    if (json['cast_data'] != null) {
      dynamic castData = json['cast_data'];
      if (castData is String) {
        try {
          castData = jsonDecode(castData);
        } catch (_) {}
      }
      if (castData is List) {
        castMembers = castData.map((e) {
          if (e is Map<String, dynamic>) return CastMember.fromJson(e);
          return CastMember(id: 0, name: e.toString());
        }).toList();
      }
    }

    return ContentDetail(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse(json['id'].toString()) ?? 0,
      title: json['title']?.toString() ??
          json['name']?.toString() ??
          'Unknown Title',
      description:
          json['description']?.toString() ?? json['overview']?.toString(),
      overview: json['overview']?.toString(),
      mediaType: json['media_type']?.toString() ?? 'movie',
      voteAverage: _safeDouble(json['vote_average']) ?? 0.0,
      voteCount: _safeInt(json['vote_count']),
      posterUrl:
          json['poster_url']?.toString() ?? json['poster_path']?.toString(),
      backdropUrl:
          json['backdrop_url']?.toString() ?? json['backdrop_path']?.toString(),
      logoUrl: json['logo_url']?.toString(),
      releaseDate: json['release_date']?.toString() ??
          json['first_air_date']?.toString(),
      releaseYear: year,
      genreIds: genreIdsList,
      genres: genresList,
      castMembers: castMembers,
      tagline: json['tagline']?.toString(),
      runtime: _safeInt(json['runtime']),
      numberOfSeasons: _safeInt(json['number_of_seasons']),
      numberOfEpisodes: _safeInt(json['number_of_episodes']),
      status: json['status']?.toString(),
      imdbId: json['imdb_id']?.toString(),
      playUrl: json['play_url']?.toString(),
      downloadUrl: json['download_url']?.toString(),
      trailerUrl: json['trailer_url']?.toString(),
      episodesData: episodes,
      result: (json['result'] ?? json['quality'])?.toString(),
      language: json['language'] != null
          ? (json['language'] is List
              ? (json['language'] as List).join(', ')
              : json['language'].toString())
          : null,
      isAdmin: json['is_admin'] == true,
    );
  }

  bool get isTv =>
      mediaType.toLowerCase() == 'tv' ||
      mediaType.toLowerCase() == 'tv series' ||
      mediaType.toLowerCase() == 'series';
  bool get isMovie => mediaType.toLowerCase() == 'movie';

  String get displayYear =>
      releaseYear?.toString() ?? (releaseDate?.substring(0, 4) ?? '');

  String get displayGenres => genres?.join(', ') ?? '';

  String? get primaryWatchLink => watchLink ?? playUrl;
  String? get primaryDownloadLink => downloadLink ?? downloadUrl;

  bool get hasSeasonsData => seasonsData != null && seasonsData!.isNotEmpty;

  bool get hasLogo =>
      (logoUrl != null && logoUrl!.isNotEmpty) ||
      (tmdbLogoUrl != null && tmdbLogoUrl!.isNotEmpty);

  String? get displayLogoUrl => tmdbLogoUrl ?? logoUrl;

  List<int> get seasonNumbers {
    // Check content JSON for season_X keys
    final Set<int> seasons = {};

    if (metadataEpisodes != null) {
      for (final key in metadataEpisodes!.keys) {
        final num = int.tryParse(key.replaceAll('season_', ''));
        if (num != null) seasons.add(num);
      }
    }
    if (seasonsData != null) {
      for (final key in seasonsData!.keys) {
        final num = int.tryParse(key.replaceAll('season_', ''));
        if (num != null) seasons.add(num);
      }
    }
    if (tmdbSeasons != null) {
      for (final s in tmdbSeasons!) {
        if (s.seasonNumber > 0) seasons.add(s.seasonNumber);
      }
    }
    if (seasons.isEmpty && numberOfSeasons != null && numberOfSeasons! > 0) {
      return List.generate(numberOfSeasons!, (i) => i + 1);
    }
    final list = seasons.toList()..sort();
    return list.isEmpty ? [1] : list;
  }
}

class EpisodeData {
  final int? episodeNumber;
  final String? title;
  final String? description;
  final String? playLink;
  final String? downloadLink;
  final String? thumbnailUrl;
  final int? runtime;
  final String? airDate;
  final double? voteAverage;

  EpisodeData({
    this.episodeNumber,
    this.title,
    this.description,
    this.playLink,
    this.downloadLink,
    this.thumbnailUrl,
    this.runtime,
    this.airDate,
    this.voteAverage,
  });

  EpisodeData copyWith({
    int? episodeNumber,
    String? title,
    String? description,
    String? playLink,
    String? downloadLink,
    String? thumbnailUrl,
    int? runtime,
    String? airDate,
    double? voteAverage,
  }) {
    return EpisodeData(
      episodeNumber: episodeNumber ?? this.episodeNumber,
      title: title ?? this.title,
      description: description ?? this.description,
      playLink: playLink ?? this.playLink,
      downloadLink: downloadLink ?? this.downloadLink,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      runtime: runtime ?? this.runtime,
      airDate: airDate ?? this.airDate,
      voteAverage: voteAverage ?? this.voteAverage,
    );
  }

  factory EpisodeData.fromJson(Map<String, dynamic> json) {
    return EpisodeData(
      episodeNumber:
          _safeInt(json['episode_number']) ?? _safeInt(json['episode']),
      title: json['title']?.toString() ?? json['name']?.toString(),
      description:
          json['description']?.toString() ?? json['overview']?.toString(),
      playLink: json['play_link']?.toString() ??
          json['play_url']?.toString() ??
          json['stream_url']?.toString(),
      downloadLink:
          json['download_link']?.toString() ?? json['download_url']?.toString(),
      thumbnailUrl:
          json['thumbnail_url']?.toString() ?? json['thumbnail']?.toString(),
      runtime: _safeInt(json['runtime']),
      airDate: json['air_date']?.toString(),
      voteAverage: _safeDouble(json['vote_average']),
    );
  }

  String get displayTitle => title ?? 'Episode ${episodeNumber ?? 1}';
}

class SimilarItem {
  final int id;
  final String title;
  final String? posterPath;
  final double voteAverage;
  final String mediaType;

  SimilarItem({
    required this.id,
    required this.title,
    this.posterPath,
    this.voteAverage = 0.0,
    required this.mediaType,
  });

  factory SimilarItem.fromTmdbJson(
      Map<String, dynamic> json, String mediaType) {
    return SimilarItem(
      id: _safeInt(json['id']) ?? 0,
      title: json['title']?.toString() ?? json['name']?.toString() ?? '',
      posterPath: json['poster_path']?.toString(),
      voteAverage: _safeDouble(json['vote_average']) ?? 0.0,
      mediaType: mediaType,
    );
  }
}

class TmdbSeason {
  final int seasonNumber;
  final String? name;
  final String? overview;
  final String? posterPath;
  final int? episodeCount;
  final String? airDate;
  final List<TmdbEpisode>? episodes;

  TmdbSeason({
    required this.seasonNumber,
    this.name,
    this.overview,
    this.posterPath,
    this.episodeCount,
    this.airDate,
    this.episodes,
  });

  factory TmdbSeason.fromJson(Map<String, dynamic> json) {
    return TmdbSeason(
      seasonNumber: _safeInt(json['season_number']) ?? 0,
      name: json['name']?.toString(),
      overview: json['overview']?.toString(),
      posterPath: json['poster_path']?.toString(),
      episodeCount: _safeInt(json['episode_count']),
      airDate: json['air_date']?.toString(),
      episodes: (json['episodes'] as List?)
          ?.map((e) => TmdbEpisode.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TmdbEpisode {
  final int episodeNumber;
  final String? name;
  final String? overview;
  final String? stillPath;
  final int? runtime;
  final double? voteAverage;
  final String? airDate;

  TmdbEpisode({
    required this.episodeNumber,
    this.name,
    this.overview,
    this.stillPath,
    this.runtime,
    this.voteAverage,
    this.airDate,
  });

  factory TmdbEpisode.fromJson(Map<String, dynamic> json) {
    return TmdbEpisode(
      episodeNumber: _safeInt(json['episode_number']) ?? 0,
      name: json['name']?.toString(),
      overview: json['overview']?.toString(),
      stillPath: json['still_path']?.toString(),
      runtime: _safeInt(json['runtime']),
      voteAverage: _safeDouble(json['vote_average']),
      airDate: json['air_date']?.toString(),
    );
  }
}
