import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/extraction/site_post_extractor.dart';

void main() {
  test('Test Vikings V-Cloud episode extraction', () async {
    HttpOverrides.global = null;
    final extractor = SitePostExtractor.instance;
    // S1 480p V-Cloud selector
    final eps = await extractor.extractNextdriveEpisodes('https://nexdrive.fit/genxfm78477622892/');
    print('Found ${eps.length} episodes:');
    for (final e in eps) {
      print('  ${e.title}: ${e.vcloudUrl}');
    }
  });
}
