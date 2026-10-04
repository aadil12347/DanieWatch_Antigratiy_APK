import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/extraction/site_post_extractor.dart';

void main() {
  test('Generate GoT Sheets Catalog', () async {
  HttpOverrides.global = null;
  print('🎬 Extracting Complete Game of Thrones Catalog (Seasons 1-8)...');
  final extractor = SitePostExtractor.instance;
  const postUrl = 'https://vegamovies.gallery/download-game-of-thrones-season-1-8-hindi-dubbed-org-480p-720p-1080p-bluray/';

  final buttons = await extractor.extractPostButtons(postUrl);
  print('Total Buttons: ${buttons.length}');

  final batchButtons = buttons.where((b) => b.isBatchZip).toList();
  final nonBatchButtons = buttons.where((b) => !b.isBatchZip).toList();
  final seasons = extractor.getAvailableSeasons(buttons);
  print('Found Seasons: $seasons');

  final List<Map<String, dynamic>> sheetRows = [];

  // 1. Process Batch Zips
  for (final b in batchButtons) {
    sheetRows.add({
      'tmdb_id': 1399,
      'title': 'Game of Thrones',
      'type': 'batch_zip',
      'season': b.seasonNumber ?? 0,
      'episode': '',
      'quality': b.quality,
      'size': b.sizeLabel ?? '',
      'vcloud_url': b.href,
      'direct_stream_url': '',
      'direct_download_url': '',
      'label': b.text,
    });
  }

  // 2. Process Episodes across Seasons 1-8
  for (final s in seasons) {
    print('Processing Season $s episodes...');
    final sButtons = nonBatchButtons.where((b) => b.seasonNumber == s).toList();
    
    // Group by quality (480p, 720p, 1080p)
    final Map<String, List<NextdriveEpisode>> qualityEps = {};
    for (final btn in sButtons) {
      final q = btn.quality.toLowerCase();
      if (!qualityEps.containsKey(q)) {
        try {
          final eps = await extractor.extractNextdriveEpisodes(btn.href);
          if (eps.isNotEmpty) {
            qualityEps[q] = eps;
            print('   Season $s [$q]: extracted ${eps.length} episodes');
          }
        } catch (e) {
          print('   Error extracting Season $s [$q]: $e');
        }
      }
    }

    // Determine max episode count for this season
    int maxEps = 0;
    for (final epList in qualityEps.values) {
      if (epList.length > maxEps) maxEps = epList.length;
    }

    for (int epIdx = 1; epIdx <= maxEps; epIdx++) {
      final ep480 = qualityEps['480p'] != null && epIdx <= qualityEps['480p']!.length ? qualityEps['480p']![epIdx - 1] : null;
      final ep720 = qualityEps['720p'] != null && epIdx <= qualityEps['720p']!.length ? qualityEps['720p']![epIdx - 1] : null;
      final ep1080 = qualityEps['1080p'] != null && epIdx <= qualityEps['1080p']!.length ? qualityEps['1080p']![epIdx - 1] : null;

      sheetRows.add({
        'tmdb_id': 1399,
        'title': 'Game of Thrones',
        'type': 'episode',
        'season': s,
        'episode': epIdx,
        'quality': 'multi',
        'size': '',
        'vcloud_url': (ep720 ?? ep1080 ?? ep480)?.vcloudUrl ?? '',
        'url_480p': ep480?.vcloudUrl ?? '',
        'url_720p': ep720?.vcloudUrl ?? '',
        'url_1080p': ep1080?.vcloudUrl ?? '',
        'label': 'Episode $epIdx',
      });
    }
  }

  // Write to JSON
  final jsonFile = File('scratch/got_complete_catalog.json');
  await jsonFile.writeAsString(const JsonEncoder.withIndent('  ').convert(sheetRows));
  print('Saved ${sheetRows.length} rows to ${jsonFile.path}');

  // Write to CSV
  final csvFile = File('scratch/got_google_sheets.csv');
  final csvBuffer = StringBuffer();
  // Header
  csvBuffer.writeln('tmdb_id,title,type,season,episode,quality,size,vcloud_url,url_480p,url_720p,url_1080p,label');
  for (final row in sheetRows) {
    csvBuffer.writeln([
      row['tmdb_id'],
      '"${row['title']}"',
      row['type'],
      row['season'],
      row['episode'],
      '"${row['quality'] ?? ''}"',
      '"${row['size'] ?? ''}"',
      '"${row['vcloud_url'] ?? ''}"',
      '"${row['url_480p'] ?? ''}"',
      '"${row['url_720p'] ?? ''}"',
      '"${row['url_1080p'] ?? ''}"',
      '"${row['label'] ?? ''}"',
    ].join(','));
  }
  await csvFile.writeAsString(csvBuffer.toString());
  print('Saved CSV to ${csvFile.path}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
