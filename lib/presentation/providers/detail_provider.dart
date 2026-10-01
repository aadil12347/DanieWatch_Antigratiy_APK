import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/clients/tmdb_client.dart';
import '../../data/repositories/content_repository.dart';
import '../../domain/models/content_detail.dart';
import '../../domain/models/manifest_item.dart';
import '../../services/streaming_links_season_service.dart';
import '../../services/extraction/movie_site_scraper_service.dart';
import '../../services/extraction/site_post_extractor.dart';

// ─── Param Classes ───────────────────────────────────────────────────────────

class DetailParams {
  final int tmdbId;
  final String mediaType;

  const DetailParams({required this.tmdbId, required this.mediaType});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DetailParams &&
          runtimeType == other.runtimeType &&
          tmdbId == other.tmdbId &&
          mediaType == other.mediaType;

  @override
  int get hashCode => tmdbId.hashCode ^ mediaType.hashCode;
}

class EpisodeParams {
  final int tmdbId;
  final int seasonNumber;
  final Map<String, List<String>>? seasonsData;
  final bool isAdmin;
  final List<int>? availableEpisodeNumbers;

  const EpisodeParams({
    required this.tmdbId,
    required this.seasonNumber,
    this.seasonsData,
    this.isAdmin = false,
    this.availableEpisodeNumbers,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EpisodeParams &&
          runtimeType == other.runtimeType &&
          tmdbId == other.tmdbId &&
          seasonNumber == other.seasonNumber &&
          _listEquals(availableEpisodeNumbers, other.availableEpisodeNumbers);

  static bool _listEquals(List<int>? a, List<int>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => tmdbId.hashCode ^ seasonNumber.hashCode ^ (availableEpisodeNumbers?.length ?? 0).hashCode;
}

// ─── Providers ───────────────────────────────────────────────────────────────

/// Main content detail — cached per tmdbId + mediaType
final detailProvider = FutureProvider.family<ContentDetail?, DetailParams>(
  (ref, params) async {
    return ContentRepository.instance.fetchContentDetail(
      params.tmdbId,
      mediaType: params.mediaType,
    );
  },
);

/// Episodes for selected season — refreshed on season change only
final episodesProvider =
    FutureProvider.family<List<EpisodeData>, EpisodeParams>(
  (ref, params) async {
    return ContentRepository.instance.fetchEpisodes(
      params.tmdbId.toString(),
      params.seasonNumber,
      seasonsData: params.seasonsData,
      isAdmin: params.isAdmin,
      availableEpisodeNumbers: params.availableEpisodeNumbers,
    );
  },
);

// ─── Streaming Season Map Provider ───────────────────────────────────────────

class StreamingSeasonParams {
  final int tmdbId;
  final String mediaType;
  final String title;

  const StreamingSeasonParams({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamingSeasonParams &&
          runtimeType == other.runtimeType &&
          tmdbId == other.tmdbId;

  @override
  int get hashCode => tmdbId.hashCode;
}

/// Fetches available seasons & episodes from the streaming links JSON.
/// Returns `Map<int, List<int>>` — seasonNumber → sorted episode numbers.
/// Returns empty map if no streaming JSON or no seasons in it.
final streamingSeasonMapProvider =
    FutureProvider.family<Map<int, List<int>>, StreamingSeasonParams>(
  (ref, params) async {
    return StreamingLinksSeasonService().fetchAvailableSeasons(
      tmdbId: params.tmdbId,
      mediaType: params.mediaType,
      title: params.title,
    );
  },
);

// ─── Site Post & Nextdrive Episode Providers ───────────────────────────────

class NextdriveEpisodeParams {
  final int tmdbId;
  final String title;
  final int seasonNumber;
  final String? postUrl;
  final String? posterUrl;

  const NextdriveEpisodeParams({
    required this.tmdbId,
    required this.title,
    required this.seasonNumber,
    this.postUrl,
    this.posterUrl,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NextdriveEpisodeParams &&
          runtimeType == other.runtimeType &&
          tmdbId == other.tmdbId &&
          seasonNumber == other.seasonNumber;

  @override
  int get hashCode => tmdbId.hashCode ^ seasonNumber.hashCode;
}

/// Fetches post buttons (seasons, Batch/Zip, episode links) for a detail item.
final sitePostButtonsProvider =
    FutureProvider.family<List<SitePostButton>, String>((ref, postUrl) async {
  if (postUrl.isEmpty) return [];
  return SitePostExtractor.instance.extractPostButtons(postUrl);
});

/// Fetches episodes directly from the Nextdrive episode selector page.
/// Titles are strictly preserved from Nextdrive (e.g. "Episode 1-5", "Season 01 Complete").
/// Only thumbnails/stills are fetched from TMDB.
final nextdriveEpisodesProvider =
    FutureProvider.family<List<NextdriveEpisode>, NextdriveEpisodeParams>(
  (ref, params) async {
    // 1. Locate the post URL
    var postUrl = params.postUrl;
    if (postUrl == null || postUrl.isEmpty) {
      postUrl = await SitePostExtractor.instance.findPostUrl(
        title: params.title,
        tmdbId: params.tmdbId,
      );
    }
    if (postUrl == null || postUrl.isEmpty) {
      return [];
    }

    // 2. Extract buttons from the post page
    final buttons = await SitePostExtractor.instance.extractPostButtons(postUrl);
    if (buttons.isEmpty) return [];

    // 3. Find the best episode link button for this season (720p > 480p > 1080p)
    final bestBtn = SitePostExtractor.instance.getBestEpisodeButton(buttons, params.seasonNumber);
    if (bestBtn == null) return [];

    // 4. Extract episodes from Nextdrive selector page
    final episodes = await SitePostExtractor.instance.extractNextdriveEpisodes(bestBtn.href);
    if (episodes.isEmpty) return [];

    // 5. Fetch TMDB season details ONLY for stills/thumbnails (NEVER for titles!)
    Map<int, String?> stillMap = {};
    try {
      final seasonJson = await TmdbClient.instance.getSeasonDetails(params.tmdbId, params.seasonNumber);
      if (seasonJson != null && seasonJson['episodes'] is List) {
        for (final ep in seasonJson['episodes']) {
          final epNum = ep['episode_number'] as int?;
          final still = ep['still_path'] as String?;
          if (epNum != null && still != null && still.isNotEmpty) {
            stillMap[epNum] = 'https://image.tmdb.org/t/p/w500$still';
          }
        }
      }
    } catch (_) {}

    // 6. Enrich episodes with TMDB thumbnail (fallback to posterUrl)
    for (final ep in episodes) {
      if (ep.episodeNumber != null && stillMap.containsKey(ep.episodeNumber)) {
        ep.thumbnailUrl = stillMap[ep.episodeNumber];
      } else if (ep.rangeStart != null && stillMap.containsKey(ep.rangeStart)) {
        ep.thumbnailUrl = stillMap[ep.rangeStart];
      } else {
        ep.thumbnailUrl = params.posterUrl;
      }
    }

    return episodes;
  },
);

/// Similar content
final similarProvider = FutureProvider.family<List<SimilarItem>, DetailParams>(
  (ref, params) async {
    return ContentRepository.instance.fetchSimilar(
      params.tmdbId,
      params.mediaType,
    );
  },
);


/// Reviews content
final reviewsProvider = FutureProvider.family<List<ReviewItem>, DetailParams>(
  (ref, params) async {
    return ContentRepository.instance.fetchReviews(
      params.tmdbId,
      params.mediaType,
    );
  },
);

// ─── TMDB Logo Provider (for carousel) ───────────────────────────────────────

class TmdbLogoParams {
  final int tmdbId;
  final String mediaType;

  const TmdbLogoParams({required this.tmdbId, required this.mediaType});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TmdbLogoParams &&
          runtimeType == other.runtimeType &&
          tmdbId == other.tmdbId &&
          mediaType == other.mediaType;

  @override
  int get hashCode => tmdbId.hashCode ^ mediaType.hashCode;
}

/// Fetches the TMDB logo URL for a given item.
/// Used by the carousel to show logos instead of text titles.
final tmdbLogoProvider = FutureProvider.family<String?, TmdbLogoParams>(
  (ref, params) async {
    try {
      final images = await TmdbClient.instance.getImages(params.tmdbId, params.mediaType);
      if (images == null) return null;
      final logos = images['logos'] as List?;
      if (logos == null || logos.isEmpty) return null;
      // Prefer English logos
      final englishLogo = logos.firstWhere(
        (l) => (l['iso_639_1'] ?? '') == 'en',
        orElse: () => logos.first,
      );
      final path = englishLogo['file_path'] as String?;
      return TmdbClient.logoUrl(path);
    } catch (_) {
      return null;
    }
  },
);

/// Fetches and caches the TMDB logo for a carousel ManifestItem.
/// Resolves via detail page -> IMDb code (tt...) -> TMDB ID -> TMDB logo.
final heroItemLogoProvider = FutureProvider.family<String?, ManifestItem>(
  (ref, item) async {
    try {
      // 1. If item already has a logoUrl, return it immediately
      if (item.logoUrl != null && item.logoUrl!.isNotEmpty) {
        return item.logoUrl;
      }

      // 2. Obtain postUrl (from item or from scraper service map)
      String? postUrl = item.postUrl;
      if (postUrl == null || postUrl.isEmpty) {
        postUrl = MovieSiteScraperService.instance.getPostUrl(item.id);
      }

      String? imdbId = item.imdbId;

      // 3. If no imdbId, fetch detail page from postUrl and extract IMDb code
      if ((imdbId == null || imdbId.isEmpty) && postUrl != null && postUrl.isNotEmpty) {
        imdbId = await MovieSiteScraperService.instance.fetchImdbIdFromPostUrl(postUrl);
      }

      int? tmdbId;
      String mediaType = item.mediaType;

      // 4. If we have an IMDb code (e.g. tt5675620), find TMDB details
      if (imdbId != null && imdbId.isNotEmpty) {
        final findData = await TmdbClient.instance.findByImdbId(imdbId);
        if (findData != null) {
          tmdbId = findData['id'] as int?;
          final type = findData['media_type']?.toString();
          if (type == 'tv' || type == 'movie') {
            mediaType = type!;
          }
        }
      }

      // 5. If still no tmdbId, check if item.id is already a real TMDB ID (< 1,000,000)
      if (tmdbId == null && item.id > 0 && item.id < 1000000) {
        tmdbId = item.id;
      }

      // 6. Fallback: Search TMDB by clean title
      if (tmdbId == null) {
        final pureTitle = MovieSiteScraperService.extractPureTitle(item.title);
        final searchResults = await TmdbClient.instance.searchMulti(
          pureTitle.isNotEmpty ? pureTitle : item.cleanTitle,
        );
        if (searchResults.isNotEmpty) {
          final firstMatch = searchResults.first;
          tmdbId = firstMatch['id'] as int?;
          final type = firstMatch['media_type']?.toString();
          if (type == 'tv' || type == 'movie') {
            mediaType = type!;
          }
        }
      }

      if (tmdbId == null) return null;

      // Register the resolved real tmdbId & mediaType so taps open real detail screen
      MovieSiteScraperService.instance.registerResolvedTmdb(item.id, tmdbId, mediaType);

      // 7. Fetch the logo
      return await TmdbClient.instance.fetchTmdbLogo(tmdbId, mediaType);
    } catch (_) {
      return null;
    }
  },
);
