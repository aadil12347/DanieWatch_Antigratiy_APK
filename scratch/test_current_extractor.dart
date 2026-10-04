import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/extraction/site_post_extractor.dart';

void main() {
  test('Test current SitePostExtractor on multi-season series', () async {
    HttpOverrides.global = null;
    final posts = [
      {
        'title': 'Breaking Bad (Seasons 1-5)',
        'url': 'https://vegamovies.gallery/download-breaking-bad-season-5-complete-hindi-org-dubbed-web-dl-480p-720p-1080p/',
      },
      {
        'title': 'Vikings (Seasons 1-6)',
        'url': 'https://vegamovies.gallery/download-vikings-season-1-6-hindi-org-dubbed-complete-series-480p-720p/',
      },
      {
        'title': 'Game of Thrones (Seasons 1-8)',
        'url': 'https://vegamovies.gallery/download-game-of-thrones-season-1-8-hindi-dubbed-org-480p-720p-1080p-bluray/',
      }
    ];

    final extractor = SitePostExtractor.instance;

    for (final p in posts) {
      print('================================================================');
      print('Testing extractor on: ${p['title']}');
      print('URL: ${p['url']}');
      print('================================================================');

      final buttons = await extractor.extractPostButtons(p['url']!);
      print('Total buttons parsed: ${buttons.length}');

      final nonBatch = buttons.where((b) => !b.isBatchZip).toList();
      print('Non-batch buttons: ${nonBatch.length}');

      final seasons = extractor.getAvailableSeasons(buttons);
      print('Seasons detected by getAvailableSeasons: $seasons');

      final groupedBySeason = <int, List<SitePostButton>>{};
      for (final b in buttons) {
        groupedBySeason.putIfAbsent(b.seasonNumber, () => []).add(b);
      }

      print('\nGrouped by detected season:');
      for (final s in groupedBySeason.keys.toList()..sort()) {
        final sBtns = groupedBySeason[s]!;
        print('  Season $s (${sBtns.length} buttons):');
        for (final b in sBtns) {
          print('    • Quality: ${b.quality.padRight(6)} | isBatch: ${b.isBatchZip.toString().padRight(5)} | Text: "${b.text.padRight(28)}" | Link: ${b.href}');
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
