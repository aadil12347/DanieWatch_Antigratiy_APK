import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'movie_site_scraper_service.dart';
import 'dynamic_urls.dart';

/// Represents a download or episode landing button extracted from a post page.
class SitePostButton {
  final String text;
  final String href;
  final String quality; // '480p', '720p', '1080p', '2160p'
  final int seasonNumber;
  final bool isBatchZip;
  final bool isEpisodeList;
  final String? sizeLabel;

  SitePostButton({
    required this.text,
    required this.href,
    required this.quality,
    required this.seasonNumber,
    required this.isBatchZip,
    this.isEpisodeList = false,
    this.sizeLabel,
  });

  @override
  String toString() =>
      'SitePostButton(S$seasonNumber, $quality, isBatch=$isBatchZip, isEpList=$isEpisodeList, size=$sizeLabel, text="$text", href="$href")';
}

/// Represents an episode extracted directly from the Nextdrive episode selector page.
class NextdriveEpisode {
  final String title;
  final String vcloudUrl;
  final int index;
  final int? episodeNumber;
  final int? rangeStart;
  final int? rangeEnd;
  final bool isComplete;
  String? thumbnailUrl; // Set from TMDB still or poster fallback

  NextdriveEpisode({
    required this.title,
    required this.vcloudUrl,
    required this.index,
    this.episodeNumber,
    this.rangeStart,
    this.rangeEnd,
    this.isComplete = false,
    this.thumbnailUrl,
  });

  @override
  String toString() =>
      'NextdriveEpisode(index: $index, title: "$title", epNum: $episodeNumber, range: $rangeStart-$rangeEnd, isComplete: $isComplete, url: "$vcloudUrl")';
}

/// Resolved stream URLs from VCloud.
class VcloudStreamResult {
  final String? fslv2Url;
  final String? fslUrl;
  final String? tenGbpsUrl;
  final String? pixeldrainUrl;

  VcloudStreamResult({
    this.fslv2Url,
    this.fslUrl,
    this.tenGbpsUrl,
    this.pixeldrainUrl,
  });

  /// Online playback policy:
  /// Strictly FSLv2 > FSL (NO 10Gbps link for online play).
  String? get onlineStreamUrl => fslv2Url ?? fslUrl;

  bool get canStreamOnline => onlineStreamUrl != null;

  /// Download fallback:
  /// FSLv2 > FSL > Pixeldrain > 10Gbps
  String? get bestDownloadUrl =>
      fslv2Url ?? fslUrl ?? pixeldrainUrl ?? tenGbpsUrl;

  @override
  String toString() =>
      'VcloudStreamResult(FSLv2: $fslv2Url, FSL: $fslUrl, 10Gbps: $tenGbpsUrl, PXL: $pixeldrainUrl)';
}

