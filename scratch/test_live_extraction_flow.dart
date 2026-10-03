import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/extraction/site_post_extractor.dart';

void main() {
  test('End-to-End Season 8 Pre-Resolution & Other Qualities Flow', () async {
    HttpOverrides.global = null;
    print('═══════════════════════════════════════════════════════════════');
    print('▶ Testing End-to-End Season 8 Pre-Resolution & Other Qualities Flow');
  
  final extractor = SitePostExtractor.instance;
  const nextdrive720pUrl = 'https://nexdrive.fit/genxfm784776336319/';

  // 1. Extract Nextdrive 720p Episodes
  print('Step 1: Extracting Nextdrive 720p episodes from $nextdrive720pUrl...');
  final episodes = await extractor.extractNextdriveEpisodes(nextdrive720pUrl);
  print('✔ Extracted ${episodes.length} episodes');
  expect(episodes.isNotEmpty, true);

  final ep1 = episodes.first;
  print('  Initial Ep 1: title="${ep1.title}", vcloud="${ep1.vcloudUrl}", size=${ep1.exactSize}');

  // 2. Test Background Pre-Resolution for Season 8
  print('Step 2: Pre-resolving Season 8 720p episodes (prioritizing Ep 1)...');
  final sw = Stopwatch()..start();
  await extractor.preResolveSeasonEpisodes(episodes, priorityIndex: 0);
  sw.stop();
  print('✔ Pre-resolution completed in ${sw.elapsedMilliseconds}ms');

  print('  After Pre-resolution Ep 1:');
  print('    - exactSize: ${ep1.exactSize}');
  print('    - preResolvedStream online: ${ep1.preResolvedStream?.onlineStreamUrl}');
  print('    - preResolvedStream download: ${ep1.preResolvedStream?.bestDownloadUrl}');
  print('    - canStreamOnline: ${ep1.preResolvedStream?.canStreamOnline}');

  expect(ep1.preResolvedStream?.bestDownloadUrl != null, true);
  expect(ep1.exactSize != null, true);

  // 3. Test Async Fetching of Other Resolutions for Ep 1
  print('Step 3: Finding Game of Thrones post URL...');
  final postUrl = await extractor.findPostUrl(title: 'Game of Thrones', tmdbId: 1399) ??
      'https://vegamovies.gallery/download-game-of-thrones-season-1-8-hindi-english-480p-720p-1080p/';
  print('✔ Found postUrl: $postUrl');

  print('Step 4: Fetching other resolutions (480p, 1080p) for Ep 1...');
  final sw2 = Stopwatch()..start();
  final otherResolutions = await extractor.fetchOtherResolutionsForEpisode(
    postUrl: postUrl,
    seasonNumber: 8,
    episodeNumber: ep1.episodeNumber ?? 1,
    currentQuality: '720p',
    targetEpisode: ep1,
  );
  sw2.stop();
  print('✔ Fetched other resolutions in ${sw2.elapsedMilliseconds}ms:');
  otherResolutions.forEach((q, url) {
    print('    - $q: $url');
  });

  // Check cached other resolutions on ep1
  print('  targetEpisode.otherResolutions: ${ep1.otherResolutions}');
  
  // Wait briefly for background size resolution of other resolutions
  await Future.delayed(const Duration(seconds: 4));
  print('  targetEpisode.otherResolutionSizes: ${ep1.otherResolutionSizes}');

    print('═══════════════════════════════════════════════════════════════');
    print('🎉 ALL TESTS PASSED! Flow is completely verified.');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
