import 'package:dio/dio.dart';
import '../config/env.dart';
import '../../domain/models/notification_entry.dart';

/// Service to fetch movie/TV show details from TMDB API by ID.
/// Admin enters TMDB ID → this service auto-fills all metadata.
class TmdbFetchService {
  static final TmdbFetchService instance = TmdbFetchService._();
  TmdbFetchService._();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: Env.tmdbBaseUrl,
    queryParameters: {'api_key': Env.tmdbApiKey},
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Fetch movie or TV show details by TMDB ID.
  /// Returns a NotificationEntry ready for database insert.
  Future<NotificationEntry?> fetchByTmdbId({
    required int tmdbId,
    required String mediaType,
    required String category,
  }) async {
    try {
      final endpoint = mediaType == 'tv' ? '/tv/$tmdbId' : '/movie/$tmdbId';
      final response = await _dio.get(endpoint);
      
      if (response.statusCode != 200 || response.data == null) return null;

      final data = response.data as Map<String, dynamic>;
      
      final title = (data['title'] ?? data['name'] ?? '').toString();
      final posterPath = data['poster_path']?.toString();
      final backdropPath = data['backdrop_path']?.toString();
      
      // Extract release year
      int? releaseYear;
      final releaseDate = (data['release_date'] ?? data['first_air_date'])?.toString();
      if (releaseDate != null && releaseDate.length >= 4) {
        releaseYear = int.tryParse(releaseDate.substring(0, 4));
      }

      final voteAverage = (data['vote_average'] is num)
          ? (data['vote_average'] as num).toDouble()
          : 0.0;

      return NotificationEntry(
        id: '', // Will be assigned by database
        tmdbId: tmdbId,
        mediaType: mediaType,
        title: title,
        posterUrl: posterPath != null ? 'https://image.tmdb.org/t/p/w342$posterPath' : null,
        backdropUrl: backdropPath != null ? 'https://image.tmdb.org/t/p/w780$backdropPath' : null,
        releaseYear: releaseYear,
        voteAverage: voteAverage,
        category: category,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Search TMDB to auto-detect if an ID is a movie or TV show.
  /// Tries movie first, then TV.
  Future<String?> detectMediaType(int tmdbId) async {
    try {
      final movieResponse = await _dio.get('/movie/$tmdbId');
      if (movieResponse.statusCode == 200) return 'movie';
    } catch (_) {}
    
    try {
      final tvResponse = await _dio.get('/tv/$tmdbId');
      if (tvResponse.statusCode == 200) return 'tv';
    } catch (_) {}
    
    return null;
  }
}
