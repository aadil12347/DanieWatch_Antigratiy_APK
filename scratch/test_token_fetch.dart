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
        hrefLower.contains('/admin') ||
        hrefLower.contains('/login')) {
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
               (href.contains('hubcloud') && !href.contains('report')) || 
               href.contains('gpdl')) {
      resolved['Server 3'] = href;
    }
  }
  return resolved;
}

Future<void> main() async {
  final mappings = {
    'https://vcloud.zip/fwpydo7j1ommkyj': 'https://gamerxyt.com/hubcloud.php?host=vcloud&id=fwpydo7j1ommkyj&token=ZE1Vd3dldkVRejNYRGhzcE1YeEp1aGZMakg=',
    'https://hubcloud.foo/drive/guvqvqxbk1k1fsf': 'https://gamerxyt.com/hubcloud.php?host=hubcloud&id=guvqvqxbk1k1fsf&token=cDhMbXVFTnFmeTVMSUhEMkd6cmxubEZpN1NhdUlhNittTEtjUDMvellOND0=',
  };

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..badCertificateCallback = (cert, host, port) => true;

  final headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  for (final entry in mappings.entries) {
    final vcloudUrl = entry.key;
    final tokenUrl = entry.value;

    print('\n======================================');
    print('Testing Referer: $vcloudUrl');
    print('Fetching Token URL: $tokenUrl');

    try {
      final req = await client.getUrl(Uri.parse(tokenUrl));
      headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.set('Referer', vcloudUrl);
      final resp = await req.close();
      print('Status Code: ${resp.statusCode}');
      if (resp.statusCode != 200) {
        continue;
      }
      final html2 = await resp.transform(utf8.decoder).join();
      print('HTML Length: ${html2.length}');

      final resolved = _parseServerLinks(html2);

      print('Resolved servers:');
      resolved.forEach((k, v) {
        print('  $k: $v');
      });
    } catch (e) {
      print('Error: $e');
    }
  }

  client.close();
}
