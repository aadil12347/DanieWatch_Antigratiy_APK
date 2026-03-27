import 'dart:convert';
import 'dart:developer' as dev;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/content_detail.dart';
import '../../domain/models/entry.dart';
import '../clients/tmdb_client.dart';

class ContentRepository {
  ContentRepository._();
  static final ContentRepository instance = ContentRepository._();

  SupabaseClient get _client => Supabase.instance.client;

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

      // Step 1+2: Parallel fetch TMDB + DB entry
      final futures = await Future.wait([
        isTv
            ? TmdbClient.instance.getTvDetails(tmdbId)
            : TmdbClient.instance.getMovieDetails(tmdbId),
        _client
            .from('entries')
            .select()
            .eq('id', tmdbId.toString())
            .maybeSingle(),
      ]);

      final tmdbDetails = futures[0];
      final rawDbEntry = futures[1];

      Map<String, dynamic>? dbEntry;
      if (rawDbEntry != null) {
        dbEntry = rawDbEntry;
        final actualType = dbEntry['type']?.toString().toLowerCase();
        final expectedType = isTv ? 'series' : 'movie';

        if (actualType != null &&
            actualType != expectedType &&
            actualType != 'tv') {
          dev.log(
              '[ContentRepo] Type mismatch: Expected $expectedType but got $actualType. Ignoring DB entry.');
          dbEntry = null; // Ignore mismatched DB entry
        }
      }

      // If both are null, nothing to show
      if (tmdbDetails == null && dbEntry == null) return null;

      // Step 3: Detect active links from DB
      Map<String, dynamic>? contentJson;
      if (dbEntry != null && dbEntry['content'] != null) {
        contentJson = dbEntry['content'] is String
            ? jsonDecode(dbEntry['content'] as String) as Map<String, dynamic>
            : dbEntry['content'] as Map<String, dynamic>;
      }

      final dbType =
          dbEntry?['type']?.toString() ?? (isTv ? 'series' : 'movie');
      final hasActiveLinks = _detectActiveLinks(contentJson, dbType);

      // Step 4: Build ContentDetail with merge strategy
      // TMDB values as base, DB overrides when hasActiveLinks and non-null
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
        posterUrl =
            TmdbClient.posterUrl(tmdbDetails['poster_path']?.toString());
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

