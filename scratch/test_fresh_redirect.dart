import 'dart:convert';
import 'dart:io';

Map<String, String> _parseServerLinks(String html) {
  final Map<String, String> resolved = {};
  final aTagRegExp = RegExp(r'<a\s+([^>]+)>(.*?)</a>', caseSensitive: false, dotAll: true);
  final hrefAttrRegExp = RegExp(r'''href=["']([^"']+)["']''', caseSensitive: false);
  final idAttrRegExp = RegExp(r'''id=["']([^"']+)["']''', caseSensitive: false);
  
  final matches = aTagRegExp.allMatches(html);

  for (var match in matches) {
    final attributes = match.group(1)!;
    final innerHtml = match.group(2) ?? '';
    
    final hrefMatch = hrefAttrRegExp.firstMatch(attributes);
    if (hrefMatch == null) continue;
    
    final href = hrefMatch.group(1)!;
    if (href == '#' || href.isEmpty) continue;
    
    // Exclude irrelevant links
    final hrefLower = href.toLowerCase();
    if (hrefLower.contains('css') || 
        hrefLower.contains('fonts') || 
        hrefLower.contains('favicon') || 
        hrefLower.contains('manifest') || 
        hrefLower.contains('telegram') || 
        hrefLower.contains('t.me') || 
        hrefLower.contains('google.com') ||
        hrefLower.contains('github.com') ||
        hrefLower.contains('admin') ||
        hrefLower.contains('login') ||
        hrefLower.contains('signup') ||
        hrefLower.contains('sign-up') ||
        hrefLower.contains('create') ||
        hrefLower.contains('account') ||
        hrefLower.contains('hubcloud.php')) {
      continue;
    }

    final idMatch = idAttrRegExp.firstMatch(attributes);
    final id = idMatch?.group(1) ?? '';

    if (id == 'fsl' || innerHtml.contains('[FSL Server]')) {
      final minutes = DateTime.now().minute;
      resolved['Server 1'] = href.contains('X-Amz-Signature') || href.contains('r2.cloudflarestorage')
          ? href
          : href + '1$minutes';
    } else if (id == 's3' || innerHtml.contains('[FSLv2 Server]')) {
      final minutes2 = DateTime.now().minute;
      resolved['Server 2'] = href.contains('X-Amz-Signature') || href.contains('r2.cloudflarestorage')
          ? href
          : href + '1$minutes2';
    } else if (attributes.contains('btn-danger') || 
               innerHtml.contains('[Server : 10Gbps]') || 
               (href.contains('hubcloud') && (href.contains('id=') || href.contains('/tg/'))) || 
               href.contains('gpdl')) {
      resolved['Server 3'] = href;
    }
  }
  return resolved;
}

Future<String?> resolveHubCloudRedirect(String url) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (cert, host, port) => true;

  final headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  try {
    var currentUrl = url;
    var redirectCount = 0;
    String? finalUrl;

    while (redirectCount < 8) {
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
        finalUrl = currentUrl;
        break;
      }
    }

    if (finalUrl != null) {
      final uri = Uri.parse(finalUrl);
      if (uri.queryParameters.containsKey('link')) {
        return uri.queryParameters['link']!;
      }
    }

    final uri = Uri.parse(currentUrl);
    if (uri.queryParameters.containsKey('link')) {
      return uri.queryParameters['link']!;
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
  return null;
}

Future<void> main() async {
  final url = 'https://hubcloud.foo/drive/guvqvqxbk1k1fsf';

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (cert, host, port) => true;

  final headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  try {
    print('1. Fetching fresh main page...');
    final req = await client.getUrl(Uri.parse(url));
    headers.forEach((k, v) => req.headers.set(k, v));
    final resp = await req.close();
    final html = await resp.transform(utf8.decoder).join();

    // Parse token URL
    String? tokenUrl;
    final varUrlRegExp = RegExp(r'''var\s+url\s*=\s*['"](https?://[^'"]+)['"]''', caseSensitive: false);
    final varUrlMatch = varUrlRegExp.firstMatch(html);
    if (varUrlMatch != null) {
      tokenUrl = varUrlMatch.group(1);
      print('Extracted fresh token URL: $tokenUrl');
    }

    if (tokenUrl == null) {
      print('Could not find token URL.');
      return;
    }

    print('2. Fetching fresh token page...');
    final req2 = await client.getUrl(Uri.parse(tokenUrl));
    headers.forEach((k, v) => req2.headers.set(k, v));
    req2.headers.set('Referer', url);
    final resp2 = await req2.close();
    final html2 = await resp2.transform(utf8.decoder).join();

    final servers = _parseServerLinks(html2);
    print('Resolved servers:');
    servers.forEach((k, v) => print('  $k: $v'));

    final gbpsUrl = servers['Server 3'];
    if (gbpsUrl != null) {
      print('3. Resolving fresh Gbps/Server 3 redirect: $gbpsUrl');
      final directVideoLink = await resolveHubCloudRedirect(gbpsUrl);
      if (directVideoLink != null) {
        print('\nSUCCESS!');
        print('Captured direct video link:');
        print(directVideoLink);
        
        // Verification HEAD request on final video URL
        print('4. Verifying direct video link via HEAD request...');
        final req3 = await client.headUrl(Uri.parse(directVideoLink));
        req3.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
        final resp3 = await req3.close();
        print('Video URL HTTP Status Code: ${resp3.statusCode}');
        if (resp3.headers.value('content-type') != null) {
          print('Content-Type: ${resp3.headers.value('content-type')}');
        }
        if (resp3.headers.value('content-length') != null) {
          print('Content-Length: ${resp3.headers.value('content-length')} bytes');
        }
      } else {
        print('Failed to resolve Gbps direct link.');
      }
    } else {
      print('No Gbps URL found.');
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
