import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/clients/tmdb_client.dart';
import '../../data/repositories/content_repository.dart';
import '../../domain/models/content_detail.dart';
import '../../services/streaming_links_season_service.dart';

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
/// Returns Map<int, List<int>> — seasonNumber → sorted episode numbers.
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
