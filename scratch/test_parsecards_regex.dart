import 'dart:convert';
import 'dart:io';

String cleanTitle(String rawTitle) {
  var t = rawTitle
      .replaceAll(RegExp(r'&amp;#038;', caseSensitive: false), '&')
      .replaceAll(RegExp(r'&#038;', caseSensitive: false), '&')
      .replaceAll(RegExp(r'&amp;', caseSensitive: false), '&');
  t = t.replaceAll(RegExp(r'^(?:Download\s+)+', caseSensitive: false), '');
  return t.trim();
}

void main() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final uri = Uri.parse('https://vegamovies.gallery/korean-series/');
  final req = await client.getUrl(uri);
  req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36');
  final resp = await req.close();
  final html = await resp.transform(utf8.decoder).join();
  client.close();

  final cardRegex = RegExp(
    r'<div class="poster-card"[^>]*>([\s\S]*?)<\/div>\s*<\/div>\s*<\/div>',
    caseSensitive: false,
  );

  final urlRegex = RegExp(r'<meta itemprop="url" content="([^"]+)"|<a\s+[^>]*href="([^"]+)"', caseSensitive: false);
  final imgRegex = RegExp(r'<img[^>]+(?:src|data-src)="([^"]+)"', caseSensitive: false);
  final altRegex = RegExp(r'alt="([^"]+)"', caseSensitive: false);
  final titleRegex = RegExp(r'class="poster-title"[^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>', caseSensitive: false);

  final matches = cardRegex.allMatches(html).toList();
  print('cardRegex matches found: ${matches.length}');

  for (int i = 0; i < matches.length && i < 5; i++) {
    final block = matches[i].group(1) ?? '';
    final urlM = urlRegex.firstMatch(block);
    final postUrl = urlM?.group(1) ?? urlM?.group(2);
    final imgM = imgRegex.firstMatch(block);
    final altM = altRegex.firstMatch(block);
    final titleM = titleRegex.firstMatch(block);
    final rawTitle = altM?.group(1) ?? (titleM?.group(1) ?? '');
    final title = cleanTitle(rawTitle);
    print('[$i] title: "$title" | postUrl: $postUrl | img: ${imgM?.group(1)}');
  }
}
