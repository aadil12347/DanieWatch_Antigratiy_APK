import 'dart:convert';
import 'dart:io';

void main() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final uri = Uri.parse('https://vegamovies.gallery/korean-series/');
  final req = await client.getUrl(uri);
  req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36');
  final resp = await req.close();
  final html = await resp.transform(utf8.decoder).join();
  client.close();

  print('HTML length: ${html.length}');
  print('Contains poster-card? ${html.contains("poster-card")}');
  print('Contains blog-item? ${html.contains("blog-item")}');
  print('Contains post-item? ${html.contains("post-item")}');
  print('Contains article? ${html.contains("<article")}');

  // Find all matches for class= on divs/articles
  final m = RegExp(r'<(?:article|div)\s+[^>]*class="([^"]+)"[^>]*>', caseSensitive: false).allMatches(html);
  final classes = <String>{};
  for (final match in m) {
    classes.add(match.group(1)!);
  }
  print('Found classes (sample): ${classes.take(30).toList()}');

  // Let's also check a sample card HTML snippet
  final postMatch = RegExp(r'<(?:article|div)[^>]+class="[^"]*(?:blog|post|card|entry)[^"]*"[^>]*>[\s\S]*?<\/(?:article|div)>', caseSensitive: false).firstMatch(html);
  if (postMatch != null) {
    print('\nSample card snippet:\n${postMatch.group(0)?.substring(0, 300)}');
  }
}
