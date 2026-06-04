import '../../domain/models/content_detail.dart';
import '../../domain/models/manifest_item.dart';
import '../../domain/models/catalog_page.dart';
import '../local/manifest_dao.dart';

class SearchRepository {
  SearchRepository._();
  static final SearchRepository instance = SearchRepository._();

  // In-memory cache of search index
  List<SearchIndexEntry>? _searchIndex;

  /// Load the search index (from cache or SQLite).
  Future<List<SearchIndexEntry>> _getSearchIndex() async {
    if (_searchIndex != null) return _searchIndex!;
    _searchIndex = await ManifestDao().loadSearchIndex();
    return _searchIndex ?? [];
  }

  /// Invalidate in-memory search index cache (called after sync).
  void invalidateCache() {
    _searchIndex = null;
  }

  /// Search from the lightweight search index.
  /// This is fast because search_index.json only has id+title+type+language.
  Future<List<ContentDetail>> search(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final index = await _getSearchIndex();
      final queryLower = query.toLowerCase();

      // Filter items by title match
      final results = index
          .where((entry) => entry.title.toLowerCase().contains(queryLower))
          .take(30)
          .toList();

      return results.map((entry) => _searchEntryToContentDetail(entry)).toList();
    } catch (e) {
      // Fallback to FTS if search index fails
      return _searchFts(query);
    }
  }

  /// Fallback: search using local FTS (from cached pages).
  Future<List<ContentDetail>> _searchFts(String query) async {
    try {
      final ftsResults = await ManifestDao().searchFts(query);
      return ftsResults.map((r) => ContentDetail(
        id: r.itemId,
        title: r.title,
        mediaType: r.mediaType,
      )).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get all items from search index (used for explore page).
  Future<List<ContentDetail>> getAllContent() async {
    try {
      final index = await _getSearchIndex();
      return index.map((entry) => _searchEntryToContentDetail(entry)).toList();
    } catch (e) {
      print('Error getting all content: $e');
      return [];
    }
  }

  ContentDetail _searchEntryToContentDetail(SearchIndexEntry entry) {
    return ContentDetail(
      id: entry.id,
      title: entry.title,
      mediaType: entry.mediaType,
    );
  }
}
