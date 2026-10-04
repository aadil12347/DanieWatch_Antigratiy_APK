import 'dart:convert';
import 'dart:io';

void main() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  
  // Test URLs used by MovieSiteScraperService
  final urls = {
    'korean': 'https://vegamovies.gallery/korean-series/',
    'anime': 'https://vegamovies.gallery/anime-series/',
    'indian (rog)': 'https://rogmovies.fit/',
    'dual-audio (rog)': 'https://rogmovies.fit/',
    'chinese search': 'https://vegamovies.gallery/?s=Chinese',
    'action vega': 'https://vegamovies.gallery/movies-by-genres/action/',
    'action rog': 'https://rogmovies.fit/movies-by-genres/action/',
  };

  for (final entry in urls.entries) {
    try {
      print('\nTesting ${entry.key}: ${entry.value}...');
      final uri = Uri.parse(entry.value);
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36');
      final resp = await req.close();
      print('Status: ${resp.statusCode}');
      final html = await resp.transform(utf8.decoder).join();
      print('HTML length: ${html.length}');
      
      // Count article or blog-item cards
      final cardMatches = RegExp(r'<article\b|<div[^>]+class="[^"]*(?:blog-item|post-item|entry-item)', caseSensitive: false).allMatches(html);
      print('Detected cards: ${cardMatches.length}');
    } catch (e) {
      print('Error fetching ${entry.key}: $e');
    }
  }
  client.close();
}
