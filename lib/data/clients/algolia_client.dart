import 'package:dio/dio.dart';
import '../../core/constants/api_keys.dart';
import '../local/manifest_dao.dart';
import '../../presentation/providers/search_provider.dart';

class AlgoliaClient {
  static final AlgoliaClient instance = AlgoliaClient._internal();
  final Dio _dio;

  AlgoliaClient._internal()
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://${ApiKeys.algoliaAppId}-dsn.algolia.net/1/indexes/${ApiKeys.algoliaIndexName}/',
          headers: {
            'X-Algolia-Application-Id': ApiKeys.algoliaAppId,
            'X-Algolia-API-Key': ApiKeys.algoliaSearchKey,
            'Content-Type': 'application/json',
          },
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ));

  Future<List<ManifestSearchResult>> search(String query, {SearchFilters? filters, int limit = 40}) async {
    try {
      final List<String> numericFilters = [];
      final List<String> stringFilters = [];
      
      if (filters != null) {
        if (filters.genres.isNotEmpty) {
           stringFilters.add('(${filters.genres.map((g) => 'genres:"$g"').join(' OR ')})');
        }
        if (filters.originalLanguages.isNotEmpty) {
           stringFilters.add('(${filters.originalLanguages.map((l) => 'languages:"$l"').join(' OR ')})');
        }
        if (filters.categories.isNotEmpty) {
           // Some categories might map to originCountry, but usually categories are handled via navbar.
           // For simplicity, we assume category name matches originCountry or genres for specific cases.
           // (The python script matched them into categories implicitly. If we need strict category matching,
           // we could add a `category` facet to Algolia in the future).
        }
        if (filters.years.isNotEmpty) {
           numericFilters.add('(${filters.years.map((y) => 'releaseYear=$y').join(' OR ')})');
        }
      }
      
      String filterString = stringFilters.join(' AND ');
      if (numericFilters.isNotEmpty) {
          if (filterString.isNotEmpty) filterString += ' AND ';
          filterString += numericFilters.join(' AND ');
      }

      final Map<String, dynamic> data = {
        'params': 'query=${Uri.encodeQueryComponent(query)}&hitsPerPage=$limit'
      };
      if (filterString.isNotEmpty) {
         data['params'] = '${data['params']}&filters=${Uri.encodeQueryComponent(filterString)}';
      }

      final response = await _dio.post('query', data: data);
      
      if (response.statusCode == 200) {
        final List hits = response.data['hits'] ?? [];
        return hits.map((hit) {
          return ManifestSearchResult(
            itemId: int.tryParse(hit['itemId']?.toString() ?? '') ?? 0,
            mediaType: hit['mediaType'] ?? 'movie',
            title: hit['title'] ?? '',
            score: 1.0,
            posterUrl: hit['posterUrl'],
            languages: (hit['languages'] as List?)?.map((e) => e.toString()).toList() ?? [],
            genres: (hit['genres'] as List?)?.map((e) => e.toString()).toList() ?? [],
            releaseYear: hit['releaseYear'] as int? ?? 0,
            originCountry: (hit['originCountry'] as List?)?.map((e) => e.toString()).toList() ?? [],
          );
        }).toList();
      }
    } catch (e) {
      print('Algolia search error: $e');
    }
    return [];
  }
}
