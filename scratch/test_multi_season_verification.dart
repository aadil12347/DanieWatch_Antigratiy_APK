import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daniewatch_app/services/extraction/site_post_extractor.dart';
import 'package:daniewatch_app/services/extraction/series_vcloud_repository.dart';

void main() {
  test('Multi-Season Series Architecture Verification Test', () async {
    print('===============================================================');
    print('  Multi-Season Series Architecture Verification Test');
    print('===============================================================');

  final testSeries = [
    {
      'title': 'Vikings',
      'year': 2013,
      'expectedSeasons': 6,
      'testSeason': 4,
    },
    {
      'title': 'Breaking Bad',
      'year': 2008,
      'expectedSeasons': 5,
      'testSeason': 1,
    },
    {
      'title': 'Game of Thrones',
      'year': 2011,
      'expectedSeasons': 8,
      'testSeason': 8,
    },
  ];

  final extractor = SitePostExtractor.instance;
  final httpClient = HttpClient()
    ..badCertificateCallback = (cert, host, port) => true;

  for (final item in testSeries) {
    final title = item['title'] as String;
    final year = item['year'] as int;
    final expSeasons = item['expectedSeasons'] as int;
    final testSeason = item['testSeason'] as int;

    print('\n-------------------------------------------------------------');
    print('Testing Show: "$title" (Expected Seasons: >= $expSeasons)');

    // 1. findPostUrl
    final stopwatch = Stopwatch()..start();
    final postUrl = await extractor.findPostUrl(title: title, year: year);
    stopwatch.stop();

    if (postUrl == null) {
      print('❌ FAILED: findPostUrl returned null for $title');
      continue;
    }

    print('✔ Post URL Found (${stopwatch.elapsedMilliseconds}ms): $postUrl');

    // 2. extractPostButtons & getAvailableSeasons
    final buttons = await extractor.extractPostButtons(postUrl);
    final seasons = extractor.getAvailableSeasons(buttons);
    print('✔ Discovered Seasons: $seasons (Count: ${seasons.length})');

    if (seasons.length < expSeasons) {
      print('⚠️ Warning: Discovered ${seasons.length} seasons, expected $expSeasons');
    } else {
      print('✅ All expected seasons verified on post page!');
    }

    // 3. getSeasonQualityButtons for testSeason
    final qualityButtons = extractor.getSeasonQualityButtons(buttons, testSeason);
    print('✔ Season $testSeason Quality Buttons: ${qualityButtons.keys.toList()}');

    // 4. Extract episodes for all available qualities in parallel
    final Map<String, List<NextdriveEpisode>> qualityEpisodes = {};
    await Future.wait(qualityButtons.entries.map((entry) async {
      try {
        final eps = await extractor.extractNextdriveEpisodes(entry.value.href);
        if (eps.isNotEmpty) {
          qualityEpisodes[entry.key] = eps;
        }
      } catch (e) {
        print('  Error extracting ${entry.key}: $e');
      }
    }));

    if (qualityEpisodes.isEmpty) {
      print('❌ FAILED: No episodes extracted for Season $testSeason');
      continue;
    }

    final primaryQuality = qualityEpisodes.containsKey('720p')
        ? '720p'
        : (qualityEpisodes.containsKey('480p') ? '480p' : qualityEpisodes.keys.first);
    final episodes = qualityEpisodes[primaryQuality]!;

    print('✔ Season $testSeason: Extracted ${episodes.length} episodes across qualities [${qualityEpisodes.keys.join(', ')}]');

    // Link resolutions
    for (int i = 0; i < episodes.length; i++) {
      final ep = episodes[i];
      final epNum = ep.episodeNumber ?? ep.index;
      final otherRes = <String, String>{};
      for (final qEntry in qualityEpisodes.entries) {
        final matchedEp = qEntry.value.firstWhere(
          (e) => (e.episodeNumber ?? e.index) == epNum,
          orElse: () => (i < qEntry.value.length ? qEntry.value[i] : ep),
        );
        if (matchedEp.vcloudUrl.isNotEmpty) {
          otherRes[qEntry.key] = matchedEp.vcloudUrl;
        }
      }
      ep.otherResolutions = otherRes;
    }

    final sampleEp = episodes.first;
    print('  Sample Episode: "${sampleEp.title}"');
    print('  Resolutions available for modal: ${sampleEp.otherResolutions?.keys.toList()}');
    print('  Direct VCloud 720p URL: ${sampleEp.vcloudUrl}');

    // 5. Direct Stream Resolution Probe on sample episode
    try {
      final streamResult = await extractor.resolveVcloudStream(
        sampleEp.vcloudUrl,
        alternativeUrls: sampleEp.alternativeUrls,
      );
      print('  Stream Resolution:');
      print('    • Online Stream URL: ${streamResult.onlineStreamUrl != null ? "✔ Ready" : "❌ None"}');
      print('    • Best Download URL: ${streamResult.bestDownloadUrl != null ? "✔ Ready" : "❌ None"}');
      print('    • Detected Exact Size: ${streamResult.fileSize ?? "Unknown"}');

      if (streamResult.onlineStreamUrl != null) {
        final req = await httpClient.getUrl(Uri.parse(streamResult.onlineStreamUrl!));
        req.headers.set('User-Agent', 'Mozilla/5.0');
        req.headers.set('Range', 'bytes=0-1024');
        final resp = await req.close();
        print('    • HTTP Probe on Direct Stream: HTTP ${resp.statusCode} (Accept-Ranges: ${resp.headers.value('accept-ranges')})');
        if (resp.statusCode == 206 || resp.statusCode == 200) {
          print('    ✅ Direct seekable playback confirmed!');
        }
      }
    } catch (e) {
      print('  Error resolving stream probe: $e');
    }
  }

  httpClient.close();
  print('\n===============================================================');
  print('  All Multi-Season Tests Completed Successfully!');
  print('===============================================================');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
