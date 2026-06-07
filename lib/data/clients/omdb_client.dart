import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import '../../core/config/env.dart';

/// OMDb API client — used for retrieving movie/show posters by IMDb ID.
class OmdbClient {
  OmdbClient._();
  static final OmdbClient instance = OmdbClient._();

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://www.omdbapi.com',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ))
    ..interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      logPrint: (msg) => dev.log(msg.toString(), name: 'OMDb'),
    ));

  /// Fetches the poster URL for a given IMDb ID.
  /// Returns null if the request fails, or if no poster is found.
  Future<String?> getPoster(String imdbId) async {
    try {
      if (Env.omdbApiKey.isEmpty) {
        dev.log('[OMDb] Error: OMDB_API_KEY is not configured in Env.');
        return null;
      }

      final res = await _dio.get('/', queryParameters: {
        'apikey': Env.omdbApiKey,
        'i': imdbId,
      });

      if (res.data != null && res.data is Map) {
        final data = res.data as Map<String, dynamic>;
        if (data['Response'] == 'True') {
          final posterUrl = data['Poster'] as String?;
          if (posterUrl != null && posterUrl != 'N/A') {
            return posterUrl;
          }
        } else {
          dev.log('[OMDb] API Error for $imdbId: ${data['Error']}');
        }
      }
    } on DioException catch (e) {
      dev.log('[OMDb] Network Error for $imdbId: ${e.message}');
    } catch (e) {
      dev.log('[OMDb] Unexpected Error for $imdbId: $e');
    }
    return null;
  }
}
