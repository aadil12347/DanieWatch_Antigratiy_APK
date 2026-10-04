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

  final idx = html.indexOf('class="poster-card"');
  if (idx != -1) {
    print('Found poster-card at index $idx');
    final start = idx > 100 ? idx - 50 : 0;
    final end = (idx + 1200) < html.length ? idx + 1200 : html.length;
    print(html.substring(start, end));
  } else {
    print('poster-card not found with exact class="poster-card"');
    // Look for poster-card with any quotes or spacing
    final m = RegExp(r'class=["\x27][^"\x27]*poster-card[^"\x27]*["\x27]').firstMatch(html);
    if (m != null) {
      print('Found match: ${m.group(0)}');
    }
  }
}
