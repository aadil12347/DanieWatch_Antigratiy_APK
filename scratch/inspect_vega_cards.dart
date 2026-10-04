import 'package:dio/dio.dart';
import '../lib/services/extraction/movie_site_scraper_service.dart';

void main() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 12),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    },
  ));

  final res = await dio.get<String>('https://vegamovies.gallery/korean-series/');
  final html = res.data ?? '';

  final cards = MovieSiteScraperService.parseCards(html, 'vegamovies');
  print('parseCards count: ${cards.length}');
  for (final c in cards.take(5)) {
    print('Card: title="${c.title}", poster="${c.posterUrl}", postUrl="${c.postUrl}"');
  }
}
