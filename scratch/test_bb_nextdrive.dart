import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/extraction/site_post_extractor.dart';

void main() {
  test('Check Breaking Bad S5 720p Nextdrive Extraction', () async {
    HttpOverrides.global = null;
    final extractor = SitePostExtractor.instance;
    const url = 'https://nexdrive.fit/genxfm784776335459/';
    final eps = await extractor.extractNextdriveEpisodes(url);
    print('Breaking Bad S5 720p Episodes count: ${eps.length}');
    for (final ep in eps.take(3)) {
      print('  ${ep.title} -> ${ep.vcloudUrl} (alts: ${ep.alternativeUrls})');
    }
  });
}
