import '../../domain/models/content_detail.dart';
import '../../domain/models/manifest_item.dart';
import '../local/manifest_dao.dart';

class SearchRepository {
  SearchRepository._();
  static final SearchRepository instance = SearchRepository._();

  /// Search from local manifest cache
  Future<List<ContentDetail>> search(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final manifest = await ManifestDao().readManifest();
      if (manifest == null) return [];

      final queryLower = query.toLowerCase();
      
      // Filter items by search query
      final results = manifest.items.where((item) {
        return item.title.toLowerCase().contains(queryLower) ||
            (item.overview?.toLowerCase().contains(queryLower) ?? false);
      }).take(30).toList();

      return results.map((item) => _manifestToContentDetail(item)).toList();
    } catch (e) {
      print('Error searching: $e');
      return [];
    }
  }

  /// Get all items from local cache
  Future<List<ContentDetail>> getAllContent() async {
    try {
      final manifest = await ManifestDao().readManifest();
      if (manifest == null) return [];

      return manifest.items.map((item) => _manifestToContentDetail(item)).toList();
    } catch (e) {
      print('Error getting all content: $e');
      return [];
    }
  }

  ContentDetail _manifestToContentDetail(ManifestItem item) {
    return ContentDetail(
      id: item.id,
      title: item.title,
      description: item.overview,
      overview: item.overview,
      mediaType: item.mediaType,
      voteAverage: item.voteAverage,
      voteCount: item.voteCount,
      posterUrl: item.posterUrl,
      backdropUrl: item.backdropUrl,
      logoUrl: item.logoUrl,
      releaseYear: item.releaseYear,
      genreIds: item.genreIds,
      genres: null,
      tagline: item.tagline,
      runtime: item.runtime,
      numberOfSeasons: item.numberOfSeasons,
      numberOfEpisodes: item.numberOfEpisodes,
      status: item.status,
    );
  }
}
