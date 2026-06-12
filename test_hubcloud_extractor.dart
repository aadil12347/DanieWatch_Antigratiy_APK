import 'dart:convert';
import 'dart:io';

void main() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (cert, host, port) => true;

  final mainUrl = 'https://hubcloud.foo/drive/beew6tiegb42e3i';
  print('=== HUBCLOUD.FOO STANDALONE EXTRACTOR ===');
  print('Main URL: $mainUrl');

  try {
    // Step 1: Fetch main page
    print('\n[Step 1] Fetching main page...');
    final req = await client.getUrl(Uri.parse(mainUrl));
    req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    final resp = await req.close();
    if (resp.statusCode != 200) {
      print('Failed to load main page: ${resp.statusCode}');
      return;
    }
    final html = await resp.transform(utf8.decoder).join();
    print('Main page fetched successfully. Length: ${html.length} bytes');

    // Step 2: Extract Base64 token URL
    print('\n[Step 2] Extracting Base64 token URL...');
    final atobRegExp = RegExp(r'''url\s*=\s*atob\(['"]([A-Za-z0-9+/=]+)['"]\)''', caseSensitive: false);
    final match = atobRegExp.firstMatch(html);
    if (match == null) {
      print('Error: Could not locate Base64 encoded token URL in HTML.');
      return;
    }
    final base64Str = match.group(1)!;
    print('  Found Base64 string: $base64Str');

    // Decode Base64
    final decodedBytes = base64.decode(base64Str);
    final tokenPageUrl = utf8.decode(decodedBytes);
    print('  Decoded Token Page URL: $tokenPageUrl');

    // Step 3: Fetch token page
    print('\n[Step 3] Fetching token page from gamerxyt...');
    final req2 = await client.getUrl(Uri.parse(tokenPageUrl));
    req2.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    req2.headers.set('Referer', mainUrl);
    final resp2 = await req2.close();
    if (resp2.statusCode != 200) {
      print('Failed to load token page: ${resp2.statusCode}');
      return;
    }
    final tokenHtml = await resp2.transform(utf8.decoder).join();
    print('Token page HTML fetched successfully. Length: ${tokenHtml.length} bytes');

    // Step 4: Parse download servers
    print('\n[Step 4] Parsing download servers...');
    final Map<String, String> resolved = {};
    final aTagRegExp = RegExp(r'<a\s+([^>]+)>(.*?)</a>', caseSensitive: false, dotAll: true);
    final hrefAttrRegExp = RegExp(r'''href=["']([^"']+)["']''', caseSensitive: false);
    final idAttrRegExp = RegExp(r'''id=["']([^"']+)["']''', caseSensitive: false);
    
    final matches = aTagRegExp.allMatches(tokenHtml);
    print('Found ${matches.length} total anchor links in token HTML.');

    final minutes = DateTime.now().minute;

    for (var match in matches) {
      final attributes = match.group(1)!;
      final innerHtml = match.group(2) ?? '';
      
      final hrefMatch = hrefAttrRegExp.firstMatch(attributes);
      if (hrefMatch == null) continue;
      
      final href = hrefMatch.group(1)!;
      if (href == '#' || href.isEmpty) continue;

      final idMatch = idAttrRegExp.firstMatch(attributes);
      final id = idMatch?.group(1) ?? '';

      // Server 1: FSL
      if (id == 'fsl' || innerHtml.contains('[FSL Server]')) {
        resolved['Server 1'] = href + '1$minutes';
        print('  Server 1 (FSL): $href -> ${resolved['Server 1']}');
      } 
      // Server 2: FSLv2 (s3)
      else if (id == 's3' || innerHtml.contains('[FSLv2 Server]')) {
        // If the URL contains cloudflarestorage/r2.dev/signatures, don't append suffix
        if (href.contains('X-Amz-Signature') || href.contains('r2.cloudflarestorage') || href.contains('r2.dev')) {
          resolved['Server 2'] = href;
        } else {
          // Otherwise, append '_1' + minutes to FSLv2 Server
          resolved['Server 2'] = href + '_1$minutes';
        }
        print('  Server 2 (FSLv2): $href -> ${resolved['Server 2']}');
      } 
      // Server 3: HubCloud / 10Gbps
      else if (innerHtml.contains('[Server : 10Gbps]') || 
               href.contains('pixel.hubcloud') || 
               href.contains('gpdl') || 
               (href.contains('hubcloud') && href.contains('id='))) {
        // Exclude telegram and admin links explicitly
        if (href.contains('telegram') || href.contains('t.me') || href.contains('admin') || href.contains('/tg/')) {
          continue;
        }
        resolved['Server 3'] = href;
        print('  Server 3 (HubCloud): $href');
      }
    }

    // Step 5: Pre-resolve Server 3 redirects to get Google Drive direct url
    if (resolved.containsKey('Server 3')) {
      print('\n[Step 5] Resolving Server 3 redirects...');
      final hubUrl = resolved['Server 3']!;
      final directGDriveUrl = await resolveRedirects(hubUrl, client);
      if (directGDriveUrl != null) {
        resolved['Server 3'] = directGDriveUrl;
        print('  Successfully resolved Server 3 to direct GDrive: $directGDriveUrl');
      } else {
        print('  Failed to resolve Server 3 redirects.');
      }
    }

    print('\n=== FINAL EXTRACTION RESULTS ===');
    resolved.forEach((server, url) {
      print('  $server: $url');
    });

  } catch (e) {
    print('Extraction error: $e');
  } finally {
    client.close(force: true);
    print('\n=== EXTRACTION COMPLETE ===');
  }
}

