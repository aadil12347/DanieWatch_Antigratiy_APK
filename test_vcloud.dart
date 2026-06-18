import 'dart:convert';
import 'dart:io';

void main() async {
  final client = HttpClient();
  
  // 1. Fetch the JSON file from the GitHub repo
  final url = 'https://raw.githubusercontent.com/aadil12347/DanieWatch_Apk_Database/main/streaming_links/Brown%20(Season%201)%20(2026)_series_226560.json';
  print('Fetching: $url');
  
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    
    final json = jsonDecode(body) as Map<String, dynamic>;
    print('Metadata:');
    print('Title: ${json['post_title']}');
    print('Type: ${json['post_type']}');
    print('TMDB ID: ${json['tmdb_id']}');
    
    // Let's print all links found for Season 1, Episode 1
    final seasons = json['seasons'] as Map<String, dynamic>?;
    if (seasons != null && seasons.containsKey('01')) {
      final s1 = seasons['01'] as Map<String, dynamic>;
      for (var res in s1.keys) {
        print('\nResolution: $res');
        final episodesList = s1[res] as List<dynamic>;
        // Get Episode 1
        final ep1 = episodesList.firstWhere(
          (ep) => ep['episode_title'] == 'Episode 1',
          orElse: () => null,
        );
        if (ep1 != null) {
          print('  Episode 1 link: ${ep1['link']}');
          // Let's extract the link using Vcloud extraction logic
          await extractVcloud(ep1['link'] as String, client);
        }
      }
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}

Future<void> extractVcloud(String vcloudUrl, HttpClient client) async {
  print('  -> Extracting from Vcloud: $vcloudUrl');
  final headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };
  
  try {
    // Step 1: Fetch base page
    final req = await client.getUrl(Uri.parse(vcloudUrl));
    headers.forEach((k, v) => req.headers.set(k, v));
    var resp = await req.close();
    var html = await resp.transform(utf8.decoder).join();
    
    print('    HTML Length: ${html.length}');
    final lines = html.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('token') || line.contains('var url')) {
        print('    Line ${i + 1}: ${line.trim()}');
      }
    }
    
    // Step 2: Extract token URL
    String? tokenUrl;
    final tokenRegExp = RegExp(r"var url\s*=\s*'(https?://[^'\s]+token=[^'\s]+)'");
    final match = tokenRegExp.firstMatch(html);
    if (match != null) {
      tokenUrl = match.group(1)!;
    } else {
      // Try double atob
      final atob2UrlRegExp = RegExp(r'''atob\(atob\(['"]([A-Za-z0-9+/=]{10,})['"]\)\)''', caseSensitive: false);
      final atob2UrlMatch = atob2UrlRegExp.firstMatch(html);
      if (atob2UrlMatch != null) {
        try {
          final decodedBytes1 = base64.decode(atob2UrlMatch.group(1)!);
          final decodedStr1 = utf8.decode(decodedBytes1);
          final decodedBytes2 = base64.decode(decodedStr1);
          tokenUrl = utf8.decode(decodedBytes2);
        } catch (e) {
          print('    Failed to decode double-base64: $e');
        }
      }
      // Try single atob
      if (tokenUrl == null) {
        final atobUrlRegExp = RegExp(r'''url\s*=\s*atob\(['"]([A-Za-z0-9+/=]{10,})['"]\)''', caseSensitive: false);
        final atobUrlMatch = atobUrlRegExp.firstMatch(html);
        if (atobUrlMatch != null) {
          try {
            final decodedBytes = base64.decode(atobUrlMatch.group(1)!);
            tokenUrl = utf8.decode(decodedBytes);
          } catch (e) {
            print('    Failed to decode single-base64: $e');
          }
        }
      }
    }

    if (tokenUrl == null) {
      print('    Error: Token URL not found in HTML');
      return;
    }
    print('    Found Token URL: $tokenUrl');
    
    // Step 3: Fetch token page with referer
    final req2 = await client.getUrl(Uri.parse(tokenUrl));
    headers.forEach((k, v) => req2.headers.set(k, v));
    req2.headers.set('Referer', vcloudUrl);
    resp = await req2.close();
    html = await resp.transform(utf8.decoder).join();
    
    // Step 4: Parse links
    final hrefRegExp = RegExp(r'''href=["']([^"']+)["']''');
    final matches = hrefRegExp.allMatches(html);
    final hrefs = matches.map((m) => m.group(1)!).toList();
    
    for (var href in hrefs) {
      if (href.contains('css') || href.contains('fonts') || href.contains('favicon') || href.contains('manifest') || href.contains('telegram') || href == '#') {
        continue;
      }
      
      print('    Extracted Href: $href');
      
      // Categorize and resolve if HubCloud / GPDL
      if (href.contains('hubcloud') || href.contains('gpdl')) {
        print('      Resolving GPDL/HubCloud redirect...');
        try {
          var currentUrl = href;
          var redirectCount = 0;
          String? finalUrl;
          
          while (redirectCount < 5) {
            final hcReq = await client.getUrl(Uri.parse(currentUrl));
            headers.forEach((k, v) => hcReq.headers.set(k, v));
            hcReq.followRedirects = false;
            final hcResp = await hcReq.close();
            
            final loc = hcResp.headers.value('location');
            if (loc != null) {
              print('        Hop ${redirectCount + 1}: $loc');
              if (loc.startsWith('http')) {
                currentUrl = loc;
              } else {
                currentUrl = Uri.parse(currentUrl).resolve(loc).toString();
              }
              redirectCount++;
            } else {
              finalUrl = currentUrl;
              break;
            }
          }
          
          if (finalUrl != null) {
            print('      Final Redirect URL: $finalUrl');
            final finalUri = Uri.parse(finalUrl);
            if (finalUri.queryParameters.containsKey('link')) {
              final directLink = finalUri.queryParameters['link']!;
              print('      -> Server 3 (Google Drive direct): $directLink');
            } else {
              // Sometimes the final URL is gamerxyt.com/dl.php?link=...
              // Check if the current URL or final URL query contains 'link'
              final uri = Uri.parse(currentUrl);
              if (uri.queryParameters.containsKey('link')) {
                final directLink = uri.queryParameters['link']!;
                print('      -> Server 3 (Google Drive direct): $directLink');
              }
            }
          }
        } catch (e) {
          print('      Error resolving HubCloud redirect: $e');
        }
      } else if (href.contains('obsession') || href.contains('hub')) {
        print('      -> Server 2 (Hub direct): $href');
      } else if (href.contains('r2') || href.contains('cloudflare')) {
        print('      -> Server 1 (Cloudflare R2 direct): $href');
      } else {
        print('      -> Other Server: $href');
      }
    }
  } catch (e) {
    print('    Extraction failed: $e');
  }
}
