import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../domain/models/catalog_page.dart';
import '../../domain/models/manifest_item.dart';

/// Client for fetching catalog data from GitHub raw files.
///
/// GitHub repo structure:
///   index/
///     meta.json                 ← version + category counts
///     home/sections.json        ← pre-built home screen data
class GitHubCatalogClient {
  GitHubCatalogClient._();
  static final GitHubCatalogClient instance = GitHubCatalogClient._();

  String get _baseUrl => '${Env.githubRawBaseUrl}/index';

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
  /// Contains version string + item counts.
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

  // ─── Fallback Item Fetching ─────────────────────────────────────────────────

  /// Fetch a single item's JSON directly from streaming_links.
  /// (Watch links are now fetched from here when detail page opens).
  Future<ManifestItem?> fetchSingleItemFallback(String id, String type) async {
    try {
      // streaming_links are stored in root/streaming_links
      final url = '${Env.githubRawBaseUrl}/streaming_links/${type == 'movie' ? 'admin_movie' : 'admin_tv'}_$id.json';
      dev.log('[CatalogClient] Fetching fallback item: $url');
      var response = await _deduplicatedGet(url);
      
      if (response.statusCode != 200) {
        // Try the normal prefix if admin fails
        final normalUrl = '${Env.githubRawBaseUrl}/streaming_links/${type == 'movie' ? 'normal_movie' : 'normal_tv'}_$id.json';
        dev.log('[CatalogClient] Fetching fallback item (normal): $normalUrl');
        response = await _deduplicatedGet(normalUrl);
      }

      if (response.statusCode != 200) {
         // One last attempt without prefix
         final bareUrl = '${Env.githubRawBaseUrl}/streaming_links/$type/$id.json';
         dev.log('[CatalogClient] Fetching fallback item (bare): $bareUrl');
         response = await _deduplicatedGet(bareUrl);
      }

      if (response.statusCode != 200) {
        dev.log('[CatalogClient] fallback item failed: ${response.statusCode}');
        return null;
      }
      
      final dynamic decoded = jsonDecode(response.body);
      
      // streaming_links can sometimes be an array with one object
      Map<String, dynamic> json;
      if (decoded is List && decoded.isNotEmpty) {
        json = decoded.first as Map<String, dynamic>;
      } else if (decoded is Map<String, dynamic>) {
        json = decoded;
      } else {
        return null;
      }

      return ManifestItem.fromJson(json);
    } catch (e) {
      dev.log('[CatalogClient] fetchSingleItemFallback error: $e');
      return null;
    }
  }
}
