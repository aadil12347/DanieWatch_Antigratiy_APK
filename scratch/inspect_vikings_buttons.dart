import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/extraction/site_post_extractor.dart';

void main() {
  test('Inspect Vikings post buttons', () async {
    HttpOverrides.global = null;
    final extractor = SitePostExtractor.instance;
    const vikingsUrl = 'https://vegamovies.gallery/download-vikings-season-1-6-hindi-org-dubbed-complete-series-480p-720p/';
    final buttons = await extractor.extractPostButtons(vikingsUrl);
    for (final b in buttons) {
      print('S${b.seasonNumber} | ${b.quality} | isBatch=${b.isBatchZip} | "${b.text}" -> ${b.href}');
    }
  });
}
