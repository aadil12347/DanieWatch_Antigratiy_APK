import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import '../../domain/models/content_detail.dart';
import '../../domain/models/entry.dart';
import '../../core/config/env.dart';
import '../clients/tmdb_client.dart';

class ContentRepository {
  ContentRepository._();
  static final ContentRepository instance = ContentRepository._();

  // ─── Safe Parsing Helpers ──────────────────────────────────────────────────
  static int? _safeInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double _safeDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  // ─── Suspicious Domains Filter ─────────────────────────────────────────────
  static final List<String> _suspiciousDomains = [
    'click',
    'clk',
    'ads',
    'pop',
    'banner',
    'tracker',
    'analytics',
    'doubleclick',
    'googlesyndication',
    'googleadservices',
    'adf',
    'adb',
    'traffic',
    'visit'
  ];

  static bool isSuspiciousLink(String url) {
    if (url.contains('daniewatch')) return false; // Allow our own domain names
    final lowerUrl = url.toLowerCase();
    for (final domain in _suspiciousDomains) {
      if (lowerUrl.contains(domain)) return true;
    }
    return false;
  }

  static String? extractValidEmbedUrl(String iframeString) {
    if (!iframeString.contains('<iframe')) {
      if (isSuspiciousLink(iframeString)) return null;
      return iframeString;
    }
    final srcMatch = RegExp(r'src="([^"]+)"').firstMatch(iframeString);
    if (srcMatch != null) {
      final embedUrl = srcMatch.group(1);
      if (embedUrl != null && !isSuspiciousLink(embedUrl)) return embedUrl;
    }
    return null;
  }

  static String? extractValidDownloadUrl(String url) {
    if (isSuspiciousLink(url)) return null;
    if (url.contains('<iframe')) return null;
    return url;
  }

  // ─── Detect Active Links ───────────────────────────────────────────────────
  /// Check if content JSON has any non-empty watch/download links
  static bool _detectActiveLinks(Map<String, dynamic>? content, String type) {
    if (content == null) return false;

    if (type == 'movie') {
      final watchLink = (content['watch_link'] ??
                  content['play_url'] ??
                  content['stream_url'])
              ?.toString() ??
          '';
      final downloadLink =
          (content['download_link'] ?? content['download_url'])?.toString() ??
              '';
      return watchLink.isNotEmpty || downloadLink.isNotEmpty;
    }

    // Series: check all season_X keys
    for (final key in content.keys) {
      if (!key.startsWith('season_')) continue;
      final seasonData = content[key] as Map<String, dynamic>?;
      if (seasonData == null) continue;
      final watchLinks = seasonData['watch_links'] as List?;
      final downloadLinks = seasonData['download_links'] as List?;
      final hasWatch =
          watchLinks != null && watchLinks.any((l) => l.toString().isNotEmpty);
      final hasDownload = downloadLinks != null &&
          downloadLinks.any((l) => l.toString().isNotEmpty);
      if (hasWatch || hasDownload) return true;
    }
    return false;
  }

  // ─── Extract Season Links ──────────────────────────────────────────────────
  static ({List<String> watchLinks, List<String> downloadLinks})
      _extractSeasonLinks(
    dynamic content,
    int season,
  ) {
    if (content == null) return (watchLinks: [], downloadLinks: []);

    Map<String, dynamic> parsedContent;
    if (content is String) {
      try {
        parsedContent = jsonDecode(content) as Map<String, dynamic>;
      } catch (e) {
        return (watchLinks: [], downloadLinks: []);
      }
    } else if (content is Map<String, dynamic>) {
      parsedContent = content;
    } else if (content is Map) {
      parsedContent = Map<String, dynamic>.from(content);
    } else {
      return (watchLinks: [], downloadLinks: []);
    }

    final seasonKey = 'season_$season';
    final seasonData = parsedContent[seasonKey] as Map<String, dynamic>? ??
        parsedContent[seasonKey] as Map?;

    if (seasonData == null) {
      return (watchLinks: [], downloadLinks: []);
    }

    final watchLinks = ((seasonData['watch_links'] as List?) ??
                (seasonData['play_urls'] as List?))
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final downloadLinks = ((seasonData['download_links'] as List?) ??
                (seasonData['download_urls'] as List?))
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return (watchLinks: watchLinks, downloadLinks: downloadLinks);
  }

  // ─── Parse Genres ──────────────────────────────────────────────────────────
  static List<String> _parseGenres(dynamic genresData) {
    if (genresData == null) return [];
    if (genresData is List) {
      return genresData
          .map((e) {
            if (e is Map) return e['name']?.toString() ?? e.toString();
            return e.toString();
          })
          .where((g) => g.isNotEmpty)
          .toList();
    }
    if (genresData is String) {
      try {
        final decoded = jsonDecode(genresData);
        if (decoded is List) return _parseGenres(decoded);
      } catch (_) {}
      return genresData
          .split(',')
          .map((e) => e.trim())
          .where((g) => g.isNotEmpty)
          .toList();
    }
    return [];
  }

