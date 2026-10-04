import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/extraction/series_vcloud_repository.dart';
import '../lib/services/extraction/site_post_extractor.dart';

void main() {
  test('Test SeriesVcloudRepository multi-season multi-quality crawling', () async {
    HttpOverrides.global = null;
    final repo = SeriesVcloudRepository.instance;

    final testCases = [
      {
        'title': 'Breaking Bad',
        'url': 'https://vegamovies.gallery/download-breaking-bad-season-5-complete-hindi-org-dubbed-web-dl-480p-720p-1080p/',
        'checkSeason': 5,
        'checkEp': 1,
      },
      {
        'title': 'Vikings',
        'url': 'https://vegamovies.gallery/download-vikings-season-1-6-hindi-org-dubbed-complete-series-480p-720p/',
        'checkSeason': 1,
        'checkEp': 1,
      },
      {
        'title': 'Game of Thrones',
        'url': 'https://vegamovies.gallery/download-game-of-thrones-season-1-8-hindi-dubbed-org-480p-720p-1080p-bluray/',
        'checkSeason': 8,
        'checkEp': 1,
      }
    ];

    for (final tc in testCases) {
      final title = tc['title'] as String;
      final url = tc['url'] as String;
      final s = tc['checkSeason'] as int;
      final epNum = tc['checkEp'] as int;

      print('\n=============================================================');
      print('Crawling $title (Season $s, Ep $epNum)');
      print('=============================================================');

      await repo.crawlAllSeasonsVcloud(postUrl: url, prioritySeason: s);

      final ep = repo.getEpisode(url, s, epNum);
      if (ep == null) {
        print('❌ Episode not found in repo for S$s E$epNum!');
      } else {
        print('✔ Found Episode: "${ep.title}"');
        print('  Qualities stored: ${ep.vcloudUrls.keys.toList()}');
        for (final entry in ep.vcloudUrls.entries) {
          print('    • [${entry.key}]: ${entry.value}');
        }
        print('  Alternative URLs: ${ep.alternativeUrls}');
        print('  Exact Sizes: ${ep.exactSizes}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
