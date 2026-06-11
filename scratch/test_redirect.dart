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
    String? finalUrl;

    print('Starting redirect resolution for: $url');

    while (redirectCount < 8) {
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
        finalUrl = currentUrl;
        break;
      }
    }

    print('Final resolved URL: $finalUrl');

    if (finalUrl != null) {
      final uri = Uri.parse(finalUrl);
      if (uri.queryParameters.containsKey('link')) {
        final directLink = uri.queryParameters['link']!;
        print('Direct link from query parameter "link": $directLink');
        return directLink;
      }
    }

    final uri = Uri.parse(currentUrl);
    if (uri.queryParameters.containsKey('link')) {
      final directLink = uri.queryParameters['link']!;
      print('Direct link from fallback query parameter "link": $directLink');
      return directLink;
    }
  } catch (e) {
    print('Error resolving redirect: $e');
  } finally {
    client.close();
  }
  return null;
}

Future<void> main() async {
  final gpdlUrl = 'https://gpdl2.hubcloud.cx/?id=604c33ddb65ea79ebcdeb42b6d6dbdb960d2330b03b5de95092531b504c5adeecb3f8e895d90ff5593e699ebd12c6cbc65573f878ecb3b26f578b04ed8c28884b5b09785615d1a6507f3dab35eef3941e5d3398fda4533cd470b838ab837601f7677266740e082d34d6ed994a35801dc::2a96ee0d95812588a104ad32c54681fe';
  final hubcloudUrl = 'https://hubcloud.foo/tg/go?id=3Ofp3dyuoqThzuDY3N/K4aHZ3NCju+rPzODi6tHh2NXk4ajn59bf3bHDyZ6cyMe/27+5o+6/v8bBw7S3ycfMx7DKuK3nw6XFxcfVvrjJ16+61OCd4sfIx7u2yaS6wcHYucuy4LE=';

  for (final url in [gpdlUrl, hubcloudUrl]) {
    print('\n======================================');
    final directVideoLink = await resolveHubCloudRedirect(url);
    if (directVideoLink != null) {
      print('Testing final direct video link: $directVideoLink');
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..badCertificateCallback = (cert, host, port) => true;
      try {
        final req = await client.headUrl(Uri.parse(directVideoLink));
        req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
        final resp = await req.close();
        print('Final Video Link Status Code: ${resp.statusCode}');
        if (resp.headers.value('content-type') != null) {
          print('Content-Type: ${resp.headers.value('content-type')}');
        }
        if (resp.headers.value('content-length') != null) {
          print('Content-Length: ${resp.headers.value('content-length')} bytes');
        }
      } catch (e) {
        print('Error verifying final video link: $e');
      } finally {
        client.close();
      }
    } else {
      print('Could not resolve direct video link.');
    }
  }
}
