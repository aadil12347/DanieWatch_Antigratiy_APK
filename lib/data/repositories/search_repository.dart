import '../../domain/models/content_detail.dart';
import '../../domain/models/manifest_item.dart';
import '../services/database_sync_service.dart';

class SearchRepository {
  SearchRepository._();
  static final SearchRepository instance = SearchRepository._();

  // In-memory cache of search index
  List<ManifestItem>? _searchIndex;

  /// Load the search index from local database file.
  Future<List<ManifestItem>> _getSearchIndex() async {
    if (_searchIndex != null) return _searchIndex!;
    _searchIndex = await DatabaseSyncService.instance.loadLocalIndex();
    return _searchIndex ?? [];
  }

  /// Invalidate in-memory search index cache (called after sync).
  void invalidateCache() {
    _searchIndex = null;
  }

  /// Search from the local manifest index.
  /// This is fast because the index is already loaded in memory or parsed in isolates.
  Future<List<ContentDetail>> search(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final index = await _getSearchIndex();
      final queryLower = query.toLowerCase().trim();

      // Filter items by title match (case-insensitive)
      final results = index
          .where((item) => item.title.toLowerCase().contains(queryLower))
          .take(30)
          .toList();

      return results.map((item) => _itemToContentDetail(item)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get all items from index (used for explore page).
  Future<List<ContentDetail>> getAllContent() async {
    try {
      final index = await _getSearchIndex();
      return index.map((item) => _itemToContentDetail(item)).toList();
    } catch (e) {
      return [];
    }
  }

  ContentDetail _itemToContentDetail(ManifestItem item) {
    return ContentDetail(
      id: item.id,
      title: item.title,
      mediaType: item.mediaType,
      overview: item.overview,
      posterUrl: item.effectivePosterUrl,
      backdropUrl: item.effectiveBackdropUrl,
      releaseYear: item.releaseYear,
      genres: item.genres,
    );
  }
}
