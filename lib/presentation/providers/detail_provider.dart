import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/content_repository.dart';
import '../../domain/models/content_detail.dart';

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

  const EpisodeParams({
    required this.tmdbId,
    required this.seasonNumber,
    this.seasonsData,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EpisodeParams &&
          runtimeType == other.runtimeType &&
          tmdbId == other.tmdbId &&
          seasonNumber == other.seasonNumber;

  @override
  int get hashCode => tmdbId.hashCode ^ seasonNumber.hashCode;
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
