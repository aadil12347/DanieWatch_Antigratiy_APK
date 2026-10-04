import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../lib/services/extraction/site_post_extractor.dart';

/// Helper to resolve batch zip landing page to direct vcloud.fit
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
  } catch (_) {}
  return null;
}

String cleanVcloud(String? url) {
  if (url == null) return '';
  final trimmed = url.trim();
  return trimmed.contains('vcloud.fit') ? trimmed : '';
}

void main() {
  test('Crawl Any New Series to Pure V-Cloud Rows', () async {
    HttpOverrides.global = null;
    final extractor = SitePostExtractor.instance;

    // ─────────────────────────────────────────────────────────
    // ✍️ CONFIGURE THE SHOW YOU WANT TO ADD HERE:
    // ─────────────────────────────────────────────────────────
    const tmdbId = int.fromEnvironment('TMDB', defaultValue: 76669); // Example: Elite (76669)
    const seriesTitle = String.fromEnvironment('TITLE', defaultValue: 'Elite');
    const optionalPostUrl = String.fromEnvironment('URL', defaultValue: '');

    print('🎬 Starting Pure V-Cloud Crawl for: $seriesTitle (TMDB ID: $tmdbId)...');

    // 1. Locate the post URL if not specified
    String? postUrl = optionalPostUrl.isNotEmpty ? optionalPostUrl : null;
    if (postUrl == null || postUrl.isEmpty) {
      postUrl = await extractor.findPostUrl(title: seriesTitle, tmdbId: tmdbId);
    }

    if (postUrl == null || postUrl.isEmpty) {
      print('❌ Could not find post page for $seriesTitle. Please supply URL with --dart-define=URL=...');
      return;
    }

    print('✅ Found post page: $postUrl');

    final buttons = await extractor.extractPostButtons(postUrl);
    final batchButtons = buttons.where((b) => b.isBatchZip).toList();
    final seasons = extractor.getAvailableSeasons(buttons);
    print('Found seasons: $seasons');

    final List<Map<String, dynamic>> newRows = [];

    // 2. Batch Zips -> Pure V-Cloud
    for (final b in batchButtons) {
      final directVcloud = await resolveBatchVcloudUrl(b.href);
      if (directVcloud != null && directVcloud.contains('vcloud.fit')) {
        newRows.add({
          'tmdb_id': tmdbId,
          'title': seriesTitle,
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

    // 3. Episodes -> Pure V-Cloud
    for (final s in seasons) {
      final qualityButtons = extractor.getSeasonQualityButtons(buttons, s);
      final Map<String, List<NextdriveEpisode>> qualityEps = {};

      for (final entry in qualityButtons.entries) {
        final q = entry.key.toLowerCase();
        try {
          final eps = await extractor.extractNextdriveEpisodes(entry.value.href);
          if (eps.isNotEmpty) {
            qualityEps[q] = eps;
            print('  Season $s [$q]: extracted ${eps.length} episodes');
          }
        } catch (_) {}
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
          newRows.add({
            'tmdb_id': tmdbId,
            'title': seriesTitle,
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

    final slug = seriesTitle.toLowerCase().replaceAll(' ', '_');
    final outCsv = File('scratch/${slug}_vcloud.csv');
    final buf = StringBuffer();
    buf.writeln('tmdb_id,title,type,season,episode,quality,size,vcloud_url,url_480p,url_720p,url_1080p,label');
    for (final r in newRows) {
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
    await outCsv.writeAsString(buf.toString());
    print('\n🎉 Success! Extracted ${newRows.length} pure V-Cloud rows for $seriesTitle!');
    print('Saved to: ${outCsv.path}');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
