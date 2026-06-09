import 'dart:convert';
import 'dart:io';

void main() async {
  final vcloudUrl = 'https://vcloud.zip/oh55kmlbiydogqr';
  print('Extracting $vcloudUrl...');
  
  final Map<String, String> resolved = {};
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..badCertificateCallback = (cert, host, port) => true;

  final headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  try {
    // Step 1: Fetch base page
    final req = await client.getUrl(Uri.parse(vcloudUrl));
    headers.forEach((k, v) => req.headers.set(k, v));
    final resp = await req.close();
    print('Base page status: ${resp.statusCode}');
    if (resp.statusCode != 200) {
      client.close();
      return;
    }
    final html = await resp.transform(utf8.decoder).join();

    // Step 2: Extract token URL
    final tokenRegExp = RegExp(r"var url\s*=\s*'(https?://[^'\s]+token=[^'\s]+)'");
    final match = tokenRegExp.firstMatch(html);
    if (match == null) {
      print('Token URL not found');
      client.close();
      return;
    }
    final tokenUrl = match.group(1)!;
    print('Token URL: $tokenUrl');

    // Step 3: Fetch token page with Referer header
    final req2 = await client.getUrl(Uri.parse(tokenUrl));
    headers.forEach((k, v) => req2.headers.set(k, v));
    req2.headers.set('Referer', vcloudUrl);
    final resp2 = await req2.close();
    print('Token page status: ${resp2.statusCode}');
    if (resp2.statusCode != 200) {
      client.close();
      return;
    }
    final html2 = await resp2.transform(utf8.decoder).join();

    // Step 4: Parse all href links from token page
    final hrefRegExp = RegExp(r'''href=["']([^"']+)["']''');
    final matches = hrefRegExp.allMatches(html2);
    final hrefs = matches.map((m) => m.group(1)!).toList();
    print('Parsed hrefs: $hrefs');

    // Step 5: Categorize and resolve links parallelly
    final List<Future<void>> resolveTasks = [];

    for (var href in hrefs) {
      if (href.contains('css') ||
          href.contains('fonts') ||
          href.contains('favicon') ||
          href.contains('manifest') ||
          href.contains('telegram') ||
          href == '#') {
        continue;
      }

      if (href.contains('hub.obsession.buzz') || href.contains('obsession.buzz')) {
        resolved['Server 1'] = href;
      } else if (href.contains('r2.cloudflarestorage.com') || href.contains('r2.dev') || href.contains('.r2.')) {
        // Wait, let's see which Server they map to
        // We'll see if it has cloudflarestorage vs r2.dev
        if (href.contains('cloudflarestorage.com')) {
          resolved['Server 3'] = href;
        } else if (href.contains('r2.dev')) {
          resolved['Server 1'] = href; // Ah! Maybe r2.dev should be Server 1?
        } else {
          resolved['Server 3'] = href;
        }
      } else if (href.contains('hubcloud') || href.contains('gpdl')) {
        resolveTasks.add(() async {
          try {
            print('Resolving redirect for: $href');
            var currentUrl = href;
            var redirectCount = 0;
            String? finalUrl;
            final followClient = HttpClient()
              ..connectionTimeout = const Duration(seconds: 10)
              ..badCertificateCallback = (cert, host, port) => true;

            while (redirectCount < 10) {
              final hcReq = await followClient.getUrl(Uri.parse(currentUrl));
              headers.forEach((k, v) => hcReq.headers.set(k, v));
              hcReq.followRedirects = false;
              final hcResp = await hcReq.close();
              
              final loc = hcResp.headers.value('location');
              print('Hop ${redirectCount + 1}: Status ${hcResp.statusCode}, location=$loc');
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
            followClient.close();

            print('Final URL: $finalUrl');
            if (finalUrl != null) {
              final finalUri = Uri.parse(finalUrl);
              if (finalUri.queryParameters.containsKey('link')) {
                resolved['Server 2'] = finalUri.queryParameters['link']!;
                print('Server 2 (from finalUrl param): ${resolved['Server 2']}');
              } else {
                final uri = Uri.parse(currentUrl);
                if (uri.queryParameters.containsKey('link')) {
                  resolved['Server 2'] = uri.queryParameters['link']!;
                  print('Server 2 (from currentUrl param): ${resolved['Server 2']}');
                } else {
                  print('No link parameter found in final/current URL');
                }
              }
            }
          } catch (e) {
            print('Error resolving redirect for $href: $e');
          }
        }());
      }
    }

    await Future.wait(resolveTasks);
  } catch (e) {
    print('Error during extraction: $e');
  } finally {
    client.close();
  }

  print('\nResolved Server Map:');
  resolved.forEach((k, v) {
    print('$k: $v');
  });
}
