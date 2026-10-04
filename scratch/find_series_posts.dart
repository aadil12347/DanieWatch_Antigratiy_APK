import 'dart:convert';
import 'dart:io';

Future<void> searchVegamovies(String query) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (cert, host, port) => true;

  try {
    final searchUrl = 'https://vegamovies.gallery/ts-search.php?q=${Uri.encodeComponent(query)}&page=1';
    final req = await client.getUrl(Uri.parse(searchUrl));
    req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36');
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    final json = jsonDecode(body);
    final hits = json['hits'] as List? ?? [];
    print('Found ${hits.length} hits for "$query":');
    for (final h in hits.take(5)) {
      final doc = h['document'];
      print('  • Title: ${doc['post_title']}');
      print('    Permalink: ${doc['permalink']}');
    }
  } catch (e) {
    print('Error searching $query: $e');
  } finally {
    client.close();
  }
}

void main() async {
  await searchVegamovies('Breaking Bad');
  print('---------------------------------------------------------');
  await searchVegamovies('Vikings');
  print('---------------------------------------------------------');
  await searchVegamovies('Game of Thrones');
}
