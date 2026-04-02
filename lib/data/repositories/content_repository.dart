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

      // Step 1: Fetch GitHub entry (determines admin vs normal path)
      final githubResult = await _fetchGitHubDetail(tmdbId, resolvedMediaType);
      final githubEntry = githubResult.data;
      final isAdmin = githubResult.isAdmin;

      // Step 2: ALWAYS fetch TMDB for visuals (logo, poster, backdrop, trailer)
      Map<String, dynamic>? tmdbDetails;
      tmdbDetails = isTv
          ? await TmdbClient.instance.getTvDetails(tmdbId)
          : await TmdbClient.instance.getMovieDetails(tmdbId);

      // If both are null, nothing to show
      if (tmdbDetails == null && githubEntry == null) return null;

      String title;
      String? overview, posterUrl, backdropUrl, logoUrl, tagline, imdbId, trailerUrl;
      double voteAverage;
      int? voteCount, runtime, numberOfSeasons, numberOfEpisodes, releaseYear;
      String? status;
      List<String> genres;
      List<CastMember> castMembers;
      List<TmdbSeason>? tmdbSeasons;

      // ── Always extract TMDB visuals ──
      final tmdbLogoUrl = _extractTmdbLogo(tmdbDetails);
      final tmdbTrailerUrl = _extractTmdbTrailer(tmdbDetails);
      final tmdbPosterUrl = TmdbClient.posterUrl(tmdbDetails?['poster_path']?.toString());
      final tmdbBackdropUrl = TmdbClient.backdropUrl(tmdbDetails?['backdrop_path']?.toString());

      if (isAdmin) {
        // ━━━ ADMIN PATH: TMDB for metadata + visuals, GitHub for streaming/episodes ━━━
        // Title: prefer TMDB, fallback GitHub
        title = tmdbDetails?['title']?.toString() ??
            tmdbDetails?['name']?.toString() ??
            githubEntry?['title']?.toString() ?? 'Unknown';
        // Overview: prefer TMDB, fallback GitHub
        overview = tmdbDetails?['overview']?.toString() ??
            githubEntry?['overview']?.toString();
        // Tagline: prefer TMDB, fallback GitHub
        tagline = tmdbDetails?['tagline']?.toString() ??
            githubEntry?['tagline']?.toString();
        // Vote data: prefer TMDB, fallback GitHub
        voteAverage = (tmdbDetails?['vote_average'] as num?)?.toDouble() ??
            _safeDouble(githubEntry?['vote_average']);
        voteCount = (tmdbDetails?['vote_count'] as num?)?.toInt() ??
            _safeInt(githubEntry?['vote_count']);
        // Runtime: prefer TMDB, fallback GitHub
        runtime = (tmdbDetails?['runtime'] as num?)?.toInt() ??
            _safeInt(githubEntry?['runtime']);
        // Status: prefer TMDB, fallback GitHub
        status = tmdbDetails?['status']?.toString() ??
            githubEntry?['status']?.toString();
        // IMDB ID: prefer TMDB, fallback GitHub
        imdbId = tmdbDetails?['imdb_id']?.toString() ??
            githubEntry?['imdb_id']?.toString();
        // Genres: prefer TMDB, fallback GitHub
        final tmdbGenres = _parseGenres(tmdbDetails?['genres']);
        genres = tmdbGenres.isNotEmpty ? tmdbGenres : _parseGenres(githubEntry?['genres']);
        // Cast: prefer TMDB, fallback GitHub
        final tmdbCast = tmdbDetails != null ? _parseTmdbCredits(tmdbDetails) : <CastMember>[];
        castMembers = tmdbCast.isNotEmpty ? tmdbCast : _parseCastData(githubEntry?['cast_data']);
        // Release year: prefer TMDB, fallback GitHub
        final dateStr = tmdbDetails?['release_date']?.toString() ??
            tmdbDetails?['first_air_date']?.toString();
        if (dateStr != null && dateStr.length >= 4) {
          releaseYear = int.tryParse(dateStr.substring(0, 4));
        }
        releaseYear ??= int.tryParse(githubEntry?['year']?.toString() ?? '');

        // ALWAYS use TMDB for visuals, fallback to GitHub if TMDB empty
        logoUrl = tmdbLogoUrl ?? githubEntry?['logo_url']?.toString();
        trailerUrl = tmdbTrailerUrl ?? githubEntry?['trailer_url']?.toString();
        posterUrl = tmdbPosterUrl.isNotEmpty
            ? tmdbPosterUrl
            : _sanitizePosterForAvif(githubEntry?['poster']?.toString(), null);
        backdropUrl = tmdbBackdropUrl.isNotEmpty
            ? tmdbBackdropUrl
            : githubEntry?['backdrop']?.toString();

        // Season count: prefer TMDB, fallback GitHub
        numberOfSeasons = (tmdbDetails?['number_of_seasons'] as num?)?.toInt();
        numberOfEpisodes = (tmdbDetails?['number_of_episodes'] as num?)?.toInt();

        // For admin TV: build tmdbSeasons from TMDB for display metadata,
        // but episode watch links come from GitHub (via _buildAdminEpisodes)
        if (isTv) {
          // First try TMDB seasons metadata (for poster, overview, air_date)
          final tmdbSeasonsList = tmdbDetails?['seasons'] as List?;
          if (tmdbSeasonsList != null) {
            tmdbSeasons = tmdbSeasonsList
                .where((s) {
                  final sn = s['season_number'];
                  if (sn == null) return false;
                  final num = sn is int ? sn : int.tryParse(sn.toString());
                  return num != null && num > 0;
                })
                .map((s) => TmdbSeason.fromJson(s as Map<String, dynamic>))
                .toList();
          }

          // If TMDB didn't have seasons, fall back to GitHub season structure
          if ((tmdbSeasons == null || tmdbSeasons!.isEmpty) && githubEntry != null) {
            final seasonsList = githubEntry['seasons'] as List?;
            if (seasonsList != null) {
              numberOfSeasons ??= seasonsList.length;
              int totalEps = 0;
              tmdbSeasons = seasonsList.map((s) {
                final sMap = s as Map<String, dynamic>;
                final episodes = sMap['episodes'] as List?;
                final epCount = episodes?.length ?? 0;
                totalEps += epCount;
                return TmdbSeason(
                  seasonNumber: _safeInt(sMap['season_number']) ?? 1,
                  name: sMap['name']?.toString() ?? 'Season ${_safeInt(sMap['season_number']) ?? 1}',
                  overview: sMap['overview']?.toString(),
                  posterPath: sMap['poster_path']?.toString(),
                  episodeCount: epCount,
                  airDate: sMap['air_date']?.toString(),
                );
              }).toList();
              numberOfEpisodes ??= totalEps;
            }
          }

          // Ensure episode counts from GitHub if TMDB didn't have them
          if (numberOfSeasons == null && githubEntry != null) {
            final seasonsList = githubEntry['seasons'] as List?;
            if (seasonsList != null) {
              numberOfSeasons = seasonsList.length;
              int totalEps = 0;
              for (final s in seasonsList) {
                final episodes = (s as Map<String, dynamic>)['episodes'] as List?;
                totalEps += episodes?.length ?? 0;
              }
              numberOfEpisodes ??= totalEps;
            }
          }
        }
      } else if (tmdbDetails != null) {
        // ━━━ NORMAL PATH: TMDB for metadata + visuals, GitHub for links only ━━━
        title = tmdbDetails['title']?.toString() ??
            tmdbDetails['name']?.toString() ?? 'Unknown';
        overview = tmdbDetails['overview']?.toString();
        posterUrl = tmdbPosterUrl;
        backdropUrl = tmdbBackdropUrl;
        logoUrl = tmdbLogoUrl;
        trailerUrl = tmdbTrailerUrl;
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

        // TMDB seasons for normal TV
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
      } else {
        // Fallback: GitHub-only (no TMDB available)
        title = githubEntry?['title']?.toString() ?? 'Unknown';
        overview = githubEntry?['overview']?.toString();
        posterUrl = _sanitizePosterForAvif(githubEntry?['poster']?.toString(), null);
        backdropUrl = githubEntry?['backdrop']?.toString();
        logoUrl = githubEntry?['logo_url']?.toString();
        trailerUrl = githubEntry?['trailer_url']?.toString();
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

      // Step 3: Extract watch links from GitHub (all paths)
      String? watchLink, downloadLink;
      if (!isTv && githubEntry != null) {
        final rawWatch = githubEntry['watch'] ??
            githubEntry['watch_link'] ?? githubEntry['play_url'];
        if (rawWatch != null) {
          watchLink = extractValidEmbedUrl(rawWatch.toString());
        }
        final rawDownload =
            githubEntry['download_link'] ?? githubEntry['download_url'];
        if (rawDownload != null) {
          downloadLink = extractValidDownloadUrl(rawDownload.toString());
        }
        downloadLink ??= watchLink;
      }

      // Fix empty image URLs
      if (posterUrl != null && posterUrl.isEmpty) posterUrl = null;
      if (backdropUrl != null && backdropUrl.isEmpty) backdropUrl = null;
      if (logoUrl != null && logoUrl.isEmpty) logoUrl = null;
      if (trailerUrl != null && trailerUrl.isEmpty) trailerUrl = null;

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
        watchLink: watchLink,
        downloadLink: downloadLink,
        tmdbSeasons: tmdbSeasons,
        tmdbLogoUrl: logoUrl,
        isAdmin: isAdmin,
        seasonsData: isTv ? _parseSeasonsFromGithub(githubEntry) : null,
      );
    } catch (e, stack) {
      dev.log('[ContentRepo] fetchContentDetail error: $e', stackTrace: stack);
      return null;
    }
  }

  /// Internal helper to fetch from GitHub — returns data + isAdmin flag
  Future<({Map<String, dynamic>? data, bool isAdmin})> _fetchGitHubDetail(
      int id, String type) async {
    final baseUrl = '${Env.githubRawBaseUrl}/streaming_links';
    
    // 1. Try Admin version first
    final adminUrl = Uri.parse('$baseUrl/admin_${type}_$id.json');
    try {
      final res = await http.get(adminUrl);
      if (res.statusCode == 200) {
        return (data: jsonDecode(res.body) as Map<String, dynamic>, isAdmin: true);
      }
    } catch (_) {}

    // 2. Try Normal version
    final normalUrl = Uri.parse('$baseUrl/normal_${type}_$id.json');
    try {
      final res = await http.get(normalUrl);
      if (res.statusCode == 200) {
        return (data: jsonDecode(res.body) as Map<String, dynamic>, isAdmin: false);
      }
    } catch (_) {}

    return (data: null, isAdmin: false);
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
  // EPISODES FETCH: Admin = GitHub only, Normal = TMDB + GitHub links
  // ═══════════════════════════════════════════════════════════════════════════
  Future<List<EpisodeData>> fetchEpisodes(
      String entryId, int seasonNumber,
      {Map<String, List<String>>? seasonsData,
      bool isAdmin = false}) async {
    try {
      final tmdbId = int.tryParse(entryId) ?? 0;
      final seasonKey = 'season_$seasonNumber';
      final githubLinks = seasonsData?[seasonKey] ?? [];

      // ━━━ ADMIN PATH: Build episodes entirely from GitHub data ━━━
      if (isAdmin) {
        return _buildAdminEpisodes(tmdbId, seasonNumber);
      }

      // ━━━ NORMAL PATH: TMDB metadata + GitHub watch links ━━━
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
            );
          }).toList();
        }
      }

      // Merge GitHub watch links into TMDB episodes
      if (githubLinks.isNotEmpty) {
        if (episodes.isEmpty) {
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

  /// Build episodes for admin TV shows: GitHub for links, TMDB for metadata fallback
  Future<List<EpisodeData>> _buildAdminEpisodes(int tmdbId, int seasonNumber) async {
    try {
      final githubResult = await _fetchGitHubDetail(tmdbId, 'tv');
      final githubEntry = githubResult.data;
      if (githubEntry == null) return [];

      final seasonsList = githubEntry['seasons'] as List?;
      if (seasonsList == null) return [];

      // Find the matching season
      final seasonData = seasonsList.firstWhere(
        (s) => (_safeInt(s['season_number']) ?? 0) == seasonNumber,
        orElse: () => null,
      );
      if (seasonData == null) return [];

      final episodes = seasonData['episodes'] as List?;
      if (episodes == null) return [];

      // Fetch TMDB season details for metadata enrichment
      Map<int, Map<String, dynamic>> tmdbEpMap = {};
      try {
        final tmdbSeasonDetails = await TmdbClient.instance.getSeasonDetails(tmdbId, seasonNumber);
        if (tmdbSeasonDetails != null) {
          final tmdbEps = tmdbSeasonDetails['episodes'] as List?;
          if (tmdbEps != null) {
            for (final ep in tmdbEps) {
              final epMap = ep as Map<String, dynamic>;
              final epNum = (epMap['episode_number'] as num?)?.toInt();
              if (epNum != null) tmdbEpMap[epNum] = epMap;
            }
          }
        }
      } catch (_) {}

      return episodes.map((e) {
        final eMap = e as Map<String, dynamic>;
        final epNum = _safeInt(eMap['episode_number']) ?? 0;
        final rawWatch = eMap['watch']?.toString();
        final watchUrl = rawWatch != null ? extractValidEmbedUrl(rawWatch) : null;

        // Get TMDB episode data for enrichment
        final tmdbEp = tmdbEpMap[epNum];

        // Admin JSON fields (may be empty strings)
        final adminName = eMap['name']?.toString();
        final adminOverview = eMap['overview']?.toString();
        final adminStillPath = eMap['still_path']?.toString();
        final adminAirDate = eMap['air_date']?.toString();
        final adminRuntime = _safeInt(eMap['runtime']);
        final adminVoteAvg = (eMap['vote_average'] is num) ? (eMap['vote_average'] as num).toDouble() : null;

        // TMDB fields for fallback
        final tmdbName = tmdbEp?['name']?.toString();
        final tmdbOverview = tmdbEp?['overview']?.toString();
        final tmdbStillPath = tmdbEp?['still_path']?.toString();
        final tmdbAirDate = tmdbEp?['air_date']?.toString();
        final tmdbRuntime = (tmdbEp?['runtime'] as num?)?.toInt();
        final tmdbVoteAvg = (tmdbEp?['vote_average'] as num?)?.toDouble();

        // Use admin data if non-empty, otherwise TMDB fallback
        String finalName = (adminName != null && adminName.isNotEmpty && adminName != 'Episode $epNum')
            ? adminName
            : (tmdbName ?? 'Episode $epNum');
        String? finalOverview = (adminOverview != null && adminOverview.isNotEmpty)
            ? adminOverview
            : tmdbOverview;
        String? finalThumb;
        if (adminStillPath != null && adminStillPath.isNotEmpty) {
          // Admin still_path might be a full URL or a TMDB path
          finalThumb = adminStillPath.startsWith('http') ? adminStillPath : TmdbClient.thumbUrl(adminStillPath);
        } else if (tmdbStillPath != null && tmdbStillPath.isNotEmpty) {
          finalThumb = TmdbClient.thumbUrl(tmdbStillPath);
        }

        return EpisodeData(
          episodeNumber: epNum,
          title: finalName,
          description: finalOverview,
          thumbnailUrl: finalThumb,
          runtime: adminRuntime ?? tmdbRuntime,
          airDate: (adminAirDate != null && adminAirDate.isNotEmpty) ? adminAirDate : tmdbAirDate,
          voteAverage: adminVoteAvg ?? tmdbVoteAvg,
          playLink: watchUrl,
          downloadLink: watchUrl,
        );
      }).toList();
    } catch (e, stack) {
      dev.log('[ContentRepo] _buildAdminEpisodes error: $e', stackTrace: stack);
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
