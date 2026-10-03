import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/extraction/site_post_extractor.dart';

void main() {
  test('Check Rogmovies Series Structure', () async {
    HttpOverrides.global = null;
    print('===============================================================');
    print('🔍 Checking Rogmovies TV Series Button Structure');
    print('===============================================================\n');

    final extractor = SitePostExtractor.instance;
    final postUrl = await extractor.findPostUrl(
      title: 'Breaking Bad',
      tmdbId: 1396,
    );
    print('Found Post URL for Breaking Bad: $postUrl');

    if (postUrl != null && postUrl.isNotEmpty) {
      final buttons = await extractor.extractPostButtons(postUrl);
      print('Total Buttons: ${buttons.length}');
      final seasons = extractor.getAvailableSeasons(buttons);
      print('Seasons Detected: $seasons');
      final nonBatch = buttons.where((b) => !b.isBatchZip).toList();
      print('Non-batch buttons: ${nonBatch.length}');
      for (final b in nonBatch.take(15)) {
        print('  [S${b.seasonNumber} - ${b.quality}] text: "${b.text}" -> href: ${b.href}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