Future<String?> resolveRedirects(String url, HttpClient client) async {
  final headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  try {
    var currentUrl = url;
    var redirectCount = 0;

    while (redirectCount < 10) {
      print('    Hop $redirectCount: $currentUrl');
      
      final uri = Uri.parse(currentUrl);
      if (uri.queryParameters.containsKey('link')) {
        final directLink = uri.queryParameters['link']!;
        print('    Found "link=" parameter in URL!');
        return directLink;
      }

      final req = await client.getUrl(Uri.parse(currentUrl));
      headers.forEach((k, v) => req.headers.set(k, v));
      req.followRedirects = false;
      final resp = await req.close();

      final loc = resp.headers.value('location');
      if (loc != null) {
        if (loc.startsWith('http')) {
          currentUrl = loc;
        } else {
          currentUrl = Uri.parse(currentUrl).resolve(loc).toString();
        }
        redirectCount++;
      } else {
        // Read body to check for JS redirects or meta refresh
        final body = await resp.transform(utf8.decoder).join();
        
        final jsLocMatch = RegExp(r'''window\.location\s*=\s*['"](https?://[^'"]+)['"]''', caseSensitive: false).firstMatch(body);
        final jsLocHrefMatch = RegExp(r'''window\.location\.href\s*=\s*['"](https?://[^'"]+)['"]''', caseSensitive: false).firstMatch(body);
        final metaRefreshMatch = RegExp(r'''<meta\s+http-equiv=["']refresh["']\s+content=["']\d+;\s*url=([^"']+)["']''', caseSensitive: false).firstMatch(body);
        
        // Exclude blocker/ad redirects in window.location
        if (jsLocMatch != null && !jsLocMatch.group(1)!.contains('bonuscaf.com') && !jsLocMatch.group(1)!.contains('go/')) {
          currentUrl = jsLocMatch.group(1)!;
          redirectCount++;
          print('    Followed window.location JS redirect to: $currentUrl');
        } else if (jsLocHrefMatch != null && !jsLocHrefMatch.group(1)!.contains('bonuscaf.com') && !jsLocHrefMatch.group(1)!.contains('go/')) {
          currentUrl = jsLocHrefMatch.group(1)!;
          redirectCount++;
          print('    Followed window.location.href JS redirect to: $currentUrl');
        } else if (metaRefreshMatch != null) {
          currentUrl = metaRefreshMatch.group(1)!;
          redirectCount++;
          print('    Followed Meta Refresh to: $currentUrl');
        } else {
          break;
        }
      }
    }

    final uri = Uri.parse(currentUrl);
    if (uri.queryParameters.containsKey('link')) {
      return uri.queryParameters['link']!;
    }
  } catch (e) {
    print('    Redirect resolution error: $e');
  }
  return null;
}
