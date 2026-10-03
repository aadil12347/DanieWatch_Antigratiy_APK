import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/extraction/site_post_extractor.dart';

void main() {
  test('Full Matrix Extraction: Game of Thrones Seasons 1-8', () async {
    HttpOverrides.global = null;
    print('===============================================================');
    print('📊 Full Matrix Extraction: Game of Thrones Seasons 1-8');
    print('===============================================================\n');

    final extractor = SitePostExtractor.instance;
    const postUrl = 'https://vegamovies.gallery/download-game-of-thrones-season-1-8-hindi-dubbed-org-480p-720p-1080p-bluray/';

    final buttons = await extractor.extractPostButtons(postUrl);
    print('Total Buttons Extracted: ${buttons.length}');

    final nonBatch = buttons.where((b) => !b.isBatchZip).toList();
    print('Total Non-Batch Buttons: ${nonBatch.length}');

    final seasons = extractor.getAvailableSeasons(buttons);
    print('Available Seasons Detected: $seasons\n');

    for (final s in seasons) {
      print('👑 Season $s:');
      final sBtns = nonBatch.where((b) => b.seasonNumber == s).toList();
      for (final b in sBtns) {
        print('   • Quality: ${b.quality.padRight(6)} | Text: "${b.text.padRight(28)}" | Link: ${b.href}');
      }
    }

    // Now let's test Season 1 and Season 8 episode extraction
    print('\n=============================================================');
    print('🧪 Testing Episode Extraction across qualities for Season 1 & 8:');
    
    for (final testSeason in [1, 8]) {
      print('\n▶ Season $testSeason Extraction:');
      final sBtns = nonBatch.where((b) => b.seasonNumber == testSeason).toList();
      for (final b in sBtns) {
        final eps = await extractor.extractNextdriveEpisodes(b.href);
        print('   [${b.quality}] -> Found ${eps.length} episodes:');
        if (eps.isNotEmpty) {
          print('       Ep 1: "${eps.first.title}" -> V-Cloud: ${eps.first.vcloudUrl}');
          print('       Ep Last: "${eps.last.title}" -> V-Cloud: ${eps.last.vcloudUrl}');
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
