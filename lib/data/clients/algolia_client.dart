import '../local/search_database.dart';
import '../local/manifest_dao.dart';
import '../../presentation/providers/search_provider.dart';

/// Local search client backed by SQLite FTS5.
/// Drop-in replacement for the old Algolia HTTP client.
/// Same public API so search_screen.dart needs zero changes.
class AlgoliaClient {
  static final AlgoliaClient instance = AlgoliaClient._internal();
  AlgoliaClient._internal();

  Future<List<ManifestSearchResult>> search(String query, {SearchFilters? filters, int limit = 80}) async {
    return SearchDatabase.instance.search(query, filters: filters, limit: limit);
  }
}