/// Unified extractor for Vegamovies & Rogmovies detail posts, Nextdrive episode pages,
/// and V-Cloud stream/download link resolution.
class SitePostExtractor {
  static final SitePostExtractor instance = SitePostExtractor._internal();
  SitePostExtractor._internal();

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// Fetch HTML with appropriate Referer, auto-retrying with active mirror domains on failure.
  Future<String> fetchHtml(String url, {String? referer}) async {
    final uri = Uri.parse(url);

    final urlsToTry = <String>[url];
    if (uri.host.contains('vegamovies.')) {
      for (final mirror in ['vegamovies.gallery', 'vegamovies.pages.dev', 'vegamovies.im']) {
        final alt = url.replaceFirst(uri.host, mirror);
        if (!urlsToTry.contains(alt)) urlsToTry.add(alt);
      }
    } else if (uri.host.contains('rogmovies.')) {
      for (final mirror in ['rogmovies.best', 'rogmovies.online']) {
        final alt = url.replaceFirst(uri.host, mirror);
        if (!urlsToTry.contains(alt)) urlsToTry.add(alt);
      }
    }

    Object? lastError;
    for (final tryUrl in urlsToTry) {
      try {
        final tryUri = Uri.parse(tryUrl);
        final tryRef = referer ?? '${tryUri.scheme}://${tryUri.host}/';
        final res = await http.get(tryUri, headers: {
          ..._headers,
          'Referer': tryRef,
        }).timeout(const Duration(seconds: 12));
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          return res.body;
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('Failed to fetch $url');
  }

  /// Find the site post URL for a title or TMDB ID.
  /// Uses VegaMovies TypeSense search API (/ts-search.php) for reliable JSON results,
  /// and falls back to RogMovies HTML search.
  Future<String?> findPostUrl({
    required String title,
    int? tmdbId,
    int? year,
    String? imdbId,
  }) async {
    // 1. Check in-memory post URL map from MovieSiteScraperService
    if (tmdbId != null) {
      final cached = MovieSiteScraperService.instance.getPostUrl(tmdbId);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
    }

    // 2. Clean query
    final cleanQuery = title
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]|\{.*?\}'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // 3. Search VegaMovies via TypeSense API (returns JSON, not JS-powered HTML)
    final vegaBase = await DynamicUrls()
        .getLatestBaseUrl('vegamovies', fallback: 'https://vegamovies.gallery');
    try {
      final tsUrl = '$vegaBase/ts-search.php?q=${Uri.encodeComponent(cleanQuery)}&page=1';
      final tsRes = await http.get(Uri.parse(tsUrl), headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (tsRes.statusCode == 200 && tsRes.body.isNotEmpty) {
        final data = jsonDecode(tsRes.body) as Map<String, dynamic>;
        final hits = data['hits'] as List? ?? [];
        for (final hit in hits) {
          final doc = hit['document'] as Map<String, dynamic>?;
          if (doc == null) continue;
          final permalink = doc['permalink']?.toString() ?? '';
          if (permalink.isNotEmpty) {
            final fullUrl = permalink.startsWith('http')
                ? permalink
                : '$vegaBase$permalink';
            // Validate it's a post, not a category/tag page
            if (!fullUrl.contains('/category/') &&
                !fullUrl.contains('/tag/') &&
                !fullUrl.contains('/page/')) {
              debugPrint('[SitePostExtractor] Found post via TypeSense: $fullUrl');
              return fullUrl;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[SitePostExtractor] TypeSense search error: $e');
    }

    // 4. Fallback: VegaMovies old ?s= search (may still work for some mirrors)
    try {
      final oldSearchUrl = '$vegaBase/?s=${Uri.encodeComponent(cleanQuery)}';
      final html = await fetchHtml(oldSearchUrl);
      final doc = html_parser.parse(html);
      final anchors = doc.querySelectorAll(
          'article a[href], .poster-card a[href], .entry-title a[href], h2 a[href]');
      for (final a in anchors) {
        final href = a.attributes['href'] ?? '';
        if (href.isNotEmpty &&
            (href.contains('/download-') ||
                href.contains('vegamovies.') ||
                href.contains('rogmovies.'))) {
          if (!href.contains('/category/') &&
              !href.contains('/tag/') &&
              !href.contains('/page/')) {
            return href;
          }
        }
      }
    } catch (e) {
      debugPrint('[SitePostExtractor] Old search fallback error: $e');
    }

    // 5. Fallback: RogMovies old ?s= search
    try {
      final rogSearchUrl =
          'https://rogmovies.best/?s=${Uri.encodeComponent(cleanQuery)}';
      final html = await fetchHtml(rogSearchUrl);
      final doc = html_parser.parse(html);
      final anchors = doc.querySelectorAll(
          'article a[href], .poster-card a[href], .entry-title a[href], h2 a[href]');
      for (final a in anchors) {
        final href = a.attributes['href'] ?? '';
        if (href.isNotEmpty &&
            (href.contains('/download-') ||
                href.contains('vegamovies.') ||
                href.contains('rogmovies.'))) {
          if (!href.contains('/category/') &&
              !href.contains('/tag/') &&
              !href.contains('/page/')) {
            return href;
          }
        }
      }
    } catch (e) {
      debugPrint('[SitePostExtractor] RogMovies search error: $e');
    }
    return null;
  }


  /// Parse all download and episode buttons from a Vegamovies/Rogmovies detail post page.
  Future<List<SitePostButton>> extractPostButtons(String postUrl) async {
    try {
      final html = await fetchHtml(postUrl);
      final doc = html_parser.parse(html);
      final contentEl = doc.querySelector(
              'main.page-body, .page-body, .entry-content, #main-content, div.content-kuss, div.content-area, article') ??
          doc.body;
      if (contentEl == null) return [];

      final buttons = <SitePostButton>[];
      final anchors = contentEl.querySelectorAll('a[href]');

      for (final a in anchors) {
        var href = a.attributes['href'] ?? '';
        if (href.isEmpty || href.startsWith('#')) continue;

        try {
          href = Uri.parse(postUrl).resolve(href).toString();
        } catch (_) {}

        final lh = href.toLowerCase();
        final isLanding = [
          'nexdrive', 'vgmlink', 'gdflix', 'fastdl', 'filebee',
          'hubcloud', 'vcloud', 'pixeldrain'
        ].any((d) => lh.contains(d));

        if (!isLanding) continue;
        if (lh.contains('telegram') ||
            lh.contains('facebook') ||
            lh.contains('twitter') ||
            lh.contains('category/') ||
            lh.contains('/tag/')) {
          continue;
        }

        final aText = a.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        final lowerText = aText.toLowerCase();

        final isBatchZip = lowerText.contains('batch') ||
            lowerText.contains('zip') ||
            lowerText.contains('pack');

        final isEpisodeList = lowerText.contains('episode') ||
            lowerText.contains('v-cloud') ||
            lowerText.contains('g-direct') ||
            (!isBatchZip && lowerText.contains('resumable'));

        // Extract size label e.g. [3.4GB] or [1.5GB]
        String? sizeLabel;
        final sizeMatch = RegExp(r'\[\s*(\d+(?:\.\d+)?\s*(?:MB|GB))\s*\]',
                caseSensitive: false)
            .firstMatch(aText);
        if (sizeMatch != null) {
          sizeLabel = sizeMatch.group(1);
        }

        // Walk upward in DOM to find specific Quality and Season headings
        String quality = '720p';
        int seasonNumber = 1;

        var curr = a.parent;
        bool foundQuality = false;
        bool foundSeason = false;

        while (curr != null &&
            curr != contentEl &&
            (!foundQuality || !foundSeason)) {
          var sib = curr.previousElementSibling;
          while (sib != null && (!foundQuality || !foundSeason)) {
            final st = sib.text.replaceAll(RegExp(r'\s+'), ' ').trim();
            final lowerSt = st.toLowerCase();
            final tag = (sib.localName ?? '').toLowerCase();

            // Quality heading
            if (!foundQuality &&
                (RegExp(r'^h[1-6]$').hasMatch(tag) ||
                    lowerSt.contains('web-dl') ||
                    lowerSt.contains('bluray') ||
                    lowerSt.contains('hevc') ||
                    lowerSt.contains('480p') ||
                    lowerSt.contains('720p') ||
                    lowerSt.contains('1080p'))) {
              if (lowerSt.contains('2160p') || lowerSt.contains('4k')) {
                quality = '2160p';
                foundQuality = true;
              } else if (lowerSt.contains('1080p')) {
                quality = '1080p';
                foundQuality = true;
              } else if (lowerSt.contains('720p')) {
                quality = '720p';
                foundQuality = true;
              } else if (lowerSt.contains('480p')) {
                quality = '480p';
                foundQuality = true;
              }
            }

            // Season heading
            if (!foundSeason) {
              final sMatch =
                  RegExp(r'(?:Season|S)\s*0*(\d+)', caseSensitive: false)
                      .firstMatch(st);
              if (sMatch != null) {
                final s = int.tryParse(sMatch.group(1)!);
                if (s != null && s > 0 && s < 100) {
                  seasonNumber = s;
                  foundSeason = true;
                }
              }
            }

            sib = sib.previousElementSibling;
          }
          curr = curr.parent;
        }

        if (!buttons.any((b) => b.href == href)) {
          buttons.add(SitePostButton(
            text: aText.isNotEmpty ? aText : 'Download',
            href: href,
            quality: quality,
            seasonNumber: seasonNumber,
            isBatchZip: isBatchZip,
            isEpisodeList: isEpisodeList,
            sizeLabel: sizeLabel,
          ));
        }
      }

      return buttons;
    } catch (e) {
      debugPrint('[SitePostExtractor] Error extracting post buttons: $e');
      return [];
    }
  }

  /// Get the best Nextdrive episode landing URL for a given season.
  /// Priority: V-Cloud buttons with 720p > 480p > 1080p fallback.
  SitePostButton? getBestEpisodeButton(
      List<SitePostButton> buttons, int seasonNumber) {
    var seasonButtons = buttons
        .where((b) => b.seasonNumber == seasonNumber && !b.isBatchZip)
        .toList();

    // Fallback if post is single season and buttons weren't explicitly numbered
    if (seasonButtons.isEmpty && seasonNumber == 1) {
      seasonButtons = buttons.where((b) => !b.isBatchZip).toList();
    }

    if (seasonButtons.isEmpty) return null;

    // Filter to V-Cloud buttons if available (user requirement)
    final vcloudButtons = seasonButtons
        .where((b) =>
            b.text.toLowerCase().contains('v-cloud') ||
            b.text.toLowerCase().contains('vcloud') ||
            b.text.toLowerCase().contains('resumable'))
        .toList();

    final targetList = vcloudButtons.isNotEmpty ? vcloudButtons : seasonButtons;

    // Prioritize 720p > 480p > 1080p > others
    return targetList.firstWhere(
      (b) => b.quality == '720p',
      orElse: () => targetList.firstWhere(
        (b) => b.quality == '480p',
        orElse: () => targetList.firstWhere(
          (b) => b.quality == '1080p',
          orElse: () => targetList.first,
        ),
      ),
    );
  }

  /// Get all unique season numbers found in post buttons.
  List<int> getAvailableSeasons(List<SitePostButton> buttons) {
    final seasons = <int>{};
    for (final b in buttons) {
      if (b.seasonNumber > 0) {
        seasons.add(b.seasonNumber);
      }
    }
    final sorted = seasons.toList()..sort();
    return sorted.isEmpty ? [1] : sorted;
  }

  /// Get all available Batch/Zip options for a given season.
  List<SitePostButton> getBatchZipOptions(
      List<SitePostButton> buttons, int seasonNumber) {
    return buttons
        .where((b) => b.seasonNumber == seasonNumber && b.isBatchZip)
        .toList();
  }

  /// Extract episodes directly from a Nextdrive episode selector page.
  /// Strictly extracts the episode titles from the page itself (never TMDB).
  /// Handles both old format and new format:
  ///   Old: <h4>Episode 1</h4> <p><a href="vcloud...">...</a></p>
  ///   New: <h4>-:Episode: 1:-</h4> <p><a href="vcloud...">...</a></p>
  Future<List<NextdriveEpisode>> extractNextdriveEpisodes(
      String nextdriveUrl) async {
    try {
      final html = await fetchHtml(nextdriveUrl);
      final doc = html_parser.parse(html);

      final episodes = <NextdriveEpisode>[];
      final seenUrls = <String>{};

      // Search all anchors pointing to vcloud.fit or vegadrive
      final anchors = doc.querySelectorAll('a[href]');
      for (final a in anchors) {
        var href = a.attributes['href'] ?? '';
        if (href.isEmpty) continue;
        try {
          href = Uri.parse(nextdriveUrl).resolve(href).toString();
        } catch (_) {}

        // Match vcloud or vegadrive links (skip non-download links)
        final lhref = href.toLowerCase();
        if (!lhref.contains('vcloud')) continue;
        // Skip telegram, social media links
        if (lhref.contains('telegram') ||
            lhref.contains('t.me') ||
            lhref.contains('facebook') ||
            lhref.contains('twitter') ||
            lhref.contains('.fans')) {
          continue;
        }
        if (seenUrls.contains(href)) continue;
        seenUrls.add(href);

        // Find heading/text preceding this link or on this link
        String rawTitle = '';

        // 1. Direct siblings of `a`
        var aSib = a.previousElementSibling;
        while (aSib != null) {
          final st = aSib.text.trim();
          final tag = (aSib.localName ?? '').toLowerCase();
          if (st.isNotEmpty &&
              (RegExp(r'^h[1-6]$').hasMatch(tag) ||
                  st.toLowerCase().contains('episode') ||
                  st.toLowerCase().contains('season') ||
                  st.toLowerCase().contains('complete'))) {
            rawTitle = st;
            break;
          }
          aSib = aSib.previousElementSibling;
        }

        // 2. Preceding siblings of parents (e.g. <h4> above <p><a>)
        var parent = a.parent;
        while (parent != null && rawTitle.isEmpty) {
          var sib = parent.previousElementSibling;
          while (sib != null) {
            final st = sib.text.trim();
            final tag = (sib.localName ?? '').toLowerCase();
            if (st.isNotEmpty &&
                (RegExp(r'^h[1-6]$').hasMatch(tag) ||
                    st.toLowerCase().contains('episode') ||
                    st.toLowerCase().contains('season') ||
                    st.toLowerCase().contains('complete'))) {
              rawTitle = st;
              break;
            }
            sib = sib.previousElementSibling;
          }
          parent = parent.parent;
        }

        // 3. Fallback to anchor text or title if it contains episode/season info
        if (rawTitle.isEmpty) {
          final aText = a.text.trim();
          if (aText.toLowerCase().contains('episode') ||
              aText.toLowerCase().contains('season') ||
              aText.toLowerCase().contains('complete')) {
            rawTitle = aText;
          }
        }

        // Clean rawTitle — handle both old and new formats:
        //   Old: "Episode 1", "Episode: 1"
        //   New: "-:Episode: 1:-", "-:Episode: 3:-"
        var clean = rawTitle
            .replaceAll(RegExp(r'[-:~_*#]+'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        // Try range match: "Episode 1-5" or "Episode 1 to 5"
        final rangeMatch = RegExp(
                r'episode[s]?\s*[:\s]*0*(\d+)\s*[\+\-–—to]+\s*0*(\d+)',
                caseSensitive: false)
            .firstMatch(clean);
        // Try single match: "Episode 1" or "Episode: 1" or "Episode 1"
        final singleMatch = RegExp(r'episode[s]?\s*[:\s]*0*(\d+)',
                caseSensitive: false)
            .firstMatch(clean);
        final isComplete = clean.toLowerCase().contains('complete') ||
            clean.toLowerCase().contains('all episode');

        String formattedTitle;
        int? epNum;
        int? rStart;
        int? rEnd;

        if (rangeMatch != null) {
          rStart = int.tryParse(rangeMatch.group(1)!);
          rEnd = int.tryParse(rangeMatch.group(2)!);
          formattedTitle = 'Episode $rStart-$rEnd';
        } else if (singleMatch != null) {
          epNum = int.tryParse(singleMatch.group(1)!);
          formattedTitle = 'Episode ${epNum ?? episodes.length + 1}';
        } else if (isComplete) {
          final cl = clean.toLowerCase();
          if (cl.contains('all season')) {
            formattedTitle = 'All Seasons Complete';
          } else if (cl.contains('all episode')) {
            formattedTitle = 'All Episodes Complete';
          } else {
            final sNumMatch =
                RegExp(r'season\s*0*(\d+)', caseSensitive: false)
                    .firstMatch(clean);
            if (sNumMatch != null) {
              final s = int.tryParse(sNumMatch.group(1)!) ?? 1;
              formattedTitle =
                  'Season ${s.toString().padLeft(2, '0')} Complete';
            } else {
              formattedTitle = 'Season Complete';
            }
          }
        } else if (clean.isNotEmpty) {
          formattedTitle = clean;
        } else {
          epNum = episodes.length + 1;
          formattedTitle = 'Episode $epNum';
        }

        episodes.add(NextdriveEpisode(
          title: formattedTitle,
          vcloudUrl: href,
          index: episodes.length + 1,
          episodeNumber: epNum,
          rangeStart: rStart,
          rangeEnd: rEnd,
          isComplete: isComplete,
        ));
      }

      debugPrint('[SitePostExtractor] Extracted ${episodes.length} Nextdrive episodes from $nextdriveUrl');
      return episodes;
    } catch (e) {
      debugPrint('[SitePostExtractor] Error extracting Nextdrive episodes: $e');
      return [];
    }
  }

  /// Resolve a VCloud landing URL to direct stream and download links.
  Future<VcloudStreamResult> resolveVcloudStream(String vcloudUrl,
      {String? referer}) async {
    try {
      final vHtml = await fetchHtml(vcloudUrl, referer: referer);

      // 1. Look for double atob
      String? tokenUrl;
      final doubleAtobMatch = RegExp(
              r'atob\(\s*atob\(\s*[\x22\x27]([^\x22\x27]+)[\x22\x27]\s*\)\s*\)')
          .firstMatch(vHtml);
      if (doubleAtobMatch != null) {
        final s1 = utf8.decode(base64.decode(doubleAtobMatch.group(1)!));
        tokenUrl = utf8.decode(base64.decode(s1));
      } else {
        // 2. Single atob
        final singleAtobMatch =
            RegExp(r'atob\(\s*[\x22\x27]([^\x22\x27]+)[\x22\x27]\s*\)')
                .firstMatch(vHtml);
        if (singleAtobMatch != null) {
          final s1 = utf8.decode(base64.decode(singleAtobMatch.group(1)!));
          if (s1.contains('/') || s1.startsWith('http')) {
            tokenUrl = s1;
          }
        }
      }

      // 3. var url = '...' / location.href = '...'
      if (tokenUrl == null) {
        final varUrlMatch = RegExp(
                r'''(?:location\.href|window\.location|var\s+url)\s*=\s*['"]([^'"]+)['"]''',
                caseSensitive: false)
            .firstMatch(vHtml);
        if (varUrlMatch != null) {
          tokenUrl = varUrlMatch.group(1);
        }
      }

      if (tokenUrl == null) {
        return VcloudStreamResult();
      }

      if (!tokenUrl.startsWith('http')) {
        final p = Uri.parse(vcloudUrl);
        tokenUrl =
            '${p.scheme}://${p.host}${tokenUrl.startsWith('/') ? '' : '/'}$tokenUrl';
      }

      final dlHtml = await fetchHtml(tokenUrl, referer: vcloudUrl);
      final dlDoc = html_parser.parse(dlHtml);

      String? fslv2Url;
      String? fslUrl;
      String? tenGbpsUrl;
      String? pixeldrainUrl;

      for (final el in dlDoc.querySelectorAll('a[href]')) {
        var href = el.attributes['href'] ?? '';
        var text = el.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        final lt = text.toLowerCase();
        final lh = href.toLowerCase();

        if (lh.contains('telegram') ||
            lh.contains('t.me') ||
            lh.contains('admin') ||
            lh.contains('.fans')) {
          continue;
        }

        if (lt.contains('[fslv2 server]') ||
            el.attributes['id'] == 's3' ||
            lh.contains('r2.cloudflarestorage.com') ||
            lh.contains('fslv2')) {
          fslv2Url ??= href;
        } else if (lt.contains('[fsl server]') ||
            el.attributes['id'] == 'fsl' ||
            (lh.contains('fsl') && !lh.contains('fslv2'))) {
          fslUrl ??= href;
        } else if (lt.contains('10gbps') ||
            lt.contains('g-direct') ||
            lh.contains('gpdl') ||
            lh.contains('pixel.hubcloud')) {
          tenGbpsUrl ??= href;
        } else if (lt.contains('pixel') ||
            lh.contains('pixeldrain') ||
            lh.contains('sriflix')) {
          pixeldrainUrl ??= href;
        }
      }

      final pxlMatch = RegExp(r'''var\s+pxl\s*=\s*['"]([^'"]+)['"]''',
              caseSensitive: false)
          .firstMatch(dlHtml);
      if (pxlMatch != null && pxlMatch.group(1) != null) {
        pixeldrainUrl ??= pxlMatch.group(1);
      }

      return VcloudStreamResult(
        fslv2Url: fslv2Url,
        fslUrl: fslUrl,
        tenGbpsUrl: tenGbpsUrl,
        pixeldrainUrl: pixeldrainUrl,
      );
    } catch (e) {
      debugPrint('[SitePostExtractor] Error resolving VCloud stream: $e');
      return VcloudStreamResult();
    }
  }

  /// Resolve a Batch/Zip landing button to a direct `.zip` file download link.
  Future<String?> resolveBatchZipDirectLink(String batchZipLandingUrl) async {
    try {
      final html = await fetchHtml(batchZipLandingUrl);
      final doc = html_parser.parse(html);

      // Find V-Cloud button on this Batch/Zip page
      String? vcloudUrl;
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = a.attributes['href'] ?? '';
        final text = a.text.toLowerCase();
        if (href.contains('vcloud') || text.contains('v-cloud')) {
          vcloudUrl = href;
          break;
        }
      }

      if (vcloudUrl == null || vcloudUrl.isEmpty) {
        // Fallback: any direct anchor or hubcloud
        for (final a in doc.querySelectorAll('a[href]')) {
          final href = a.attributes['href'] ?? '';
          if (href.contains('vcloud') || href.contains('hubcloud')) {
            vcloudUrl = href;
            break;
          }
        }
      }

      if (vcloudUrl != null && vcloudUrl.isNotEmpty) {
        final result = await resolveVcloudStream(vcloudUrl,
            referer: batchZipLandingUrl);
        return result.bestDownloadUrl;
      }
    } catch (e) {
      debugPrint('[SitePostExtractor] Error resolving Batch/Zip link: $e');
    }
    return null;
  }
}
