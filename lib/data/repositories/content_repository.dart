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

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN FETCH: TMDB-first + DB-override merge
  // ═══════════════════════════════════════════════════════════════════════════
  Future<ContentDetail?> fetchContentDetail(int tmdbId,
      {String mediaType = 'movie'}) async {
    try {
      final isTv = mediaType.toLowerCase() == 'tv' ||
          mediaType.toLowerCase() == 'series' ||
          mediaType.toLowerCase() == 'tv series';
      final resolvedMediaType = isTv ? 'tv' : 'movie';

      // Step 1: Parallel fetch TMDB + GitHub entry
      final futures = await Future.wait([
        isTv
            ? TmdbClient.instance.getTvDetails(tmdbId)
            : TmdbClient.instance.getMovieDetails(tmdbId),
        _fetchGitHubDetail(tmdbId, resolvedMediaType),
      ]);

      final tmdbDetails = futures[0] as Map<String, dynamic>?;
      final githubEntry = futures[1] as Map<String, dynamic>?;

      // If both are null, nothing to show
      if (tmdbDetails == null && githubEntry == null) return null;

      // Step 2: Build ContentDetail with merge strategy
      String title;
      String? overview, posterUrl, backdropUrl, logoUrl, tagline, imdbId;
      double voteAverage;
      int? voteCount, runtime, numberOfSeasons, numberOfEpisodes, releaseYear;
      String? status;
      List<String> genres;
      List<CastMember> castMembers;

      // Base from TMDB
      if (tmdbDetails != null) {
        title = tmdbDetails['title']?.toString() ??
            tmdbDetails['name']?.toString() ??
            'Unknown';
        overview = tmdbDetails['overview']?.toString();
        posterUrl = TmdbClient.posterUrl(tmdbDetails['poster_path']?.toString());
        backdropUrl =
            TmdbClient.backdropUrl(tmdbDetails['backdrop_path']?.toString());
        logoUrl = _extractTmdbLogo(tmdbDetails);
        tagline = tmdbDetails['tagline']?.toString();
        voteAverage = (tmdbDetails['vote_average'] as num?)?.toDouble() ?? 0.0;
        voteCount = (tmdbDetails['vote_count'] as num?)?.toInt();
        runtime = (tmdbDetails['runtime'] as num?)?.toInt();
        numberOfSeasons = (tmdbDetails['number_of_seasons'] as num?)?.toInt();
        numberOfEpisodes = (tmdbDetails['number_of_episodes'] as num?)?.toInt();
        status = tmdbDetails['status']?.toString();
        imdbId = tmdbDetails['imdb_id']?.toString();
        genres = _parseGenres(tmdbDetails['genres']);
        castMembers = _parseTmdbCredits(tmdbDetails);

        final dateStr = tmdbDetails['release_date']?.toString() ??
            tmdbDetails['first_air_date']?.toString();
        if (dateStr != null && dateStr.length >= 4) {
          releaseYear = int.tryParse(dateStr.substring(0, 4));
        }
      } else {
        // Fallback: GitHub-only
        title = githubEntry?['title']?.toString() ?? 'Unknown';
        overview = githubEntry?['overview']?.toString();
        posterUrl = githubEntry?['poster']?.toString();
        backdropUrl = githubEntry?['backdrop']?.toString();
        logoUrl = githubEntry?['logo_url']?.toString();
        tagline = githubEntry?['tagline']?.toString();
        voteAverage = _safeDouble(githubEntry?['vote_average']);
        voteCount = _safeInt(githubEntry?['vote_count']);
        runtime = _safeInt(githubEntry?['runtime']);
        numberOfSeasons = _safeInt(githubEntry?['number_of_seasons']);
        numberOfEpisodes = _safeInt(githubEntry?['number_of_episodes']);
        status = githubEntry?['status']?.toString();
        imdbId = githubEntry?['imdb_id']?.toString();
        genres = _parseGenres(githubEntry?['genres']);
        castMembers = _parseCastData(githubEntry?['cast_data']);
        releaseYear = int.tryParse(githubEntry?['year']?.toString() ?? '');
      }

      // Step 3: Extract links from GitHub (Movies)
      String? watchLink, downloadLink;
      if (!isTv && githubEntry != null) {
        final rawWatch = githubEntry['watch'] ??
            githubEntry['watch_link'] ??
            githubEntry['play_url'];
        if (rawWatch != null) {
          watchLink = extractValidEmbedUrl(rawWatch.toString());
        }
        final rawDownload =
            githubEntry['download_link'] ?? githubEntry['download_url'];
        if (rawDownload != null) {
          downloadLink = extractValidDownloadUrl(rawDownload.toString());
        }
        // Fallback: use watch link as download link if no dedicated download
        downloadLink ??= watchLink;
      }

      // Step 4: TMDB seasons metadata
      List<TmdbSeason>? tmdbSeasons;
      if (isTv && tmdbDetails != null) {
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

      // Fix empty TMDB image URLs
      if (posterUrl != null && posterUrl.isEmpty) posterUrl = null;
      if (backdropUrl != null && backdropUrl.isEmpty) backdropUrl = null;
      if (logoUrl != null && logoUrl.isEmpty) logoUrl = null;

      return ContentDetail(
        id: tmdbId,
        title: title,
        description: overview,
        overview: overview,
        mediaType: resolvedMediaType,
        voteAverage: voteAverage,
        voteCount: voteCount,
        posterUrl: posterUrl,
        backdropUrl: backdropUrl,
        logoUrl: logoUrl,
        releaseYear: releaseYear,
        genres: genres.isNotEmpty ? genres : null,
        castMembers: castMembers,
        tagline: tagline,
        runtime: runtime,
        numberOfSeasons: numberOfSeasons,
        numberOfEpisodes: numberOfEpisodes,
        status: status,
        imdbId: imdbId,
        watchLink: watchLink,
        downloadLink: downloadLink,
        tmdbSeasons: tmdbSeasons,
        tmdbLogoUrl: logoUrl,
        // Carry GitHub entry for episodes fetch logic
        seasonsData: isTv ? _parseSeasonsFromGithub(githubEntry) : null,
      );
    } catch (e, stack) {
      dev.log('[ContentRepo] fetchContentDetail error: $e', stackTrace: stack);
      return null;
    }
  }

  /// Internal helper to fetch from GitHub with fallback
  Future<Map<String, dynamic>?> _fetchGitHubDetail(
      int id, String type) async {
    final baseUrl = '${Env.githubRawBaseUrl}/streaming_links';
    
    // 1. Try Admin version
    final adminUrl = Uri.parse('$baseUrl/admin_${type}_$id.json');
    try {
      final res = await http.get(adminUrl);
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}

    // 2. Try Normal version
    final normalUrl = Uri.parse('$baseUrl/normal_${type}_$id.json');
    try {
      final res = await http.get(normalUrl);
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}

    return null;
  }

  /// Internal helper to extract season links from GitHub TV JSON
  Map<String, List<String>> _parseSeasonsFromGithub(Map<String, dynamic>? githubEntry) {
    if (githubEntry == null || githubEntry['seasons'] == null) return {};
    
    final Map<String, List<String>> seasons = {};
    final seasonsList = githubEntry['seasons'] as List;
    
    for (final s in seasonsList) {
      final seasonNum = s['season_number'];
      if (seasonNum == null) continue;
      
      final episodes = s['episodes'] as List?;
      if (episodes == null) continue;
      
      final links = episodes
          .map((e) => e['watch']?.toString() ?? '')
          .toList();
      
      seasons['season_$seasonNum'] = links;
    }
    
    return seasons;
  }



  // ═══════════════════════════════════════════════════════════════════════════
  // EPISODES FETCH: TMDB metadata + GitHub watch links merge
  // ═══════════════════════════════════════════════════════════════════════════
  Future<List<EpisodeData>> fetchEpisodes(
      String entryId, int seasonNumber,
      {Map<String, List<String>>? seasonsData}) async {
    try {
      final tmdbId = int.tryParse(entryId) ?? 0;

      // 1. Get GitHub watch links for this season
      final seasonKey = 'season_$seasonNumber';
      final githubLinks = seasonsData?[seasonKey] ?? [];

      // 2. Fetch TMDB season data for metadata (titles, overviews, thumbnails)
      final tmdbSeasonDetails = await TmdbClient.instance.getSeasonDetails(tmdbId, seasonNumber);

      // 3. Parse TMDB episodes
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
            );
          }).toList();
        }
      }

      // 4. Merge GitHub watch links into TMDB episodes
      if (githubLinks.isNotEmpty) {
        if (episodes.isEmpty) {
          // No TMDB data — generate placeholder episodes from GitHub links
          episodes = List.generate(githubLinks.length, (i) {
            final rawLink = githubLinks[i];
            final watchUrl = extractValidEmbedUrl(rawLink);
            return EpisodeData(
              episodeNumber: i + 1,
              title: 'Episode ${i + 1}',
              playLink: watchUrl,
              downloadLink: watchUrl,
            );
          });
        } else {
          // Merge links into existing TMDB episodes
          for (int i = 0; i < episodes.length; i++) {
            if (i < githubLinks.length) {
              final rawLink = githubLinks[i];
              final watchUrl = extractValidEmbedUrl(rawLink);
              if (watchUrl != null && watchUrl.isNotEmpty) {
                episodes[i] = episodes[i].copyWith(
                  playLink: watchUrl,
                  downloadLink: watchUrl,
                );
              }
            }
          }
          // If GitHub has more links than TMDB episodes, add extra episodes
          if (githubLinks.length > episodes.length) {
            for (int i = episodes.length; i < githubLinks.length; i++) {
              final rawLink = githubLinks[i];
              final watchUrl = extractValidEmbedUrl(rawLink);
              episodes.add(EpisodeData(
                episodeNumber: i + 1,
                title: 'Episode ${i + 1}',
                playLink: watchUrl,
                downloadLink: watchUrl,
              ));
            }
          }
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
}