        // Extract year
        final dateStr = tmdbDetails['release_date']?.toString() ??
            tmdbDetails['first_air_date']?.toString();
        if (dateStr != null && dateStr.length >= 4) {
          releaseYear = int.tryParse(dateStr.substring(0, 4));
        }
      } else {
        // Fallback: DB-only
        title = dbEntry?['title']?.toString() ?? 'Unknown';
        overview = dbEntry?['overview']?.toString();
        posterUrl = dbEntry?['poster_url']?.toString();
        backdropUrl = dbEntry?['backdrop_url']?.toString();
        logoUrl = dbEntry?['logo_url']?.toString();
        tagline = dbEntry?['tagline']?.toString();
        voteAverage = (dbEntry?['vote_average'] as num?)?.toDouble() ?? 0.0;
        voteCount = (dbEntry?['vote_count'] as num?)?.toInt();
        runtime = (dbEntry?['runtime'] as num?)?.toInt();
        numberOfSeasons = (dbEntry?['number_of_seasons'] as num?)?.toInt();
        numberOfEpisodes = (dbEntry?['number_of_episodes'] as num?)?.toInt();
        status = dbEntry?['status']?.toString();
        imdbId = dbEntry?['imdb_id']?.toString();
        genres = _parseGenres(dbEntry?['genres']);
        castMembers = _parseCastData(dbEntry?['cast_data']);
        releaseYear = dbEntry?['release_year'] as int?;
      }

      // Step 4b: DB override when has active links
      if (hasActiveLinks && dbEntry != null) {
        if (dbEntry['title'] != null) title = dbEntry['title'].toString();
        if (dbEntry['overview'] != null)
          overview = dbEntry['overview'].toString();
        if (dbEntry['poster_url'] != null)
          posterUrl = dbEntry['poster_url'].toString();
        if (dbEntry['backdrop_url'] != null)
          backdropUrl = dbEntry['backdrop_url'].toString();
        if (dbEntry['logo_url'] != null)
          logoUrl = dbEntry['logo_url'].toString();
        if (dbEntry['tagline'] != null) tagline = dbEntry['tagline'].toString();
        if (dbEntry['vote_average'] != null)
          voteAverage = (dbEntry['vote_average'] as num).toDouble();
        if (dbEntry['imdb_id'] != null) imdbId = dbEntry['imdb_id'].toString();
        if (dbEntry['runtime'] != null)
          runtime = (dbEntry['runtime'] as num).toInt();
        if (dbEntry['number_of_seasons'] != null)
          numberOfSeasons = (dbEntry['number_of_seasons'] as num).toInt();
        if (dbEntry['number_of_episodes'] != null)
          numberOfEpisodes = (dbEntry['number_of_episodes'] as num).toInt();

        // DB genres/cast override
        final dbGenres = _parseGenres(dbEntry['genres']);
        if (dbGenres.isNotEmpty) genres = dbGenres;
        final dbCast = _parseCastData(dbEntry['cast_data']);
        if (dbCast.isNotEmpty) castMembers = dbCast;
      }

      // Step 5: TMDB seasons metadata
      List<TmdbSeason>? tmdbSeasons;
      if (isTv && tmdbDetails != null) {
        final seasons = tmdbDetails['seasons'] as List?;
        if (seasons != null) {
          tmdbSeasons = seasons
              .where((s) =>
                  s['season_number'] != null && (s['season_number'] as int) > 0)
              .map((s) => TmdbSeason.fromJson(s as Map<String, dynamic>))
              .toList();
        }
      }

      // Extract movie watch/download links
      String? watchLink, downloadLink;
      if (!isTv && contentJson != null) {
        final rawWatch = contentJson['watch_link'] ??
            contentJson['play_url'] ??
            contentJson['stream_url'];
        if (rawWatch != null) {
          watchLink = extractValidEmbedUrl(rawWatch.toString());
        }
        final rawDownload =
            contentJson['download_link'] ?? contentJson['download_url'];
        if (rawDownload != null) {
          downloadLink = extractValidDownloadUrl(rawDownload.toString());
        }
      }

      // Determine correct mediaType
      final resolvedMediaType = isTv ? 'tv' : 'movie';

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
      );
    } catch (e, stack) {
      dev.log('[ContentRepo] fetchContentDetail error: $e', stackTrace: stack);
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EPISODES FETCH: entry_metadata + TMDB fallback + placeholder generation
  // ═══════════════════════════════════════════════════════════════════════════
  Future<List<EpisodeData>> fetchEpisodes(
      String entryId, int seasonNumber) async {
    try {
      // Step 1: Parallel fetch metadata + content links + TMDB season
      final tmdbId = int.tryParse(entryId) ?? 0;

      final futures = await Future.wait<dynamic>([
        _client
            .from('entry_metadata')
            .select()
            .eq('entry_id', entryId)
            .eq('season_number', seasonNumber)
            .order('episode_number'),
        _client
            .from('entries')
            .select('content')
            .eq('id', entryId)
            .maybeSingle(),
        TmdbClient.instance.getSeasonDetails(tmdbId, seasonNumber),
      ]);

      final metadataRows = futures[0] as List<dynamic>;
      final entryResponse = futures[1] as Map<String, dynamic>?;
      final tmdbSeasonDetails = futures[2] as Map<String, dynamic>?;

      // Parse content JSON for links
      final seasonLinks =
          _extractSeasonLinks(entryResponse?['content'], seasonNumber);

      // Parse TMDB episodes
      List<TmdbEpisode> tmdbEpisodes = [];
      if (tmdbSeasonDetails != null) {
        final eps = tmdbSeasonDetails['episodes'] as List?;
        if (eps != null) {
          tmdbEpisodes = eps
              .map((e) => TmdbEpisode.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }

      // Step 2: Build episode list
      List<EpisodeData> episodes;

      if (metadataRows.isNotEmpty) {
        // Use DB metadata rows
        episodes = metadataRows.asMap().entries.map((entry) {
          final idx = entry.key;
          final ep = entry.value as Map<String, dynamic>;

          // Find matching TMDB episode for enrichment
          final epNum = ep['episode_number'] as int? ?? (idx + 1);
          final tmdbEp =
              tmdbEpisodes.where((t) => t.episodeNumber == epNum).firstOrNull;

          // DB metadata values take priority (admin_edited), then TMDB fallback
          final adminEdited = ep['admin_edited'] == true;
          String? thumbnailUrl = ep['still_path']?.toString();
          if (thumbnailUrl != null && !thumbnailUrl.startsWith('http')) {
            thumbnailUrl = TmdbClient.thumbUrl(thumbnailUrl);
          }
          if ((thumbnailUrl == null || thumbnailUrl.isEmpty) &&
              tmdbEp?.stillPath != null) {
            thumbnailUrl = TmdbClient.thumbUrl(tmdbEp!.stillPath);
          }

          return EpisodeData(
            episodeNumber: epNum,
            title: adminEdited
                ? (ep['name']?.toString() ?? tmdbEp?.name)
                : (tmdbEp?.name ?? ep['name']?.toString()),
            description: adminEdited
                ? (ep['overview']?.toString() ?? tmdbEp?.overview)
                : (tmdbEp?.overview ?? ep['overview']?.toString()),
            thumbnailUrl: thumbnailUrl,
            runtime: adminEdited
                ? ((ep['runtime'] as num?)?.toInt() ?? tmdbEp?.runtime)
                : (tmdbEp?.runtime ?? (ep['runtime'] as num?)?.toInt()),
            airDate: tmdbEp?.airDate ?? ep['air_date']?.toString(),
            voteAverage: tmdbEp?.voteAverage,
          );
        }).toList();
      } else if (tmdbEpisodes.isNotEmpty) {
        // Use TMDB episodes
        episodes = tmdbEpisodes.map((tmdbEp) {
          String? thumbnailUrl;
          if (tmdbEp.stillPath != null) {
            thumbnailUrl = TmdbClient.thumbUrl(tmdbEp.stillPath);
          }
          return EpisodeData(
            episodeNumber: tmdbEp.episodeNumber,
            title: tmdbEp.name,
            description: tmdbEp.overview,
            thumbnailUrl: thumbnailUrl,
            runtime: tmdbEp.runtime,
            airDate: tmdbEp.airDate,
            voteAverage: tmdbEp.voteAverage,
          );
        }).toList();
      } else {
        episodes = [];
      }

      // Step 3 & 4: Exact index-based mapping + placeholder generation
      final finalCount = [
        episodes.length,
        seasonLinks.watchLinks.length,
        seasonLinks.downloadLinks.length,
      ].reduce((a, b) => a > b ? a : b);

      final List<EpisodeData> mappedEpisodes = List.generate(finalCount, (i) {
        final epNo = i + 1;
        final base = episodes.where((e) => e.episodeNumber == epNo).firstOrNull;

        final episode = base ??
            EpisodeData(
              episodeNumber: epNo,
              title: 'Episode $epNo',
              description: '',
            );

        String? playLink;
        if (i < seasonLinks.watchLinks.length &&
            seasonLinks.watchLinks[i].isNotEmpty) {
          playLink = extractValidEmbedUrl(seasonLinks.watchLinks[i]);
        }

        String? dlLink;
        if (i < seasonLinks.downloadLinks.length &&
            seasonLinks.downloadLinks[i].isNotEmpty) {
          dlLink = extractValidDownloadUrl(seasonLinks.downloadLinks[i]);
        }

        return episode.copyWith(
          playLink: playLink,
          downloadLink: dlLink,
        );
      });

      return mappedEpisodes;
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
