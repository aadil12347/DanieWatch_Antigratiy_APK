import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final urls = [
    'https://vcloud.zip/fwpydo7j1ommkyj',
    'https://hubcloud.foo/drive/guvqvqxbk1k1fsf'
  ];

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..badCertificateCallback = (cert, host, port) => true;

  final headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  for (final url in urls) {
    print('\n======================================');
    print('Testing URL: $url');
    try {
      final req = await client.getUrl(Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      print('Status Code: ${resp.statusCode}');
      if (resp.statusCode != 200) {
        continue;
      }
      final html = await resp.transform(utf8.decoder).join();
      print('HTML Length: ${html.length}');

      // Let's test the current token extraction
      final tokenRegExp = RegExp(r"var url\s*=\s*'(https?://[^'\s]+token=[^'\s]+)'");
      final match = tokenRegExp.firstMatch(html);
      if (match != null) {
        print('Matched token URL via regex: ${match.group(1)}');
      } else {
        print('Regex did not match token URL.');
        // Let's check for any other pattern, like <a id="download" href="..."> or var url = '...'
        final anyUrlRegExp = RegExp(r"var url\s*=\s*'([^'\s]+)'");
        final anyMatch = anyUrlRegExp.firstMatch(html);
        if (anyMatch != null) {
          print('Matched generic url: ${anyMatch.group(1)}');
        }

        // Also check if there's a button with id="download"
        final downloadButtonRegExp = RegExp(r'''<a\s+[^>]*id=["']download["'][^>]*href=["']([^"']+)["']''');
        final buttonMatch = downloadButtonRegExp.firstMatch(html);
        if (buttonMatch != null) {
          print('Matched download button href: ${buttonMatch.group(1)}');
        }
      }
    } catch (e) {
      print('Error: $e');
    }
  }
  client.close();
}
