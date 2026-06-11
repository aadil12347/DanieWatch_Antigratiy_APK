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

Future<bool> _testLink(String url) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..badCertificateCallback = (cert, host, port) => true;
  try {
    final req = await client.headUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    final resp = await req.close();
    print('Testing URL: $url -> Status: ${resp.statusCode}');
    client.close();
    return resp.statusCode < 400;
  } catch (e) {
    print('Testing URL: $url -> Error: $e');
    client.close();
    return false;
  }
}

Future<void> main() async {
  final urls = [
    'https://vcloud.zip/fwpydo7j1ommkyj',
    'https://hubcloud.foo/drive/guvqvqxbk1k1fsf',
  ];

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (cert, host, port) => true;

  final headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  for (final url in urls) {
    print('\n======================================');
    print('Processing URL: $url');

    try {
      // Step 1: Fetch main page
      print('Fetching main page...');
      final req = await client.getUrl(Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      print('Main Page Status Code: ${resp.statusCode}');
      if (resp.statusCode != 200) {
        continue;
      }
      final html = await resp.transform(utf8.decoder).join();
      print('Main Page Length: ${html.length}');

      // Step 2: Check for direct servers on main page (only should succeed if this is a pre-generated page)
      var servers = _parseServerLinks(html);
      if (servers.isNotEmpty) {
        print('Found server links directly on the main page:');
        servers.forEach((k, v) => print('  $k: $v'));
        continue;
      }

      // Step 3: Parse token/button URL
      String? tokenUrl;
      final varUrlRegExp = RegExp(r'''var\s+url\s*=\s*['"](https?://[^'"]+)['"]''', caseSensitive: false);
      final varUrlMatch = varUrlRegExp.firstMatch(html);
      if (varUrlMatch != null) {
        tokenUrl = varUrlMatch.group(1);
        print('Extracted token URL from JS variable: $tokenUrl');
      }

      if (tokenUrl == null) {
        final aTagRegExp = RegExp(r'<a\s+([^>]+)>(.*?)</a>', caseSensitive: false, dotAll: true);
        final hrefAttrRegExp = RegExp(r'''href=["']([^"']+)["']''', caseSensitive: false);
        final idAttrRegExp = RegExp(r'''id=["']([^"']+)["']''', caseSensitive: false);
        
        final matches = aTagRegExp.allMatches(html);
        for (var match in matches) {
          final attributes = match.group(1)!;
          final innerHtml = match.group(2) ?? '';
          
          final idMatch = idAttrRegExp.firstMatch(attributes);
          final id = idMatch?.group(1) ?? '';
          
          if (id == 'download' || 
              innerHtml.toLowerCase().contains('generate direct download') || 
              innerHtml.toLowerCase().contains('generate download')) {
            final hrefMatch = hrefAttrRegExp.firstMatch(attributes);
            if (hrefMatch != null) {
              final href = hrefMatch.group(1)!;
              if (href.isNotEmpty && href.startsWith('http')) {
                tokenUrl = href;
                print('Extracted token URL from anchor tag: $tokenUrl');
                break;
              }
            }
          }
        }
      }

      if (tokenUrl == null) {
        print('Could not find token URL or download button on the main page.');
        continue;
      }

      // Step 4: Fetch token page with referer
      print('Fetching token page...');
      final req2 = await client.getUrl(Uri.parse(tokenUrl));
      headers.forEach((k, v) => req2.headers.set(k, v));
      req2.headers.set('Referer', url);
      final resp2 = await req2.close();
      print('Token Page Status Code: ${resp2.statusCode}');
      if (resp2.statusCode != 200) {
        continue;
      }
      final html2 = await resp2.transform(utf8.decoder).join();
      print('Token Page Length: ${html2.length}');

      // Step 5: Parse servers from token page
      servers = _parseServerLinks(html2);
      print('Resolved servers from token page:');
      for (final entry in servers.entries) {
        final key = entry.key;
        final val = entry.value;
        final isValid = await _testLink(val);
        print('  $key: $val (Valid? $isValid)');
      }

    } catch (e) {
      print('Error during pipeline: $e');
    }
  }

  client.close();
}
