import 'dart:convert';
import 'dart:io';
import 'package:daniewatch_app/services/extraction/movie_site_scraper_service.dart';

void main() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final uri = Uri.parse('https://vegamovies.gallery/korean-series/');
  final req = await client.getUrl(uri);
  req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36');
  final resp = await req.close();
  final html = await resp.transform(utf8.decoder).join();
  client.close();

  final cards = MovieSiteScraperService.parseCards(html, 'vegamovies');
  print('parseCards returned: ${cards.length} cards');
  for (final c in cards.take(5)) {
    print('Title: ${c.title}, PostUrl: ${c.postUrl}, Poster: ${c.posterUrl}');
  }
}
