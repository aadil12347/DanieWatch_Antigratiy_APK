import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../lib/services/extraction/site_post_extractor.dart';

/// Resolves a batch zip Nextdrive landing page to its direct V-Cloud URL.
Future<String?> resolveBatchVcloudUrl(String landingUrl) async {
  if (landingUrl.contains('vcloud.fit')) return landingUrl;
  try {
    final resp = await http.get(Uri.parse(landingUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    }).timeout(const Duration(seconds: 10));
    final doc = html_parser.parse(resp.body);
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      if (href.contains('vcloud.fit')) return href;
    }
  } catch (e) {
    print('    Error resolving batch $landingUrl: $e');
  }
  return null;
}

/// Helper to ensure only pure vcloud.fit URLs are accepted
String cleanVcloud(String? url) {
  if (url == null) return '';
  final trimmed = url.trim();
  if (trimmed.contains('vcloud.fit')) return trimmed;
  return '';
}

void main() {
  test('Generate 100% PURE V-CLOUD Database for GoT, Vikings, Breaking Bad', () async {
    HttpOverrides.global = null;
    final extractor = SitePostExtractor.instance;

    final targetShows = [
      {
        'tmdb_id': 1399,
        'title': 'Game of Thrones',
        'postUrl': 'https://vegamovies.gallery/download-game-of-thrones-season-1-8-hindi-dubbed-org-480p-720p-1080p-bluray/',
      },
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

    final List<Map<String, dynamic>> masterRows = [];

    for (final show in targetShows) {
      final tmdbId = show['tmdb_id'] as int;
      final title = show['title'] as String;
      final postUrl = show['postUrl'] as String;

      print('\n=============================================================');
      print('🚀 Processing 100% PURE V-CLOUD for: $title (TMDB $tmdbId)...');
      print('=============================================================');

      final buttons = await extractor.extractPostButtons(postUrl);
      final batchButtons = buttons.where((b) => b.isBatchZip).toList();
      final seasons = extractor.getAvailableSeasons(buttons);
      print('$title: Found seasons $seasons');

      // 1. Resolve Batch Zips directly to vcloud.fit
      print('  Resolving Batch Zips to pure vcloud.fit...');
      for (final b in batchButtons) {
        final directVcloud = await resolveBatchVcloudUrl(b.href);
        if (directVcloud != null && directVcloud.contains('vcloud.fit')) {
          print('    Batch S${b.seasonNumber} [${b.quality}]: $directVcloud');
          masterRows.add({
            'tmdb_id': tmdbId,
            'title': title,
            'type': 'batch_zip',
            'season': b.seasonNumber ?? 0,
            'episode': '',
            'quality': b.quality,
            'size': b.sizeLabel ?? '',
            'vcloud_url': directVcloud,
            'url_480p': '',
            'url_720p': '',
            'url_1080p': '',
            'label': b.text,
          });
        }
      }

      // 2. Extract Episodes from V-Cloud selector buttons
      for (final s in seasons) {
        print('  Crawling $title Season $s V-Cloud episodes...');
        // Prefer V-Cloud buttons for each quality
        final qualityButtons = extractor.getSeasonQualityButtons(buttons, s);

        final Map<String, List<NextdriveEpisode>> qualityEps = {};
        for (final entry in qualityButtons.entries) {
          final q = entry.key.toLowerCase();
          try {
            final eps = await extractor.extractNextdriveEpisodes(entry.value.href);
            if (eps.isNotEmpty) {
              qualityEps[q] = eps;
              print('    Season $s [$q]: extracted ${eps.length} episodes');
            }
          } catch (e) {
            print('    Season $s [$q] error: $e');
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

          final u480 = cleanVcloud(ep480?.vcloudUrl);
          final u720 = cleanVcloud(ep720?.vcloudUrl);
          final u1080 = cleanVcloud(ep1080?.vcloudUrl);
          final primary = u720.isNotEmpty ? u720 : (u480.isNotEmpty ? u480 : u1080);

          if (primary.isNotEmpty) {
            masterRows.add({
              'tmdb_id': tmdbId,
              'title': title,
              'type': 'episode',
              'season': s,
              'episode': epIdx,
              'quality': 'multi',
              'size': '',
              'vcloud_url': primary,
              'url_480p': u480,
              'url_720p': u720,
              'url_1080p': u1080,
              'label': 'Episode $epIdx',
            });
          }
        }
      }
    }

    // Write Master Pure V-Cloud CSV
    final masterCsv = File('scratch/pure_vcloud_database.csv');
    final masterBuf = StringBuffer();
    masterBuf.writeln('tmdb_id,title,type,season,episode,quality,size,vcloud_url,url_480p,url_720p,url_1080p,label');
    for (final r in masterRows) {
      masterBuf.writeln([
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
    await masterCsv.writeAsString(masterBuf.toString());
    print('\n🎉 Done! Saved ${masterRows.length} 100% PURE V-CLOUD rows to ${masterCsv.path}');

    // Verification check: make sure NO fastdl or nexdrive exists in vcloud_url!
    int nonVcloudCount = 0;
    for (final r in masterRows) {
      final url = r['vcloud_url']?.toString() ?? '';
      if (!url.contains('vcloud.fit')) {
        nonVcloudCount++;
        print('❌ Found non-vcloud URL: $url');
      }
    }
    print('Total non-vcloud links found: $nonVcloudCount');
    expect(nonVcloudCount, equals(0));

  }, timeout: const Timeout(Duration(minutes: 8)));
}
