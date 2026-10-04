import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/extraction/site_post_extractor.dart';

void main() {
  test('Find and Inspect Vikings & Breaking Bad Posts', () async {
    HttpOverrides.global = null;
    final extractor = SitePostExtractor.instance;

    print('🔍 Finding Post for Vikings (TMDB 44217)...');
    final vikingsUrl = await extractor.findPostUrl(title: 'Vikings', tmdbId: 44217);
    print('Vikings Post: $vikingsUrl');

    if (vikingsUrl != null) {
      final buttons = await extractor.extractPostButtons(vikingsUrl);
      final seasons = extractor.getAvailableSeasons(buttons);
      print('Vikings Available Seasons: $seasons (Total buttons: ${buttons.length})');
    }

    print('\n🔍 Finding Post for Breaking Bad (TMDB 1396)...');
    final bbUrl = await extractor.findPostUrl(title: 'Breaking Bad', tmdbId: 1396);
    print('Breaking Bad Post: $bbUrl');

    if (bbUrl != null) {
      final buttons = await extractor.extractPostButtons(bbUrl);
      final seasons = extractor.getAvailableSeasons(buttons);
      print('Breaking Bad Available Seasons: $seasons (Total buttons: ${buttons.length})');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
