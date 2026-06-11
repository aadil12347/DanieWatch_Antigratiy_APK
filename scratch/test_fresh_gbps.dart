import 'dart:async';
import 'dart:io';

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

    print('Starting redirect resolution for: $url');

    while (redirectCount < 8) {
      final uri = Uri.parse(currentUrl);
      if (uri.queryParameters.containsKey('link')) {
        final directLink = uri.queryParameters['link']!;
        print('SUCCESS! Found "link=" query parameter during hops:');
        print(directLink);
        return directLink;
      }

      final req = await client.getUrl(Uri.parse(currentUrl));
      headers.forEach((k, v) => req.headers.set(k, v));
      req.followRedirects = false;
      final resp = await req.close();

      print('Hop $redirectCount: $currentUrl -> Status: ${resp.statusCode}');

      final loc = resp.headers.value('location');
      if (loc != null) {
        if (loc.startsWith('http')) {
          currentUrl = loc;
        } else {
          currentUrl = Uri.parse(currentUrl).resolve(loc).toString();
        }
        redirectCount++;
      } else {
        break;
      }
    }

    final uri = Uri.parse(currentUrl);
    if (uri.queryParameters.containsKey('link')) {
      final directLink = uri.queryParameters['link']!;
      print('SUCCESS! Found "link=" query parameter at final URL:');
      print(directLink);
      return directLink;
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
  return null;
}

Future<void> main() async {
  final url = 'https://pixel.hubcloud.cx/?id=2793ca30c09cdd670ef5f645f1749ce5540abb376b43b33a21445785886ad98120758b6e76a79f32a1d0da68af3d7bcd5e02420661555534b8b1726aecd5e52f9b287985ec167ddbc4dfb9f63be065227e9f6ab9beec8ee2749015d3ec91b51f::047406ce3d6f04dfe20fcdadac6af53f';
  
  final directLink = await resolveHubCloudRedirect(url);
  if (directLink != null) {
    print('Testing resolved direct video URL via HEAD request...');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..badCertificateCallback = (cert, host, port) => true;
    try {
      final req = await client.headUrl(Uri.parse(directLink));
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      final resp = await req.close();
      print('Direct Video HTTP Status: ${resp.statusCode}');
      if (resp.headers.value('content-type') != null) {
        print('Content-Type: ${resp.headers.value('content-type')}');
      }
      if (resp.headers.value('content-length') != null) {
        print('Content-Length: ${resp.headers.value('content-length')} bytes');
      }
    } catch (e) {
      print('Error verifying link: $e');
    } finally {
      client.close();
    }
  } else {
    print('Could not extract direct link.');
  }
}
