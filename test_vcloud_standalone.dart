import 'dart:convert';
import 'dart:io';

void main() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (cert, host, port) => true;

  final mainUrl = 'https://vcloud.zip/fwpydo7j1ommkyj';
  print('=== STARTING VCLOUD STANDALONE EXTRACTION ===');
  print('Main URL: $mainUrl');

  try {
    // Step 1: Fetch landing page
    print('\n[Step 1] Fetching landing page...');
    final req = await client.getUrl(Uri.parse(mainUrl));
    req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    final resp = await req.close();
    if (resp.statusCode != 200) {
      print('Failed to load landing page: ${resp.statusCode}');
      return;
    }
    final html = await resp.transform(utf8.decoder).join();
    print('Landing page fetched successfully. Length: ${html.length} bytes');

    // Step 2: Extract token URL from JS variable or generate button
    print('\n[Step 2] Extracting token URL...');
    String? tokenUrl;
    final varUrlRegExp = RegExp(r'''var\s+url\s*=\s*['"](https?://[^'"]+)['"]''', caseSensitive: false);
    final varUrlMatch = varUrlRegExp.firstMatch(html);
    if (varUrlMatch != null) {
      tokenUrl = varUrlMatch.group(1);
      print('  Found token URL in JS: $tokenUrl');
    } else {
      // Fallback: search for anchor button with id="download"
      final aTagRegExp = RegExp(r'<button\s+([^>]+)>(.*?)</button>', caseSensitive: false, dotAll: true);
      final hrefAttrRegExp = RegExp(r'''href=["']([^"']+)["']''', caseSensitive: false);
      final idAttrRegExp = RegExp(r'''id=["']([^"']+)["']''', caseSensitive: false);
      
      final matches = aTagRegExp.allMatches(html);
      for (var match in matches) {
        final attributes = match.group(1)!;
        final idMatch = idAttrRegExp.firstMatch(attributes);
        final id = idMatch?.group(1) ?? '';
        if (id == 'download') {
          // Check if there is a link
          final hrefMatch = hrefAttrRegExp.firstMatch(attributes);
          if (hrefMatch != null) {
            tokenUrl = hrefMatch.group(1);
            print('  Found token URL on button: $tokenUrl');
            break;
          }
        }
      }
    }

    if (tokenUrl == null) {
      // Let's check if the main URL already contains the token
      if (mainUrl.contains('token=')) {
        tokenUrl = mainUrl;
        print('  Using main URL as token URL: $tokenUrl');
      } else {
        print('  Error: Could not locate token URL or download button on main page.');
        return;
      }
    }

    // Step 3: Fetch token page with Referer header
    print('\n[Step 3] Fetching token page...');
    final req2 = await client.getUrl(Uri.parse(tokenUrl));
    req2.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    req2.headers.set('Referer', mainUrl);
    final resp2 = await req2.close();
    if (resp2.statusCode != 200) {
      print('Failed to load token page: ${resp2.statusCode}');
      return;
    }
    final tokenHtml = await resp2.transform(utf8.decoder).join();
    print('Token page fetched successfully. Length: ${tokenHtml.length} bytes');

    // Step 4: Parse server links from token page HTML
    print('\n[Step 4] Parsing server links...');
    final Map<String, String> resolved = {};
    final aTagRegExp = RegExp(r'<a\s+([^>]+)>(.*?)</a>', caseSensitive: false, dotAll: true);
    final hrefAttrRegExp = RegExp(r'''href=["']([^"']+)["']''', caseSensitive: false);
    final idAttrRegExp = RegExp(r'''id=["']([^"']+)["']''', caseSensitive: false);
    
    final matches = aTagRegExp.allMatches(tokenHtml);
    print('Found ${matches.length} total anchor links in token HTML.');

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
        final minutes = DateTime.now().minute;
        resolved['Server 1'] = href + '1$minutes';
        print('  Matched Server 1 (FSL): $href -> (with minutes appended): ${resolved['Server 1']}');
      } 
      // Server 2: FSLv2
      else if (id == 's3' || innerHtml.contains('[FSLv2 Server]')) {
        resolved['Server 2'] = href;
        print('  Matched Server 2 (FSLv2): $href');
      } 
      // Server 3: HubCloud / 10Gbps
      else if (innerHtml.contains('[Server : 10Gbps]') || href.contains('hubcloud') || href.contains('gpdl')) {
        resolved['Server 3'] = href;
        print('  Matched Server 3 (HubCloud): $href');
      }
    }

    // Step 5: Pre-resolve Server 3 (HubCloud redirect) to get direct Google Drive link
    if (resolved.containsKey('Server 3')) {
      print('\n[Step 5] Resolving Server 3 redirects...');
      final hubUrl = resolved['Server 3']!;
      final directGDriveUrl = await resolveRedirects(hubUrl, client);
      if (directGDriveUrl != null) {
        resolved['Server 3'] = directGDriveUrl;
        print('  Successfully resolved Server 3 to GDrive direct link: $directGDriveUrl');
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

    while (redirectCount < 8) {
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
        // Read body to check if there is a meta refresh or script redirect
        final body = await resp.transform(utf8.decoder).join();
        // Check for window.location or similar in scripts
        final jsLocMatch = RegExp(r'''window\.location\s*=\s*['"](https?://[^'"]+)['"]''', caseSensitive: false).firstMatch(body);
        if (jsLocMatch != null) {
          currentUrl = jsLocMatch.group(1)!;
          redirectCount++;
          print('    Followed JavaScript redirect to: $currentUrl');
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