  // ─── Parse Cast ────────────────────────────────────────────────────────────
  static List<CastMember> _parseCastData(dynamic castData) {
    if (castData == null) return [];
    dynamic data = castData;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        return [];
      }
    }
    if (data is List) {
      return data.map((e) {
        if (e is Map<String, dynamic>) return CastMember.fromJson(e);
        return CastMember(id: 0, name: e.toString());
      }).toList();
    }
    return [];
  }

  // ─── Parse Cast from TMDB Credits ──────────────────────────────────────────
  static List<CastMember> _parseTmdbCredits(Map<String, dynamic>? tmdbDetails) {
    if (tmdbDetails == null) return [];
    final credits = tmdbDetails['credits'] as Map<String, dynamic>?;
    if (credits == null) return [];
    final cast = credits['cast'] as List?;
    if (cast == null) return [];
    return cast.take(20).map((c) {
      final m = c as Map<String, dynamic>;
      return CastMember(
        id: m['id'] as int? ?? 0,
        name: m['name']?.toString() ?? '',
        character: m['character']?.toString(),
        profilePath: m['profile_path']?.toString(),
      );
    }).toList();
  }

  // ─── TMDB Logo Extraction ──────────────────────────────────────────────────
  static String? _extractTmdbLogo(Map<String, dynamic>? tmdbDetails) {
    if (tmdbDetails == null) return null;
    final images = tmdbDetails['images'] as Map<String, dynamic>?;
    if (images == null) return null;
    final logos = images['logos'] as List?;
    if (logos == null || logos.isEmpty) return null;
    // Prefer English logos
    final englishLogo = logos.firstWhere(
      (l) => (l['iso_639_1'] ?? '') == 'en',
      orElse: () => logos.first,
    );
    return TmdbClient.logoUrl(englishLogo['file_path'] as String?);
  }

  // ─── TMDB Trailer Extraction ───────────────────────────────────────────────
  static String? _extractTmdbTrailer(Map<String, dynamic>? tmdbDetails) {
    if (tmdbDetails == null) return null;
    final videos = tmdbDetails['videos'] as Map<String, dynamic>?;
    if (videos == null) return null;
    final results = videos['results'] as List?;
    if (results == null || results.isEmpty) return null;
    // Prefer official YouTube trailers
    final trailer = results.firstWhere(
      (v) => v['type'] == 'Trailer' && v['site'] == 'YouTube' && (v['official'] == true),
      orElse: () => results.firstWhere(
        (v) => v['type'] == 'Trailer' && v['site'] == 'YouTube',
        orElse: () => results.firstWhere(
          (v) => v['site'] == 'YouTube',
          orElse: () => <String, dynamic>{},
        ),
      ),
    );
    final key = trailer['key']?.toString();
    if (key == null || key.isEmpty) return null;
    return 'https://www.youtube.com/watch?v=$key';
  }

  // ─── Skip .avif poster URLs ────────────────────────────────────────────────
  static String? _sanitizePosterForAvif(String? url, String? tmdbPath, {String size = 'w342'}) {
    if (url != null && url.isNotEmpty && !url.toLowerCase().endsWith('.avif')) {
      return url;
    }
    if (tmdbPath != null && tmdbPath.isNotEmpty) {
      return TmdbClient.imageUrl(tmdbPath, size: size);
    }
    return url;
  }

  Future<ContentDetail?> fetchContentDetail(int tmdbId,
      {String mediaType = 'movie'}) async {
    try {
      final isTv = mediaType.toLowerCase() == 'tv' ||
          mediaType.toLowerCase() == 'series' ||
          mediaType.toLowerCase() == 'tv series';
      final resolvedMediaType = isTv ? 'tv' : 'movie';

      // ALWAYS fetch TMDB for everything
      Map<String, dynamic>? tmdbDetails;
      tmdbDetails = isTv
          ? await TmdbClient.instance.getTvDetails(tmdbId)
          : await TmdbClient.instance.getMovieDetails(tmdbId);

      if (tmdbDetails == null) return null;

      final title = tmdbDetails['title']?.toString() ??
          tmdbDetails['name']?.toString() ?? 'Unknown';
      final overview = tmdbDetails['overview']?.toString();
      final tmdbPosterUrl = TmdbClient.posterUrl(tmdbDetails['poster_path']?.toString());
      final tmdbBackdropUrl = TmdbClient.backdropUrl(tmdbDetails['backdrop_path']?.toString());
      final tmdbLogoUrl = _extractTmdbLogo(tmdbDetails);
      final trailerUrl = _extractTmdbTrailer(tmdbDetails);
      final tagline = tmdbDetails['tagline']?.toString();
      final voteAverage = (tmdbDetails['vote_average'] as num?)?.toDouble() ?? 0.0;
      final voteCount = (tmdbDetails['vote_count'] as num?)?.toInt();
      final runtime = (tmdbDetails['runtime'] as num?)?.toInt();
      final numberOfSeasons = (tmdbDetails['number_of_seasons'] as num?)?.toInt();
      final numberOfEpisodes = (tmdbDetails['number_of_episodes'] as num?)?.toInt();
      final status = tmdbDetails['status']?.toString();
      final imdbId = tmdbDetails['imdb_id']?.toString();
      final genres = _parseGenres(tmdbDetails['genres']);
      final castMembers = _parseTmdbCredits(tmdbDetails);

      int? releaseYear;
      final dateStr = tmdbDetails['release_date']?.toString() ??
          tmdbDetails['first_air_date']?.toString();
      if (dateStr != null && dateStr.length >= 4) {
        releaseYear = int.tryParse(dateStr.substring(0, 4));
      }

      List<TmdbSeason>? tmdbSeasons;
      if (isTv) {
        final seasons = tmdbDetails['seasons'] as List?;
        if (seasons != null) {
          tmdbSeasons = seasons
              .where((s) {
                final sn = s['season_number'];
                if (sn == null) return false;
                final num = sn is int ? sn : int.tryParse(sn.toString());
                return num != null && num > 0;
              })
              .map((s) => TmdbSeason.fromJson(s as Map<String, dynamic>))
              .toList();
        }
      }

      return ContentDetail(
        id: tmdbId,
        title: title,
        description: overview,
        overview: overview,
        mediaType: resolvedMediaType,
        voteAverage: voteAverage,
        voteCount: voteCount,
        posterUrl: tmdbPosterUrl.isNotEmpty ? tmdbPosterUrl : null,
        backdropUrl: tmdbBackdropUrl.isNotEmpty ? tmdbBackdropUrl : null,
        logoUrl: tmdbLogoUrl,
        trailerUrl: trailerUrl,
        releaseYear: releaseYear,
        genres: genres.isNotEmpty ? genres : null,
        castMembers: castMembers,
        tagline: tagline,
        runtime: runtime,
        numberOfSeasons: numberOfSeasons,
        numberOfEpisodes: numberOfEpisodes,
        status: status,
        imdbId: imdbId,
        watchLink: '', // Extracted dynamically by VideasyExtractorService
        downloadLink: '',
        tmdbSeasons: tmdbSeasons,
        tmdbLogoUrl: tmdbLogoUrl,
        isAdmin: false,
        seasonsData: null,
      );
    } catch (e, stack) {
      dev.log('[ContentRepo] fetchContentDetail error: $e', stackTrace: stack);
      return null;
    }
  }




  Future<List<EpisodeData>> fetchEpisodes(
      String entryId, int seasonNumber,
      {Map<String, List<String>>? seasonsData,
      bool isAdmin = false}) async {
    try {
      final tmdbId = int.tryParse(entryId) ?? 0;
      final tmdbSeasonDetails = await TmdbClient.instance.getSeasonDetails(tmdbId, seasonNumber);

      List<EpisodeData> episodes = [];
      if (tmdbSeasonDetails != null) {
        final eps = tmdbSeasonDetails['episodes'] as List?;
        if (eps != null) {
          episodes = eps.map((e) {
            final t = TmdbEpisode.fromJson(e as Map<String, dynamic>);
            return EpisodeData(
              episodeNumber: t.episodeNumber,
              title: t.name,
              description: t.overview,
              thumbnailUrl: t.stillPath != null ? TmdbClient.thumbUrl(t.stillPath!) : null,
              runtime: t.runtime,
              airDate: t.airDate,
              voteAverage: t.voteAverage,
              playLink: '', // Dynamic via Videasy
              downloadLink: '',
            );
          }).toList();
        }
      }

      return episodes;
    } catch (e, stack) {
      dev.log('[ContentRepo] fetchEpisodes error: $e', stackTrace: stack);
      return [];
    }
  }

  // ─── Fetch Similar Content ─────────────────────────────────────────────────
  Future<List<SimilarItem>> fetchSimilar(int tmdbId, String mediaType) async {
    try {
      final isTv = mediaType.toLowerCase() == 'tv' ||
          mediaType.toLowerCase() == 'series';
      final results = isTv
          ? await TmdbClient.instance.getSimilarTv(tmdbId)
          : await TmdbClient.instance.getSimilarMovies(tmdbId);
      return results
          .map((r) => SimilarItem.fromTmdbJson(r, isTv ? 'tv' : 'movie'))
          .toList();
    } catch (e) {
      dev.log('[ContentRepo] fetchSimilar error: $e');
      return [];
    }
  }

  // ─── Fetch Reviews ─────────────────────────────────────────────────────────
  Future<List<ReviewItem>> fetchReviews(int tmdbId, String mediaType) async {
    try {
      final results = await TmdbClient.instance.getReviews(tmdbId, mediaType);
      return results.map((r) => ReviewItem.fromTmdbJson(r)).toList();
    } catch (e) {
      dev.log('[ContentRepo] fetchReviews error: $e');
      return [];
    }
  }
}
