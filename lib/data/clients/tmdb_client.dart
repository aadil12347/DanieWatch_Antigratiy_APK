import 'dart:developer' as dev;

import 'package:dio/dio.dart';

import '../../core/config/env.dart';

/// TMDB API client — used ONLY for enriching existing DB-backed items.
/// NEVER use this to discover new content or populate any UI feed.
class TmdbClient {
  TmdbClient._();
  static final TmdbClient instance = TmdbClient._();

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: Env.tmdbBaseUrl,
    queryParameters: {'api_key': Env.tmdbApiKey, 'language': 'en-US'},
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ))
    ..interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      logPrint: (msg) => dev.log(msg.toString(), name: 'TMDB'),
    ));

  static String imageUrl(String? path, {String size = 'w500'}) {
    if (path == null || path.isEmpty) return '';
    return '${Env.tmdbImageBase}/$size$path';
  }

  static String backdropUrl(String? path, {String size = 'w780'}) =>
      imageUrl(path, size: size);

  static String posterUrl(String? path, {String size = 'w342'}) =>
      imageUrl(path, size: size);

  static String thumbUrl(String? path) => imageUrl(path, size: 'w185');

  static String logoUrl(String? path) => imageUrl(path, size: 'original');

  /// Get movie details for enrichment only (fill missing fields on DB item)
  Future<Map<String, dynamic>?> getMovieDetails(int tmdbId) async {
    try {
      final res = await _dio.get('/movie/$tmdbId', queryParameters: {
        'append_to_response': 'credits,images,videos',
      });
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      dev.log('[TMDB] Movie $tmdbId error: ${e.message}');
      return null;
    }
  }

  /// Get TV details for enrichment only
  Future<Map<String, dynamic>?> getTvDetails(int tmdbId) async {
    try {
      final res = await _dio.get('/tv/$tmdbId', queryParameters: {
        'append_to_response': 'credits,images,videos',
      });
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      dev.log('[TMDB] TV $tmdbId error: ${e.message}');
      return null;
    }
  }

  /// Get season details (episodes list for TV)
  Future<Map<String, dynamic>?> getSeasonDetails(
      int tvId, int seasonNumber) async {
    try {
      final res = await _dio.get('/tv/$tvId/season/$seasonNumber', queryParameters: {
        'append_to_response': 'credits,images',
      });
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      dev.log('[TMDB] Season $tvId/$seasonNumber error: ${e.message}');
      return null;
    }
  }

  /// Get similar movies
  Future<List<Map<String, dynamic>>> getSimilarMovies(int tmdbId) async {
    try {
      final res = await _dio.get('/movie/$tmdbId/similar');
      final results = res.data['results'] as List?;
      return results?.map((e) => e as Map<String, dynamic>).take(20).toList() ?? [];
    } on DioException catch (e) {
      dev.log('[TMDB] Similar movies $tmdbId error: ${e.message}');
      return [];
    }
  }

  /// Get similar TV shows
  Future<List<Map<String, dynamic>>> getSimilarTv(int tmdbId) async {
    try {
      final res = await _dio.get('/tv/$tmdbId/similar');
      final results = res.data['results'] as List?;
      return results?.map((e) => e as Map<String, dynamic>).take(20).toList() ?? [];
    } on DioException catch (e) {
      dev.log('[TMDB] Similar TV $tmdbId error: ${e.message}');
      return [];
    }
  }
}
