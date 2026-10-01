import 'package:flutter_test/flutter_test.dart';
import 'package:daniewatch_app/services/extraction/site_post_extractor.dart';

void main() {
  test('Test Punisher extraction', () async {
    const postUrl = 'https://vegamovies.gallery/download-the-punisher-season-1-hindi-dubbed-series-480p-720p-1080p-web-dl/';
    print('Extracting post buttons for: $postUrl');

    final extractor = SitePostExtractor.instance;
    final buttons = await extractor.extractPostButtons(postUrl);
    print('Total buttons extracted: ${buttons.length}');

    for (final b in buttons) {
      print('Btn: text="${b.text}", href="${b.href}", quality="${b.quality}", season=${b.seasonNumber}, isBatch=${b.isBatchZip}, isEpList=${b.isEpisodeList}');
    }

    final seasons = extractor.getAvailableSeasons(buttons);
    print('Available seasons: $seasons');

    final best = extractor.getBestEpisodeButton(buttons, 1);
    print('Selected button for Season 1: text="${best?.text}", href="${best?.href}", quality="${best?.quality}"');
    expect(best, isNotNull);
    expect(best!.text.toLowerCase().contains('v-cloud') || best.text.toLowerCase().contains('resumable'), isTrue);

    final episodes = await extractor.extractNextdriveEpisodes(best.href);
    print('Extracted episodes count: ${episodes.length}');
    for (final ep in episodes) {
      print('  [${ep.title}] (Ep ${ep.episodeNumber}) -> ${ep.vcloudUrl}');
    }
    expect(episodes.length, greaterThan(0));

    final streamInfo = await extractor.resolveVcloudStream(episodes.first.vcloudUrl);
    print('Stream info resolved:');
    print('  FSLv2: ${streamInfo.fslv2Url}');
    print('  FSL: ${streamInfo.fslUrl}');
    print('  10Gbps: ${streamInfo.tenGbpsUrl}');
    print('  Online Stream: ${streamInfo.onlineStreamUrl}');
    expect(streamInfo.onlineStreamUrl, isNotNull);
  });
}
