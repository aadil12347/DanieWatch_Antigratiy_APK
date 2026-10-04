import 'dart:convert';
import 'dart:io';

Future<String> fetchPage(String url) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (cert, host, port) => true;
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36');
    req.headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    final resp = await req.close();
    return await resp.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

void analyzeHtml(String title, String html) {
  print('================================================================');
  print('POST ANALYSIS: $title');
  print('HTML Length: ${html.length} chars');
  print('================================================================');

  // Extract all download links with nexdrive, vgmlink, gdflix, fastdl, vcloud, etc.
  final linkRegex = RegExp(r'<a\s+[^>]*href=["\x27](https?://[^"\x27]*(?:nexdrive|vgmlink|vcloud|hubcloud|fastdl|filebee|gdflix)[^"\x27]*)["\x27][^>]*>(.*?)</a>', caseSensitive: false, dotAll: true);
  final links = linkRegex.allMatches(html).toList();
  print('Found ${links.length} download/episode links in page.\n');

  // Let's find headings and button blocks
  final headingRegex = RegExp(r'<(h[1-6]|p|div|strong)[^>]*>(.*?)</\1>', caseSensitive: false, dotAll: true);
  final headings = <Map<String, dynamic>>[];
  for (final m in headingRegex.allMatches(html)) {
    final raw = m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    final low = raw.toLowerCase();
    if (low.contains('season') || low.contains('480p') || low.contains('720p') || low.contains('1080p') || low.contains('2160p') || low.contains('download')) {
      headings.add({
        'pos': m.start,
        'tag': m.group(1),
        'text': raw.length > 90 ? '${raw.substring(0, 90)}...' : raw,
      });
    }
  }

  print('Total Relevant Headings: ${headings.length}');
  for (final h in headings.take(15)) {
    print('  [${h['tag']}] ${h['text']}');
  }

  print('\nAnalyzing Download Links & closest preceding heading:');
  for (int i = 0; i < links.length; i++) {
    final l = links[i];
    final url = l.group(1)!;
    final text = l.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    final pos = l.start;

    // Find the closest preceding heading
    String closestHeading = 'None';
    for (final h in headings) {
      if (h['pos'] < pos) {
        closestHeading = h['text'];
      } else {
        break;
      }
    }

    print('  #${(i+1).toString().padLeft(2)} Text: "${text.padRight(28)}" | Heading: "$closestHeading" | URL: $url');
  }
}

void main() async {
  final posts = [
    {
      'title': 'Breaking Bad (Seasons 1-5)',
      'url': 'https://vegamovies.gallery/download-breaking-bad-season-5-complete-hindi-org-dubbed-web-dl-480p-720p-1080p/',
    },
    {
      'title': 'Vikings (Seasons 1-6)',
      'url': 'https://vegamovies.gallery/download-vikings-season-1-6-hindi-org-dubbed-complete-series-480p-720p/',
    },
    {
      'title': 'Game of Thrones (Seasons 1-8)',
      'url': 'https://vegamovies.gallery/download-game-of-thrones-season-1-8-hindi-dubbed-org-480p-720p-1080p-bluray/',
    }
  ];

  for (final p in posts) {
    try {
      print('\nFetching ${p['title']}...');
      final html = await fetchPage(p['url']!);
      analyzeHtml(p['title']!, html);
    } catch (e) {
      print('Error analyzing ${p['title']}: $e');
    }
  }
}
