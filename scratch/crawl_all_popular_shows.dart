import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/extraction/site_post_extractor.dart';

void main() {
  test('Crawl Vikings and Breaking Bad for Google Sheets Catalog', () async {
    HttpOverrides.global = null;
    final extractor = SitePostExtractor.instance;

    final targetShows = [
      {
        'tmdb_id': 44217,
        'title': 'Vikings',
        'postUrl': 'https://vegamovies.gallery/download-vikings-season-1-6-hindi-org-dubbed-complete-series-480p-720p/',
      },
      {
        'tmdb_id': 1396,
        'title': 'Breaking Bad',
        'postUrl': 'https://vegamovies.gallery/download-breaking-bad-season-5-complete-hindi-org-dubbed-web-dl-480p-720p-1080p/',
      },
    ];

    for (final show in targetShows) {
      final tmdbId = show['tmdb_id'] as int;
      final title = show['title'] as String;
      final postUrl = show['postUrl'] as String;

      print('\n=============================================================');
      print('🎬 Crawling: $title (TMDB $tmdbId)...');
      print('=============================================================');

      final buttons = await extractor.extractPostButtons(postUrl);
      final batchButtons = buttons.where((b) => b.isBatchZip).toList();
      final nonBatchButtons = buttons.where((b) => !b.isBatchZip).toList();
      final seasons = extractor.getAvailableSeasons(buttons);
      print('$title: Found seasons $seasons (Batch: ${batchButtons.length}, Ep lists: ${nonBatchButtons.length})');

      final List<Map<String, dynamic>> sheetRows = [];

      // 1. Batch Zips
      for (final b in batchButtons) {
        sheetRows.add({
          'tmdb_id': tmdbId,
          'title': title,
          'type': 'batch_zip',
          'season': b.seasonNumber ?? 0,
          'episode': '',
          'quality': b.quality,
          'size': b.sizeLabel ?? '',
          'vcloud_url': b.href,
          'url_480p': '',
          'url_720p': '',
          'url_1080p': '',
          'label': b.text,
        });
      }

      // 2. Episodes per Season
      for (final s in seasons) {
        print('  Crawling $title Season $s...');
        final sButtons = nonBatchButtons.where((b) => b.seasonNumber == s).toList();
        final Map<String, List<NextdriveEpisode>> qualityEps = {};

        for (final btn in sButtons) {
          final q = btn.quality.toLowerCase();
          if (!qualityEps.containsKey(q)) {
            try {
              final eps = await extractor.extractNextdriveEpisodes(btn.href);
              if (eps.isNotEmpty) {
                qualityEps[q] = eps;
                print('    Season $s [$q]: extracted ${eps.length} episodes');
              }
            } catch (e) {
              print('    Season $s [$q] error: $e');
            }
          }
        }

        int maxEps = 0;
        for (final epList in qualityEps.values) {
          if (epList.length > maxEps) maxEps = epList.length;
        }

        for (int epIdx = 1; epIdx <= maxEps; epIdx++) {
          final ep480 = qualityEps['480p'] != null && epIdx <= qualityEps['480p']!.length ? qualityEps['480p']![epIdx - 1] : null;
          final ep720 = qualityEps['720p'] != null && epIdx <= qualityEps['720p']!.length ? qualityEps['720p']![epIdx - 1] : null;
          final ep1080 = qualityEps['1080p'] != null && epIdx <= qualityEps['1080p']!.length ? qualityEps['1080p']![epIdx - 1] : null;

          sheetRows.add({
            'tmdb_id': tmdbId,
            'title': title,
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

      // Save series CSV
      final slug = title.toLowerCase().replaceAll(' ', '_');
      final seriesCsv = File('scratch/${slug}_google_sheets.csv');
      final buf = StringBuffer();
      buf.writeln('tmdb_id,title,type,season,episode,quality,size,vcloud_url,url_480p,url_720p,url_1080p,label');
      for (final r in sheetRows) {
        buf.writeln([
          r['tmdb_id'],
          '"${r['title']}"',
          r['type'],
          r['season'],
          r['episode'],
          '"${r['quality'] ?? ''}"',
          '"${r['size'] ?? ''}"',
          '"${r['vcloud_url'] ?? ''}"',
          '"${r['url_480p'] ?? ''}"',
          '"${r['url_720p'] ?? ''}"',
          '"${r['url_1080p'] ?? ''}"',
          '"${r['label'] ?? ''}"',
        ].join(','));
      }
      await seriesCsv.writeAsString(buf.toString());
      print('Saved ${sheetRows.length} rows to ${seriesCsv.path}');
    }

    // Now build combined master database: GoT + Vikings + Breaking Bad
    print('\n📦 Building combined scratch/master_database.csv...');
    final masterCsv = File('scratch/master_database.csv');
    final masterBuf = StringBuffer();
    masterBuf.writeln('tmdb_id,title,type,season,episode,quality,size,vcloud_url,url_480p,url_720p,url_1080p,label');

    for (final file in [
      File('scratch/got_google_sheets.csv'),
      File('scratch/vikings_google_sheets.csv'),
      File('scratch/breaking_bad_google_sheets.csv'),
    ]) {
      if (await file.exists()) {
        final lines = await file.readAsLines();
        for (int i = 1; i < lines.length; i++) {
          if (lines[i].trim().isNotEmpty) {
            masterBuf.writeln(lines[i]);
          }
        }
      }
    }
    await masterCsv.writeAsString(masterBuf.toString());
    print('✅ Saved master database to ${masterCsv.path}');

  }, timeout: const Timeout(Duration(minutes: 8)));
}
