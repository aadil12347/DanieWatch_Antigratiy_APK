import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<String> fetchHtml(HttpClient client, String url, {String? referer}) async {
  try {
    final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
    req.headers.set(HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36');
    req.headers.set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    if (referer != null) req.headers.set(HttpHeaders.refererHeader, referer);
    final resp = await req.close().timeout(const Duration(seconds: 10));
    final buffer = StringBuffer();
    await for (final chunk in resp.transform(utf8.decoder)) {
      buffer.write(chunk);
    }
    return buffer.toString();
  } catch (e) {
    print('Error fetching $url: $e');
    return '';
  }
}

void main() async {
  print('===============================================================');
  print('🔍 Step 1: Deep Analysis of Game of Thrones Post Page');
  print('===============================================================\n');

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..badCertificateCallback = (cert, host, port) => true;

  const gotUrl = 'https://vegamovies.gallery/download-game-of-thrones-season-1-8-hindi-dubbed-org-480p-720p-1080p-bluray/';
  final gotHtml = await fetchHtml(client, gotUrl);
  print('Got HTML length: ${gotHtml.length} characters\n');

  // Find all buttons / anchor tags with hrefs pointing to nexdrive, fastdl, vcloud, gdflix, vgmlink, etc.
  final anchorRegex = RegExp(r'<a\s+[^>]*href=["\x27]([^"\x27]+)["\x27][^>]*>(.*?)</a>', caseSensitive: false, dotAll: true);
  
  final allLinks = <Map<String, String>>[];
  for (final m in anchorRegex.allMatches(gotHtml)) {
    final href = m.group(1)!.trim();
    final text = m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final lh = href.toLowerCase();
    
    final isSupported = lh.contains('nexdrive') ||
        lh.contains('fastdl') ||
        lh.contains('vcloud') ||
        lh.contains('hubcloud') ||
        lh.contains('gdflix') ||
        lh.contains('vgmlink') ||
        lh.contains('filebee') ||
        lh.contains('vegadrive');
        
    if (isSupported) {
      allLinks.add({'href': href, 'text': text});
    }
  }

  print('Total supported download/episode anchors found on GOT post: ${allLinks.length}\n');
  print('Sample of anchors found:');
  for (int i = 0; i < allLinks.length && i < 30; i++) {
    print('  [$i] text: "${allLinks[i]['text']}" -> href: "${allLinks[i]['href']}"');
  }

  // Check how buttons are grouped by season
  print('\n---------------------------------------------------------------');
  print('🔍 Step 2: Finding Another TV Series from Vegamovies Homepage');
  print('---------------------------------------------------------------\n');
  final homeHtml = await fetchHtml(client, 'https://vegamovies.gallery/');
  final articleRegex = RegExp(r'<article[^>]*>.*?<a\s+[^>]*href=["\x27]([^"\x27]+)["\x27][^>]*title=["\x27]([^"\x27]+)["\x27]', dotAll: true, caseSensitive: false);
  
  String? otherSeriesUrl;
  String? otherSeriesTitle;
  for (final m in articleRegex.allMatches(homeHtml)) {
    final href = m.group(1)!;
    final title = m.group(2)!;
    final lt = title.toLowerCase();
    if ((lt.contains('season') || lt.contains('series') || lt.contains('s01') || lt.contains('s02')) && !lt.contains('game of thrones')) {
      otherSeriesUrl = href;
      otherSeriesTitle = title;
      break;
    }
  }

  print('Other Series Candidate: "$otherSeriesTitle"');
  print('URL: $otherSeriesUrl\n');

  if (otherSeriesUrl != null) {
    final otherHtml = await fetchHtml(client, otherSeriesUrl);
    final otherLinks = <Map<String, String>>[];
    for (final m in anchorRegex.allMatches(otherHtml)) {
      final href = m.group(1)!.trim();
      final text = m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
      final lh = href.toLowerCase();
      
      final isSupported = lh.contains('nexdrive') ||
          lh.contains('fastdl') ||
          lh.contains('vcloud') ||
          lh.contains('hubcloud') ||
          lh.contains('gdflix') ||
          lh.contains('vgmlink') ||
          lh.contains('filebee') ||
          lh.contains('vegadrive');
          
      if (isSupported) {
        otherLinks.add({'href': href, 'text': text});
      }
    }
    print('Total supported anchors on $otherSeriesTitle: ${otherLinks.length}');
    for (int i = 0; i < otherLinks.length && i < 20; i++) {
      print('  [$i] text: "${otherLinks[i]['text']}" -> href: "${otherLinks[i]['href']}"');
    }
  }

  client.close();
}
