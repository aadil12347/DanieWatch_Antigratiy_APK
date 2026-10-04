import 'dart:convert';
import 'dart:io';

void main() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final uri = Uri.parse('https://rogmovies.best');
  final req = await client.getUrl(uri);
  req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36');
  final resp = await req.close();
  final html = await resp.transform(utf8.decoder).join();
  client.close();

  final cardRegex = RegExp(
    r'<div class="poster-card"[^>]*>([\s\S]*?)<\/div>\s*<\/div>\s*<\/div>',
    caseSensitive: false,
  );
  final matches = cardRegex.allMatches(html).toList();
  print('Rogmovies homepage cardRegex matches: ${matches.length}');
  print('HTML length: ${html.length}');
  print('Contains poster-card? ${html.contains("poster-card")}');
}
