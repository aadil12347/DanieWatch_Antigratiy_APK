import 'dart:convert';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';

import '../../core/config/env.dart';
import '../local/database.dart';

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

  Future<dynamic> _getCachedOrFetch(String cacheKey, Future<dynamic> Function() fetcher, {Duration maxAge = const Duration(days: 1)}) async {
    try {
      final cached = await AppDatabase.instance.getCachedTmdbResponse(cacheKey, maxAge: maxAge);
      if (cached != null) {
        return jsonDecode(cached);
      }
    } catch (e) {
      dev.log('[TMDB Cache] Error reading cache for $cacheKey: $e');
    }

    final data = await fetcher();
    if (data != null) {
      try {
        await AppDatabase.instance.cacheTmdbResponse(cacheKey, jsonEncode(data));
      } catch (e) {
        dev.log('[TMDB Cache] Error saving cache for $cacheKey: $e');
      }
    }
    return data;
  }

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
    final cacheKey = 'movie_details_$tmdbId';
    final result = await _getCachedOrFetch(cacheKey, () async {
      try {
        final res = await _dio.get('/movie/$tmdbId', queryParameters: {
          'append_to_response': 'credits,images,videos',
        });
        return res.data as Map<String, dynamic>;
      } on DioException catch (e) {
        dev.log('[TMDB] Movie $tmdbId error: ${e.message}');
        return null;
      }
    });
    return result as Map<String, dynamic>?;
  }

  /// Get TV details for enrichment only
  Future<Map<String, dynamic>?> getTvDetails(int tmdbId) async {
    final cacheKey = 'tv_details_$tmdbId';
    final result = await _getCachedOrFetch(cacheKey, () async {
      try {
        final res = await _dio.get('/tv/$tmdbId', queryParameters: {
          'append_to_response': 'credits,images,videos',
        });
        return res.data as Map<String, dynamic>;
      } on DioException catch (e) {
        dev.log('[TMDB] TV $tmdbId error: ${e.message}');
        return null;
      }
    });
    return result as Map<String, dynamic>?;
  }

  /// Get season details (episodes list for TV)
  Future<Map<String, dynamic>?> getSeasonDetails(
      int tvId, int seasonNumber) async {
    final cacheKey = 'season_details_${tvId}_$seasonNumber';
    final result = await _getCachedOrFetch(cacheKey, () async {
      try {
        final res =
            await _dio.get('/tv/$tvId/season/$seasonNumber', queryParameters: {
          'append_to_response': 'credits,images',
        });
        return res.data as Map<String, dynamic>;
      } on DioException catch (e) {
        dev.log('[TMDB] Season $tvId/$seasonNumber error: ${e.message}');
        return null;
      }
    });
    return result as Map<String, dynamic>?;
  }

  /// Get similar movies
  Future<List<Map<String, dynamic>>> getSimilarMovies(int tmdbId) async {
    final cacheKey = 'similar_movies_$tmdbId';
    final result = await _getCachedOrFetch(cacheKey, () async {
      try {
        final res = await _dio.get('/movie/$tmdbId/similar');
        final results = res.data['results'] as List?;
        return results?.map((e) => e as Map<String, dynamic>).take(20).toList() ??
            [];
      } on DioException catch (e) {
        dev.log('[TMDB] Similar movies $tmdbId error: ${e.message}');
        return [];
      }
    });
    return (result as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Get similar TV shows
  Future<List<Map<String, dynamic>>> getSimilarTv(int tmdbId) async {
    final cacheKey = 'similar_tv_$tmdbId';
    final result = await _getCachedOrFetch(cacheKey, () async {
      try {
        final res = await _dio.get('/tv/$tmdbId/similar');
        final results = res.data['results'] as List?;
        return results?.map((e) => e as Map<String, dynamic>).take(20).toList() ??
            [];
      } on DioException catch (e) {
        dev.log('[TMDB] Similar TV $tmdbId error: ${e.message}');
        return [];
      }
    });
    return (result as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Get trending content for today or this week
  Future<List<Map<String, dynamic>>> getTrending(String mediaType, {String timeWindow = 'day', int page = 1}) async {
    try {
      final res = await _dio.get('/trending/$mediaType/$timeWindow', queryParameters: {'page': page});
      final results = res.data['results'] as List?;
      return results?.map((e) => e as Map<String, dynamic>).toList() ?? [];
    } on DioException catch (e) {
      dev.log('[TMDB] Trending $mediaType $timeWindow error: ${e.message}');
      return [];
    }
  }

  /// Get popular content
  Future<List<Map<String, dynamic>>> getPopular(String mediaType, {int page = 1}) async {
    try {
      final res = await _dio.get('/$mediaType/popular', queryParameters: {'page': page});
      final results = res.data['results'] as List?;
      return results?.map((e) => e as Map<String, dynamic>).toList() ?? [];
    } on DioException catch (e) {
      dev.log('[TMDB] Popular $mediaType error: ${e.message}');
      return [];
    }
  }
  
  /// Batch fetch trending content
  Future<List<Map<String, dynamic>>> getTrendingPages(String mediaType, int pageCount) async {
    final futures = <Future<List<Map<String, dynamic>>>>[];
    for (int i = 1; i <= pageCount; i++) {
      futures.add(getTrending(mediaType, page: i));
    }
    final results = await Future.wait(futures);
    return results.expand((x) => x).toList();
  }

  /// Batch fetch popular content
  Future<List<Map<String, dynamic>>> getPopularPages(String mediaType, int pageCount) async {
    final futures = <Future<List<Map<String, dynamic>>>>[];
    for (int i = 1; i <= pageCount; i++) {
      futures.add(getPopular(mediaType, page: i));
    }
    final results = await Future.wait(futures);
    return results.expand((x) => x).toList();
  }

  /// Get top rated content
  Future<List<Map<String, dynamic>>> getTopRated(String mediaType, {int page = 1}) async {
    try {
      final res = await _dio.get('/$mediaType/top_rated', queryParameters: {'page': page});
      final results = res.data['results'] as List?;
      return results?.map((e) => e as Map<String, dynamic>).toList() ?? [];
    } on DioException catch (e) {
      dev.log('[TMDB] Top rated $mediaType error: ${e.message}');
      return [];
    }
  }

  /// Batch fetch top rated content
  Future<List<Map<String, dynamic>>> getTopRatedPages(String mediaType, int pageCount) async {
    final futures = <Future<List<Map<String, dynamic>>>>[];
    for (int i = 1; i <= pageCount; i++) {
      futures.add(getTopRated(mediaType, page: i));
    }
    final results = await Future.wait(futures);
    return results.expand((x) => x).toList();
  }

  /// Lightweight: fetch only images (logos) for a given media item
  Future<Map<String, dynamic>?> getImages(int id, String mediaType) async {
    final cacheKey = 'images_${mediaType}_$id';
    final result = await _getCachedOrFetch(cacheKey, () async {
      try {
        final type = (mediaType == 'tv' || mediaType == 'series') ? 'tv' : 'movie';
        final res = await _dio.get('/$type/$id/images', queryParameters: {
          'include_image_language': 'en,null',
        });
        return res.data as Map<String, dynamic>;
      } on DioException catch (e) {
        dev.log('[TMDB] Images $id error: ${e.message}');
        return null;
      }
    });
    return result as Map<String, dynamic>?;
  }


  /// Helper: fetch the best English logo URL for a TMDB item
  Future<String?> fetchTmdbLogo(int tmdbId, String mediaType) async {
    try {
      final images = await getImages(tmdbId, mediaType);
      if (images == null) return null;
      final logos = images['logos'] as List?;
      if (logos == null || logos.isEmpty) return null;
      final englishLogo = logos.firstWhere(
        (l) => (l['iso_639_1'] ?? '') == 'en',
        orElse: () => logos.first,
      );
      final path = englishLogo['file_path'] as String?;
      return logoUrl(path);
    } catch (e) {
      dev.log('[TMDB] fetchTmdbLogo error for $tmdbId: $e');
      return null;
    }
  }

  /// Lightweight: fetch only videos (trailers) for a given media item
  Future<List<Map<String, dynamic>>> getVideos(int id, String mediaType) async {
    final cacheKey = 'videos_${mediaType}_$id';
    final result = await _getCachedOrFetch(cacheKey, () async {
      try {
        final type = (mediaType == 'tv' || mediaType == 'series') ? 'tv' : 'movie';
        final res = await _dio.get('/$type/$id/videos');
        final results = res.data['results'] as List?;
        return results?.map((e) => e as Map<String, dynamic>).toList() ?? [];
      } on DioException catch (e) {
        dev.log('[TMDB] Videos $id error: ${e.message}');
        return [];
      }
    });
    return (result as List?)?.cast<Map<String, dynamic>>() ?? [];
  }
  /// Fetch reviews for a given media item
  Future<List<Map<String, dynamic>>> getReviews(int id, String mediaType) async {
    final cacheKey = 'reviews_${mediaType}_$id';
    final result = await _getCachedOrFetch(cacheKey, () async {
      try {
        final type = (mediaType == 'tv' || mediaType == 'series') ? 'tv' : 'movie';
        final res = await _dio.get('/$type/$id/reviews');
        final results = res.data['results'] as List?;
        return results?.map((e) => e as Map<String, dynamic>).toList() ?? [];
      } on DioException catch (e) {
        dev.log('[TMDB] Reviews $id error: ${e.message}');
        return [];
      }
    });
    return (result as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Fetch person/actor details (biography, birthday, gender, place_of_birth, etc.)
  Future<Map<String, dynamic>?> getPersonDetails(int personId) async {
    final cacheKey = 'person_details_$personId';
    final result = await _getCachedOrFetch(cacheKey, () async {
      try {
        final res = await _dio.get('/person/$personId');
        return res.data as Map<String, dynamic>;
      } on DioException catch (e) {
        dev.log('[TMDB] Person $personId error: ${e.message}');
        return null;
      }
    });
    return result as Map<String, dynamic>?;
  }

  /// Fetch combined credits (movies + TV) for a person
  Future<List<Map<String, dynamic>>> getPersonCombinedCredits(int personId) async {
    final cacheKey = 'person_credits_$personId';
    final result = await _getCachedOrFetch(cacheKey, () async {
      try {
        final res = await _dio.get('/person/$personId/combined_credits');
        final cast = res.data['cast'] as List?;
        return cast?.map((e) => e as Map<String, dynamic>).toList() ?? [];
      } on DioException catch (e) {
        dev.log('[TMDB] Person credits $personId error: ${e.message}');
        return [];
      }
    });
    return (result as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Global search across movies and TV shows
  Future<List<Map<String, dynamic>>> searchMulti(String query, {int page = 1}) async {
    try {
      if (query.trim().isEmpty) return [];
      final res = await _dio.get('/search/multi', queryParameters: {
        'query': query,
        'page': page,
        'include_adult': false,
      });
      final results = res.data['results'] as List?;
      return results?.map((e) => e as Map<String, dynamic>).toList() ?? [];
    } on DioException catch (e) {
      dev.log('[TMDB] Search multi error: ${e.message}');
      return [];
    }
  }

  /// Discover movies with dynamic filters (e.g. genres, languages, origin_country)
  Future<List<Map<String, dynamic>>> discoverMovie({
    int page = 1,
    String? withGenres,
    String? withOriginalLanguage,
    String? withOriginCountry,
    String sortBy = 'popularity.desc',
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'sort_by': sortBy,
        'include_adult': false,
      };
      if (withGenres != null) queryParams['with_genres'] = withGenres;
      if (withOriginalLanguage != null) queryParams['with_original_language'] = withOriginalLanguage;
      if (withOriginCountry != null) queryParams['with_origin_country'] = withOriginCountry;

      final res = await _dio.get('/discover/movie', queryParameters: queryParams);
      final results = res.data['results'] as List?;
      return results?.map((e) => e as Map<String, dynamic>).toList() ?? [];
    } on DioException catch (e) {
      dev.log('[TMDB] Discover movie error: ${e.message}');
      return [];
    }
  }

  /// Discover TV shows with dynamic filters
  Future<List<Map<String, dynamic>>> discoverTv({
    int page = 1,
    String? withGenres,
    String? withOriginalLanguage,
    String? withOriginCountry,
    String sortBy = 'popularity.desc',
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'sort_by': sortBy,
        'include_adult': false,
      };
      if (withGenres != null) queryParams['with_genres'] = withGenres;
      if (withOriginalLanguage != null) queryParams['with_original_language'] = withOriginalLanguage;
      if (withOriginCountry != null) queryParams['with_origin_country'] = withOriginCountry;

      final res = await _dio.get('/discover/tv', queryParameters: queryParams);
      final results = res.data['results'] as List?;
      return results?.map((e) => e as Map<String, dynamic>).toList() ?? [];
    } on DioException catch (e) {
      dev.log('[TMDB] Discover TV error: ${e.message}');
      return [];
    }
  }

  /// Find movie or TV show by external IMDb ID
  Future<Map<String, dynamic>?> findByImdbId(String imdbId) async {
    final cacheKey = 'find_imdb_$imdbId';
    final result = await _getCachedOrFetch(cacheKey, () async {
      try {
        final res = await _dio.get('/find/$imdbId', queryParameters: {
          'external_source': 'imdb_id',
        });
        final data = res.data as Map<String, dynamic>;
        final movieResults = data['movie_results'] as List?;
        if (movieResults != null && movieResults.isNotEmpty) {
          final m = Map<String, dynamic>.from(movieResults.first as Map);
          m['media_type'] = 'movie';
          return m;
        }
        final tvResults = data['tv_results'] as List?;
        if (tvResults != null && tvResults.isNotEmpty) {
          final t = Map<String, dynamic>.from(tvResults.first as Map);
          t['media_type'] = 'tv';
          return t;
        }
        return null;
      } on DioException catch (e) {
        dev.log('[TMDB] Find by IMDb $imdbId error: ${e.message}');
        return null;
      }
    });
    return result as Map<String, dynamic>?;
  }

}
