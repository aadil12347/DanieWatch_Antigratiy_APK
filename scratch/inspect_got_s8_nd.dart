import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/extraction/site_post_extractor.dart';

void main() {
  test('Inspect Nextdrive episodes for GOT S8 480p, 720p, 1080p', () async {
    HttpOverrides.global = null;
    final extractor = SitePostExtractor.instance;
    final urls = {
      '480p': 'https://nexdrive.fit/genxfm784776336313/',
      '720p': 'https://nexdrive.fit/genxfm784776336319/',
      '1080p': 'https://nexdrive.fit/genxfm784776336325/',
    };

    for (final entry in urls.entries) {
      print('\n======================================================');
      print('Quality: ${entry.key} -> ${entry.value}');
      final eps = await extractor.extractNextdriveEpisodes(entry.value);
      print('Total extracted: ${eps.length}');
      for (final e in eps) {
        print('  • EpNum: ${e.episodeNumber} | Index: ${e.index} | Title: "${e.title}" | Vcloud: ${e.vcloudUrl} | Alts: ${e.alternativeUrls}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
