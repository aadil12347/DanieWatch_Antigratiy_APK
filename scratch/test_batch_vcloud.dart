import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../lib/services/extraction/site_post_extractor.dart';

void main() {
  test('Inspect Batch Zip Nextdrive landing page for V-Cloud link', () async {
    HttpOverrides.global = null;
    const testBatchUrl = 'https://nexdrive.fit/genxfm784776336312/';
    final response = await http.get(Uri.parse(testBatchUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    });
    print('Status: ${response.statusCode}');
    print('HTML length: ${response.body.length}');
    final doc = html_parser.parse(response.body);
    final anchors = doc.querySelectorAll('a[href]');
    for (final a in anchors) {
      final href = a.attributes['href'] ?? '';
      final text = a.text.trim();
      if (href.contains('vcloud') || href.contains('hubcloud') || href.contains('drive') || text.toLowerCase().contains('download')) {
        print('  Anchor: "$text" -> $href');
      }
    }
  });
}
