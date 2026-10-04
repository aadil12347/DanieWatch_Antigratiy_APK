import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

void main() {
  test('Inspect Nextdrive Episode Page anchors', () async {
    HttpOverrides.global = null;
    // Season 1 480p G-Direct vs V-Cloud
    const gDirectUrl = 'https://nexdrive.fit/genxfm784776336043/';
    const vCloudUrl = 'https://nexdrive.fit/genxfm784776336044/';

    print('Testing V-Cloud selector page: $vCloudUrl');
    final resp = await http.get(Uri.parse(vCloudUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    });
    final doc = html_parser.parse(resp.body);
    final anchors = doc.querySelectorAll('a[href]');
    for (final a in anchors) {
      final href = a.attributes['href'] ?? '';
      if (href.contains('vcloud') || href.contains('fastdl')) {
        print('  Ep link: ${a.text.trim()} -> $href');
      }
    }
  });
}
