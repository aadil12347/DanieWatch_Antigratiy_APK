import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (cert, host, port) => true;

  // We will run the extraction logic first to get the latest working links for the movie/series.
  final mainUrl = 'https://vcloud.zip/fwpydo7j1ommkyj';
  print('=== EXTRACTING LATEST LINKS ===');
  
  try {
    final req = await client.getUrl(Uri.parse(mainUrl));
    req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    final resp = await req.close();
    final html = await resp.transform(utf8.decoder).join();

    String? tokenUrl;
    final varUrlRegExp = RegExp(r'''var\s+url\s*=\s*['"](https?://[^'"]+)['"]''', caseSensitive: false);
    final varUrlMatch = varUrlRegExp.firstMatch(html);
    if (varUrlMatch != null) {
      tokenUrl = varUrlMatch.group(1);
    }
    
    if (tokenUrl != null) {
      final req2 = await client.getUrl(Uri.parse(tokenUrl));
      req2.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      req2.headers.set('Referer', mainUrl);
      final resp2 = await req2.close();
      final tokenHtml = await resp2.transform(utf8.decoder).join();

      final Map<String, String> resolved = {};
      final aTagRegExp = RegExp(r'<a\s+([^>]+)>(.*?)</a>', caseSensitive: false, dotAll: true);
      final hrefAttrRegExp = RegExp(r'''href=["']([^"']+)["']''', caseSensitive: false);
      final idAttrRegExp = RegExp(r'''id=["']([^"']+)["']''', caseSensitive: false);
      
      final matches = aTagRegExp.allMatches(tokenHtml);
      for (var match in matches) {
        final attributes = match.group(1)!;
        final innerHtml = match.group(2) ?? '';
        final hrefMatch = hrefAttrRegExp.firstMatch(attributes);
        if (hrefMatch == null) continue;
        final href = hrefMatch.group(1)!;
        if (href == '#' || href.isEmpty) continue;
        final idMatch = idAttrRegExp.firstMatch(attributes);
        final id = idMatch?.group(1) ?? '';

        if (id == 'fsl' || innerHtml.contains('[FSL Server]')) {
          final minutes = DateTime.now().minute;
          resolved['Server 1 (FSL)'] = href + '1$minutes';
        } else if (id == 's3' || innerHtml.contains('[FSLv2 Server]')) {
          resolved['Server 2 (FSLv2)'] = href;
        } else if (innerHtml.contains('[Server : 10Gbps]') || href.contains('hubcloud') || href.contains('gpdl')) {
          resolved['Server 3 (Gbps)'] = href;
        }
      }

      // Resolve Server 3 redirect
      if (resolved.containsKey('Server 3 (Gbps)')) {
        final hubUrl = resolved['Server 3 (Gbps)']!;
        var currentUrl = hubUrl;
        var redirectCount = 0;
        while (redirectCount < 8) {
          final uri = Uri.parse(currentUrl);
          if (uri.queryParameters.containsKey('link')) {
            resolved['Server 3 (Gbps)'] = uri.queryParameters['link']!;
            break;
          }
          final req3 = await client.getUrl(Uri.parse(currentUrl));
          req3.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
          req3.followRedirects = false;
          final resp3 = await req3.close();
          final loc = resp3.headers.value('location');
          if (loc != null) {
            currentUrl = loc.startsWith('http') ? loc : Uri.parse(currentUrl).resolve(loc).toString();
            redirectCount++;
          } else {
            final body = await resp3.transform(utf8.decoder).join();
            final jsLocMatch = RegExp(r'''window\.location\s*=\s*['"](https?://[^'"]+)['"]''', caseSensitive: false).firstMatch(body);
            if (jsLocMatch != null) {
              currentUrl = jsLocMatch.group(1)!;
              redirectCount++;
            } else {
              break;
            }
          }
        }
      }

      print('\n=== TESTING HEADERS FOR EACH SERVER ===');
      for (var entry in resolved.entries) {
        print('\n--- Testing ${entry.key} ---');
        print('URL: ${entry.value}');
        try {
          final testReq = await client.getUrl(Uri.parse(entry.value));
          // Test with User-Agent only first
          testReq.headers.set('User-Agent', 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36');
          // Send a range request to see if it responds with 206 Partial Content (important for streaming)
          testReq.headers.set('Range', 'bytes=0-100');
          
          final testResp = await testReq.close();
          print('HTTP Status: ${testResp.statusCode}');
          testResp.headers.forEach((name, values) {
            print('  $name: ${values.join(", ")}');
          });
          // Cancel the response stream to prevent hanging
          await testResp.listen((_) {}).cancel();
        } catch (e) {
          print('Error requesting ${entry.key}: $e');
        }
      }
    }
  } catch (e) {
    print('Error during test: $e');
  } finally {
    client.close();
  }
}
