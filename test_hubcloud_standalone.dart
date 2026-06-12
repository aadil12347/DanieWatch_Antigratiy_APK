import 'dart:convert';
import 'dart:io';

void main() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (cert, host, port) => true;

  final mainUrl = 'https://hubcloud.foo/drive/beew6tiegb42e3i';
  print('=== STARTING HUBCLOUD.FOO STANDALONE EXTRACTION ===');
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

    // Step 3: Decode Base64 to get redirect URL
    final decodedBytes = base64.decode(base64Str);
    final redirectUrl = utf8.decode(decodedBytes);
    print('  Decoded URL: $redirectUrl');

    // Step 4: Resolve redirects dynamically
    print('\n[Step 4] Resolving redirects...');
    final directUrl = await resolveRedirects(redirectUrl, client);
    if (directUrl != null) {
      print('\n=== FINAL EXTRACTION RESULT ===');
      print('  Direct Stream URL: $directUrl');
    } else {
      print('  Failed to resolve direct streaming URL.');
    }

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
        // Check if there is a JS redirect or Meta refresh in the body
        final body = await resp.transform(utf8.decoder).join();
        
        final jsLocMatch = RegExp(r'''window\.location\s*=\s*['"](https?://[^'"]+)['"]''', caseSensitive: false).firstMatch(body);
        final jsLocHrefMatch = RegExp(r'''window\.location\.href\s*=\s*['"](https?://[^'"]+)['"]''', caseSensitive: false).firstMatch(body);
        final metaRefreshMatch = RegExp(r'''<meta\s+http-equiv=["']refresh["']\s+content=["']\d+;\s*url=([^"']+)["']''', caseSensitive: false).firstMatch(body);
        
        if (jsLocMatch != null) {
          currentUrl = jsLocMatch.group(1)!;
          redirectCount++;
          print('    Followed window.location JS redirect to: $currentUrl');
        } else if (jsLocHrefMatch != null) {
          currentUrl = jsLocHrefMatch.group(1)!;
          redirectCount++;
          print('    Followed window.location.href JS redirect to: $currentUrl');
        } else if (metaRefreshMatch != null) {
          currentUrl = metaRefreshMatch.group(1)!;
          redirectCount++;
          print('    Followed Meta Refresh to: $currentUrl');
        } else {
          // If no redirect header and no JS/Meta refresh, maybe check query parameters of current URL one last time
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
