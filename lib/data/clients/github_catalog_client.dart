import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../domain/models/catalog_page.dart';
import '../../domain/models/manifest_item.dart';

/// Client for fetching paginated catalog data from GitHub raw files.
///
/// GitHub repo structure:
///   catalog/
///     meta.json                 ← version + page counts (~500 bytes)
///     search_index.json         ← id+title+type+language for all items
///     home/sections.json        ← pre-built home screen data
///     all/page_1.json           ← paginated global catalog
///     bollywood/page_1.json     ← paginated category pages
///     ...
class GitHubCatalogClient {
  GitHubCatalogClient._();
  static final GitHubCatalogClient instance = GitHubCatalogClient._();

  String get _baseUrl => '${Env.githubRawBaseUrl}/catalog';

  // ─── In-Memory Request Dedup ────────────────────────────────────────────────
  final Map<String, Future<http.Response>> _inflightRequests = {};

  /// Deduplicated HTTP GET — prevents parallel duplicate requests for the same URL.
  Future<http.Response> _deduplicatedGet(String url) {
    return _inflightRequests.putIfAbsent(url, () async {
      try {
        final response = await http.get(Uri.parse(url));
        return response;
      } finally {
        _inflightRequests.remove(url);
      }
    });
  }

  // ─── Catalog Metadata ───────────────────────────────────────────────────────

  /// Fetch catalog metadata (tiny, ~500 bytes).
  /// Contains version string + page counts per category.
  Future<CatalogMeta?> fetchMeta() async {
    try {
      final url = '$_baseUrl/meta.json';
      dev.log('[CatalogClient] Fetching meta: $url');
      final response = await _deduplicatedGet(url);
      if (response.statusCode != 200) {
        dev.log('[CatalogClient] meta.json failed: ${response.statusCode}');
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return CatalogMeta.fromJson(json);
    } catch (e) {
      dev.log('[CatalogClient] fetchMeta error: $e');
      return null;
    }
  }

  // ─── Paginated Category Pages ───────────────────────────────────────────────

  /// Fetch a specific page of a category.
  /// Categories: 'all', 'bollywood', 'korean', 'anime', 'hollywood',
  ///             'chinese', 'punjabi', 'pakistani'
  Future<CatalogPage?> fetchPage(String category, int page) async {
    try {
      final url = '$_baseUrl/$category/page_$page.json';
      dev.log('[CatalogClient] Fetching page: $url');
      final response = await _deduplicatedGet(url);
      if (response.statusCode != 200) {
        dev.log('[CatalogClient] Page $category/$page failed: ${response.statusCode}');
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return CatalogPage.fromJson(json);
    } catch (e) {
      dev.log('[CatalogClient] fetchPage($category, $page) error: $e');
      return null;
    }
  }

  // ─── Home Screen Sections ───────────────────────────────────────────────────

  /// Fetch pre-built home screen data (carousel + all sections).
  /// Single request gives the entire home screen content.
  Future<HomeSectionsData?> fetchHomeSections() async {
    try {
      final url = '$_baseUrl/home/sections.json';
      dev.log('[CatalogClient] Fetching home sections: $url');
      final response = await _deduplicatedGet(url);
      if (response.statusCode != 200) {
        dev.log('[CatalogClient] sections.json failed: ${response.statusCode}');
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return HomeSectionsData.fromJson(json);
    } catch (e) {
      dev.log('[CatalogClient] fetchHomeSections error: $e');
      return null;
    }
  }

  // ─── Search Index ───────────────────────────────────────────────────────────

  /// Fetch lightweight search index (id + title + type + language for all items).
  /// Used for: search, visibility checks, navigation guards.
  Future<List<SearchIndexEntry>?> fetchSearchIndex() async {
    try {
      final url = '$_baseUrl/search_index.json';
      dev.log('[CatalogClient] Fetching search index: $url');
      final response = await _deduplicatedGet(url);
      if (response.statusCode != 200) {
        dev.log('[CatalogClient] search_index.json failed: ${response.statusCode}');
        return null;
      }
      final jsonList = jsonDecode(response.body) as List<dynamic>;
      return jsonList
          .map((e) => SearchIndexEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      dev.log('[CatalogClient] fetchSearchIndex error: $e');
      return null;
    }
  }

  // ─── Multiple Pages (Prefetch) ──────────────────────────────────────────────

  /// Prefetch multiple pages of a category in parallel.
  /// Used for smooth scroll pre-loading.
  Future<List<CatalogPage>> prefetchPages(
    String category,
    List<int> pageNumbers,
  ) async {
    final futures = pageNumbers.map((p) => fetchPage(category, p));
    final results = await Future.wait(futures);
    return results.whereType<CatalogPage>().toList();
  }

  /// Fetch first page of multiple categories in parallel.
  /// Used on app startup to populate home sections quickly.
  Future<Map<String, CatalogPage>> fetchFirstPages(
    List<String> categories,
  ) async {
    final result = <String, CatalogPage>{};
    final futures = categories.map((cat) async {
      final page = await fetchPage(cat, 1);
      if (page != null) result[cat] = page;
    });
    await Future.wait(futures);
    return result;
  }
}
