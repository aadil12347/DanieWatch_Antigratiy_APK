import 'dart:convert';
import 'dart:io';
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
  final List<String> alternativeUrls;
  final int index;
  final int? episodeNumber;
  final int? rangeStart;
  final int? rangeEnd;
  final bool isComplete;
  String? thumbnailUrl; // Set from TMDB still or poster fallback
  String? exactSize; // Cached exact file size e.g. "477.72 MB"
  VcloudStreamResult? preResolvedStream; // Pre-resolved direct stream result
  Map<String, String>? otherResolutions; // Map of quality -> vcloudUrl
  Map<String, String>? otherResolutionSizes; // Map of quality -> exactSize

  NextdriveEpisode({
    required this.title,
    required this.vcloudUrl,
    List<String>? alternativeUrls,
    required this.index,
    this.episodeNumber,
    this.rangeStart,
    this.rangeEnd,
    this.isComplete = false,
    this.thumbnailUrl,
    this.exactSize,
    this.preResolvedStream,
    this.otherResolutions,
    this.otherResolutionSizes,
  }) : alternativeUrls = alternativeUrls ?? [];

  NextdriveEpisode copyWith({
    String? title,
    String? vcloudUrl,
    List<String>? alternativeUrls,
    int? index,
    int? episodeNumber,
    int? rangeStart,
    int? rangeEnd,
    bool? isComplete,
    String? thumbnailUrl,
    String? exactSize,
    VcloudStreamResult? preResolvedStream,
    Map<String, String>? otherResolutions,
    Map<String, String>? otherResolutionSizes,
  }) {
    return NextdriveEpisode(
      title: title ?? this.title,
      vcloudUrl: vcloudUrl ?? this.vcloudUrl,
      alternativeUrls:
          alternativeUrls ?? List<String>.from(this.alternativeUrls),
      index: index ?? this.index,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      rangeStart: rangeStart ?? this.rangeStart,
      rangeEnd: rangeEnd ?? this.rangeEnd,
      isComplete: isComplete ?? this.isComplete,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      exactSize: exactSize ?? this.exactSize,
      preResolvedStream: preResolvedStream ?? this.preResolvedStream,
      otherResolutions: otherResolutions ??
          (this.otherResolutions != null
              ? Map<String, String>.from(this.otherResolutions!)
              : null),
      otherResolutionSizes: otherResolutionSizes ??
          (this.otherResolutionSizes != null
              ? Map<String, String>.from(this.otherResolutionSizes!)
              : null),
    );
  }

  @override
  String toString() =>
      'NextdriveEpisode(index: $index, title: "$title", epNum: $episodeNumber, range: $rangeStart-$rangeEnd, isComplete: $isComplete, url: "$vcloudUrl", size: $exactSize, preResolved: ${preResolvedStream != null})';
}

/// Resolved stream URLs from VCloud.
class VcloudStreamResult {
  final String? fslv2Url;
  final String? fslUrl;
  final String? tenGbpsUrl;
  final String? pixeldrainUrl;
  final String? fastDlUrl;
  final String? fileSize;

  VcloudStreamResult({
    this.fslv2Url,
    this.fslUrl,
    this.tenGbpsUrl,
    this.pixeldrainUrl,
    this.fastDlUrl,
    this.fileSize,
  });

  /// Online playback policy:
  /// Strictly FSLv2 > FSL > FastDL (GoogleUserContent) > Pixeldrain direct API.
  /// NO 10Gbps link for online play.
  String? get onlineStreamUrl {
    if (fslv2Url != null && fslv2Url!.isNotEmpty) return fslv2Url;
    if (fslUrl != null && fslUrl!.isNotEmpty) return fslUrl;
    if (fastDlUrl != null && fastDlUrl!.isNotEmpty) return fastDlUrl;
    if (pixeldrainUrl != null && pixeldrainUrl!.isNotEmpty) {
      if (pixeldrainUrl!.contains('/u/')) {
        final id = pixeldrainUrl!.split('/u/').last.split('?').first.trim();
        return 'https://pixeldrain.com/api/file/$id';
      }
      return pixeldrainUrl;
    }
    return null;
  }

  bool get canStreamOnline => onlineStreamUrl != null;

  /// Download fallback:
  /// FSLv2 > FSL > FastDL > Pixeldrain > 10Gbps
  String? get bestDownloadUrl =>
      fslv2Url ?? fslUrl ?? fastDlUrl ?? pixeldrainUrl ?? tenGbpsUrl;

  @override
  String toString() =>
      'VcloudStreamResult(FSLv2: $fslv2Url, FSL: $fslUrl, FastDL: $fastDlUrl, 10Gbps: $tenGbpsUrl, PXL: $pixeldrainUrl, Size: $fileSize)';
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

  /// Cache of exact file sizes parsed from VCloud pages (vcloudUrl -> "394.05 MB")
  final Map<String, String> _vcloudSizeCache = {};

  /// Parses the exact file size string from VCloud/HubCloud page HTML
  static String? parseExactSizeFromHtml(String html) {
    if (html.isEmpty) return null;
    // Pattern 1: id="size" attribute (e.g. <i id="size">394.05 MB</i>)
    final idMatch = RegExp(r'''id=["\']size["\'][^>]*>([^<]+)<''', caseSensitive: false).firstMatch(html);
    if (idMatch != null) {
      final s = idMatch.group(1)?.trim();
      if (s != null && s.isNotEmpty && s.toUpperCase() != 'NAN' && !s.startsWith('{')) {
        return s;
      }
    }

    // Pattern 2: Size element (e.g. Size<i id="...">394.05 MB</i> or Size: 394.05 MB)
    final sizeMatch = RegExp(
      r'''Size\s*(?:<[^>]+>|\s|:)*\s*([0-9]+(?:\.[0-9]+)?\s*(?:GB|MB|KB|GiB|MiB|KiB|Bytes|B))\b''',
      caseSensitive: false,
    ).firstMatch(html);
    if (sizeMatch != null) {
      final s = sizeMatch.group(1)?.trim();
      if (s != null && s.isNotEmpty && s.toUpperCase() != 'NAN') {
        return s;
      }
    }

    // Pattern 3: File Size
    final fsMatch = RegExp(
      r'''(?:File\s*Size|FileSize)\s*[:\-]?\s*([0-9]+(?:\.[0-9]+)?\s*(?:GB|MB|KB|GiB|MiB|KiB))\b''',
      caseSensitive: false,
    ).firstMatch(html);
    if (fsMatch != null) {
      final s = fsMatch.group(1)?.trim();
      if (s != null && s.isNotEmpty) {
        return s;
      }
    }
    return null;
  }

  /// Parses exact bytes integer from a size string like "394.05 MB" or "1.45 GB"
  static int? parseBytesFromSizeString(String? sizeStr) {
    if (sizeStr == null || sizeStr.isEmpty) return null;
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*(GB|MB|KB|Bytes|B)', caseSensitive: false).firstMatch(sizeStr);
    if (match == null) return null;
    final val = double.tryParse(match.group(1)!);
    if (val == null) return null;
    final unit = match.group(2)!.toUpperCase();
    if (unit.contains('GB')) {
      return (val * 1024 * 1024 * 1024).round();
    } else if (unit.contains('MB')) {
      return (val * 1024 * 1024).round();
    } else if (unit.contains('KB')) {
      return (val * 1024).round();
    } else {
      return val.round();
    }
  }

  /// Fast, code-only stream fetcher with early socket termination.
  /// Bypasses downloading heavy HTML/JS once required content (e.g. size or token) is found.
  Future<String> fastFetchStream(
    String url, {
    String? referer,
    bool Function(String text)? stopCondition,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse(url);
      final req = await client.getUrl(uri).timeout(timeout);
      req.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36');
      req.headers.set(HttpHeaders.acceptHeader,
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
      if (referer != null && referer.isNotEmpty) {
        req.headers.set(HttpHeaders.refererHeader, referer);
      } else {
        req.headers.set(HttpHeaders.refererHeader, '${uri.scheme}://${uri.host}/');
      }

      final resp = await req.close().timeout(timeout);
      final buffer = StringBuffer();

      await for (final chunk in resp.transform(utf8.decoder)) {
        buffer.write(chunk);
        if (stopCondition != null && stopCondition(buffer.toString())) {
          resp.detachSocket().then((s) => s.destroy()).catchError((_) {});
          break;
        }
      }

      return buffer.toString();
    } catch (e) {
      debugPrint('[SitePostExtractor] fastFetchStream error for $url: $e');
      return '';
    } finally {
      client.close();
    }
  }

  /// Extracts the exact file size from a VCloud page or landing URL.
  Future<String?> extractExactFileSizeFromVcloud(String vcloudUrl) async {
    if (vcloudUrl.isEmpty) return null;
    if (_vcloudSizeCache.containsKey(vcloudUrl)) {
      return _vcloudSizeCache[vcloudUrl];
    }

    try {
      String targetUrl = vcloudUrl;
      final lh = targetUrl.toLowerCase();
      if (lh.contains('nexdrive') ||
          lh.contains('vgmlink') ||
          lh.contains('fastdl') ||
          lh.contains('gdflix') ||
          lh.contains('filebee')) {
        final resolved = await extractVcloudFromLandingPublic(targetUrl);
        if (resolved != null && resolved.isNotEmpty) {
          targetUrl = resolved;
        }
      }

      String html = await fastFetchStream(
        targetUrl,
        stopCondition: (text) =>
            text.contains('id="size"') &&
            (text.contains('atob(atob(') || text.contains('atob(') || text.contains('var url')),
      );
      if (html.isEmpty) {
        html = await fetchHtml(targetUrl);
      }
      String? size = parseExactSizeFromHtml(html);

      // If not on initial page, check if there's a tokenUrl or redirect
      if (size == null) {
        String? tokenUrl;
        final doubleAtobMatch = RegExp(
                r'atob\(\s*atob\(\s*[\x22\x27]([^\x22\x27]+)[\x22\x27]\s*\)\s*\)')
            .firstMatch(html);
        if (doubleAtobMatch != null) {
          final s1 = utf8.decode(base64.decode(doubleAtobMatch.group(1)!));
          tokenUrl = utf8.decode(base64.decode(s1));
        } else {
          final varUrlMatch = RegExp(
                  r'''(?:location\.href|window\.location|var\s+url)\s*=\s*['"]([^'"]+)['"]''',
                  caseSensitive: false)
              .firstMatch(html);
          if (varUrlMatch != null) {
            tokenUrl = varUrlMatch.group(1);
          }
        }
        if (tokenUrl != null) {
          if (!tokenUrl.startsWith('http')) {
            final p = Uri.parse(targetUrl);
            tokenUrl = '${p.scheme}://${p.host}${tokenUrl.startsWith('/') ? '' : '/'}$tokenUrl';
          }
          String dlHtml = await fastFetchStream(
            tokenUrl,
            referer: targetUrl,
            stopCondition: (text) =>
                text.contains('id="size"') ||
                text.contains('[FSLv2 Server]') ||
                text.contains('id="s3"'),
          );
          if (dlHtml.isEmpty) {
            dlHtml = await fetchHtml(tokenUrl, referer: targetUrl);
          }
          size = parseExactSizeFromHtml(dlHtml);
        }
      }

      if (size != null && size.isNotEmpty) {
        _vcloudSizeCache[vcloudUrl] = size;
        return size;
      }
    } catch (e) {
      debugPrint('[SitePostExtractor] Error extracting file size from vcloud: $e');
    }
    return null;
  }

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

        // Check if nearby heading text mentions batch/zip
        bool headingHasBatch = false;
        var checkEl = a.parent;
        while (checkEl != null && checkEl != contentEl) {
          final prevSib = checkEl.previousElementSibling;
          if (prevSib != null) {
            final prevText = prevSib.text.toLowerCase();
            final prevTag = (prevSib.localName ?? '').toLowerCase();
            if (RegExp(r'^h[1-6]$|^p$|^strong$').hasMatch(prevTag) &&
                (prevText.contains('batch') ||
                    prevText.contains('zip') ||
                    prevText.contains('full season') ||
                    prevText.contains('complete season') ||
                    prevText.contains('all episodes'))) {
              headingHasBatch = true;
              break;
            }
          }
          checkEl = checkEl.parent;
        }

        final isBatchZip = lowerText.contains('batch') ||
            lowerText.contains('zip') ||
            lowerText.contains('pack') ||
            lowerText.contains('full season') ||
            lowerText.contains('complete season') ||
            lowerText.contains('all episodes') ||
            headingHasBatch;

        final isEpisodeList = lowerText.contains('episode') ||
            lowerText.contains('v-cloud') ||
            lowerText.contains('vcloud') ||
            lowerText.contains('g-direct') ||
            lowerText.contains('instant') ||
            lowerText.contains('direct') ||
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
  /// Priority: 720p > 480p > 1080p fallback, checking Nextdrive pages from G-Direct / Instant buttons as well.
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

    // Preference: 720p > 480p > 1080p > others.
    // For each quality, prefer a button with V-Cloud/Resumable in text, but accept G-Direct/Instant
    // if that quality only has G-Direct (as Nextdrive pages contain VCloud links).
    SitePostButton? pickForQuality(String q) {
      final matches = seasonButtons
          .where((b) => b.quality.toLowerCase() == q.toLowerCase())
          .toList();
      if (matches.isEmpty) return null;
      final vcloud = matches.firstWhere(
        (b) =>
            b.text.toLowerCase().contains('v-cloud') ||
            b.text.toLowerCase().contains('vcloud') ||
            b.text.toLowerCase().contains('resumable'),
        orElse: () => matches.first,
      );
      return vcloud;
    }

    return pickForQuality('720p') ??
        pickForQuality('480p') ??
        pickForQuality('1080p') ??
        pickForQuality('2160p') ??
        seasonButtons.first;
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

  /// Extract available resolutions map (e.g. {'480p': 'vcloud...', '720p': 'vcloud...', '1080p': 'vcloud...'})
  /// for both Movies and TV Series (any season, any episode) on Vegamovies and Rogmovies.
  Future<Map<String, String>> getAvailableResolutionsForContent({
    required String postUrl,
    required bool isMovie,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final Map<String, String> resMap = {};
    try {
      final buttons = await extractPostButtons(postUrl);
      if (buttons.isEmpty) return resMap;

      if (isMovie) {
        // Movies: Each non-batch button corresponds to a resolution
        final nonBatch = buttons.where((b) => !b.isBatchZip).toList();
        for (final b in nonBatch) {
          final q = b.quality.toLowerCase();
          if (resMap.containsKey(q)) continue;

          final lh = b.href.toLowerCase();
          if (lh.contains('vcloud') || lh.contains('hubcloud')) {
            resMap[q] = b.href;
          } else {
            try {
              final vcloud = await _extractVcloudFromLanding(b.href);
              if (vcloud != null && vcloud.isNotEmpty) {
                resMap[q] = vcloud;
              } else {
                resMap[q] = b.href;
              }
            } catch (e) {
              debugPrint('[SitePostExtractor] Error resolving landing for $q: $e');
              resMap[q] = b.href;
            }
          }
        }
      } else {
        // TV Series: Find season buttons for seasonNumber
        final sNum = seasonNumber ?? 1;
        final targetEpNum = episodeNumber ?? 1;

        final seasonButtons = buttons
            .where((b) => b.seasonNumber == sNum && !b.isBatchZip)
            .toList();

        final targetBtns = (seasonButtons.isEmpty && sNum == 1)
            ? buttons.where((b) => !b.isBatchZip).toList()
            : seasonButtons;

        for (final b in targetBtns) {
          final q = b.quality.toLowerCase();
          if (resMap.containsKey(q)) continue;

          final lh = b.href.toLowerCase();
          if (lh.contains('nexdrive') ||
              lh.contains('vgmlink') ||
              lh.contains('fastdl') ||
              lh.contains('gdflix') ||
              lh.contains('filebee')) {
            try {
              final episodes = await extractNextdriveEpisodes(b.href);
              if (episodes.isNotEmpty) {
                final match = episodes.firstWhere(
                  (e) => (e.episodeNumber ?? e.index) == targetEpNum,
                  orElse: () => (targetEpNum <= episodes.length
                      ? episodes[targetEpNum - 1]
                      : episodes.first),
                );
                resMap[q] = match.vcloudUrl;
              }
            } catch (e) {
              debugPrint('[SitePostExtractor] Error extracting episodes for quality $q: $e');
            }
          } else if (lh.contains('vcloud') || lh.contains('hubcloud')) {
            resMap[q] = b.href;
          }
        }
      }
    } catch (e) {
      debugPrint('[SitePostExtractor] Error getting resolutions: $e');
    }
    return resMap;
  }

  /// Pre-resolves 720p direct stream and exact size for all episodes of the given season.
  /// Runs in background without blocking UI, prioritizing the first episode.
  Future<void> preResolveSeasonEpisodes(
    List<NextdriveEpisode> episodes, {
    int? priorityIndex,
  }) async {
    if (episodes.isEmpty) return;

    debugPrint('[SitePostExtractor] Starting background pre-resolution for ${episodes.length} episodes...');

    // Prioritize the requested episode (or Episode 1)
    final pIdx = (priorityIndex != null &&
            priorityIndex >= 0 &&
            priorityIndex < episodes.length)
        ? priorityIndex
        : 0;

    final orderedIndices = <int>[pIdx];
    for (int i = 0; i < episodes.length; i++) {
      if (i != pIdx) orderedIndices.add(i);
    }

    // Resolve in small batches (e.g. 2 concurrent) so connection is not saturated
    const batchSize = 2;
    for (int i = 0; i < orderedIndices.length; i += batchSize) {
      final chunk = orderedIndices.skip(i).take(batchSize).toList();
      await Future.wait(chunk.map((idx) async {
        final ep = episodes[idx];
        if (ep.preResolvedStream != null && ep.exactSize != null) return;

        try {
          final res = await resolveVcloudStream(
            ep.vcloudUrl,
            alternativeUrls: ep.alternativeUrls,
          );
          ep.preResolvedStream = res;
          if (res.fileSize != null && res.fileSize!.isNotEmpty) {
            ep.exactSize = res.fileSize;
            _vcloudSizeCache[ep.vcloudUrl] = res.fileSize!;
          }
          debugPrint(
              '[SitePostExtractor] Pre-resolved Ep ${ep.episodeNumber ?? ep.index} (720p): '
              'stream=${res.onlineStreamUrl != null}, size=${res.fileSize}');
        } catch (e) {
          debugPrint(
              '[SitePostExtractor] Failed pre-resolving Ep ${ep.episodeNumber ?? ep.index}: $e');
        }
      }));
    }
  }

  /// Fetches other resolutions (e.g. 480p, 1080p) for a specific episode in a season.
  /// Parallelizes extraction across buttons and enriches the target episode with pre-cached links and sizes.
  Future<Map<String, String>> fetchOtherResolutionsForEpisode({
    required String postUrl,
    required int seasonNumber,
    required int episodeNumber,
    required String currentQuality,
    NextdriveEpisode? targetEpisode,
  }) async {
    final Map<String, String> resMap = {};

    // If targetEpisode already has cached otherResolutions, return immediately!
    if (targetEpisode?.otherResolutions != null &&
        targetEpisode!.otherResolutions!.isNotEmpty) {
      return Map<String, String>.from(targetEpisode.otherResolutions!);
    }

    try {
      final buttons = await extractPostButtons(postUrl);
      if (buttons.isEmpty) return resMap;

      final seasonButtons = buttons
          .where((b) =>
              b.seasonNumber == seasonNumber &&
              !b.isBatchZip &&
              b.quality.toLowerCase() != currentQuality.toLowerCase())
          .toList();

      if (seasonButtons.isEmpty) return resMap;

      // Group buttons by quality, picking best button per quality
      final Map<String, SitePostButton> bestPerQuality = {};
      for (final b in seasonButtons) {
        final q = b.quality.toLowerCase();
        if (!bestPerQuality.containsKey(q)) {
          bestPerQuality[q] = b;
        } else {
          final bt = b.text.toLowerCase();
          if (bt.contains('v-cloud') ||
              bt.contains('vcloud') ||
              bt.contains('resumable')) {
            bestPerQuality[q] = b;
          }
        }
      }

      // Fetch each quality in parallel
      await Future.wait(bestPerQuality.entries.map((entry) async {
        final q = entry.key;
        final b = entry.value;
        final lh = b.href.toLowerCase();

        try {
          if (lh.contains('nexdrive') ||
              lh.contains('vgmlink') ||
              lh.contains('fastdl') ||
              lh.contains('gdflix') ||
              lh.contains('filebee')) {
            final episodes = await extractNextdriveEpisodes(b.href);
            if (episodes.isNotEmpty) {
              final match = episodes.firstWhere(
                (e) => (e.episodeNumber ?? e.index) == episodeNumber,
                orElse: () => (episodeNumber <= episodes.length
                    ? episodes[episodeNumber - 1]
                    : episodes.first),
              );
              if (match.vcloudUrl.isNotEmpty) {
                resMap[q] = match.vcloudUrl;
                extractExactFileSizeFromVcloud(match.vcloudUrl).then((size) {
                  if (size != null && size.isNotEmpty && targetEpisode != null) {
                    targetEpisode.otherResolutionSizes ??= {};
                    targetEpisode.otherResolutionSizes![q] = size;
                  }
                });
              }
            }
          } else if (lh.contains('vcloud') || lh.contains('hubcloud')) {
            resMap[q] = b.href;
            extractExactFileSizeFromVcloud(b.href).then((size) {
              if (size != null && size.isNotEmpty && targetEpisode != null) {
                targetEpisode.otherResolutionSizes ??= {};
                targetEpisode.otherResolutionSizes![q] = size;
              }
            });
          }
        } catch (e) {
          debugPrint(
              '[SitePostExtractor] Error fetching $q for Ep $episodeNumber: $e');
        }
      }));

      if (targetEpisode != null && resMap.isNotEmpty) {
        targetEpisode.otherResolutions ??= {};
        targetEpisode.otherResolutions!.addAll(resMap);
      }
    } catch (e) {
      debugPrint(
          '[SitePostExtractor] Error in fetchOtherResolutionsForEpisode: $e');
    }

    return resMap;
  }

  /// Helper to extract first VCloud anchor from a movie Nexdrive/G-Direct landing page
  Future<String?> _extractVcloudFromLanding(String landingUrl) async {
    try {
      final lhUrl = landingUrl.toLowerCase();
      if (lhUrl.contains('vcloud') || lhUrl.contains('hubcloud')) {
        return landingUrl;
      }
      final html = await fetchHtml(landingUrl);
      final doc = html_parser.parse(html);
      String? fallbackUrl;

      for (final a in doc.querySelectorAll('a[href]')) {
        var href = a.attributes['href'] ?? '';
        if (href.isEmpty) continue;
        try {
          href = Uri.parse(landingUrl).resolve(href).toString();
        } catch (_) {}
        final lh = href.toLowerCase();
        if (lh.contains('telegram') ||
            lh.contains('facebook') ||
            lh.contains('twitter') ||
            lh.contains('t.me') ||
            lh.contains('.fans') ||
            lh.contains('whatsapp')) {
          continue;
        }
        // First priority: VCloud or HubCloud link
        if (lh.contains('vcloud') || lh.contains('hubcloud')) {
          return href;
        }
        // Backup: FastDL, Vegadrive, Filebee, Pixeldrain
        if (fallbackUrl == null &&
            (lh.contains('fastdl') ||
                lh.contains('vegadrive') ||
                lh.contains('filebee') ||
                lh.contains('pixeldrain'))) {
          fallbackUrl = href;
        }
      }
      return fallbackUrl;
    } catch (e) {
      debugPrint('[SitePostExtractor] _extractVcloudFromLanding error: $e');
    }
    return null;
  }

  /// Public wrapper for _extractVcloudFromLanding — resolves a nexdrive/landing page to a VCloud URL
  Future<String?> extractVcloudFromLandingPublic(String landingUrl) =>
      _extractVcloudFromLanding(landingUrl);

  /// Extract episodes directly from a Nextdrive episode selector page.
  /// Strictly extracts the episode titles from the page itself (never TMDB).
  /// Handles both old format and new format:
  ///   Old: <h4>Episode 1</h4> <p><a href="vcloud...">...</a></p>
  ///   New: <h4>-:Episode: 1:-</h4> <p><a href="vcloud...">...</a></p>
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

      // Search all anchors pointing to vcloud, fastdl, vegadrive, filebee
      final anchors = doc.querySelectorAll('a[href]');
      for (final a in anchors) {
        var href = a.attributes['href'] ?? '';
        if (href.isEmpty) continue;
        try {
          href = Uri.parse(nextdriveUrl).resolve(href).toString();
        } catch (_) {}

        final lhref = href.toLowerCase();
        final isSupported = lhref.contains('vcloud') ||
            lhref.contains('hubcloud') ||
            lhref.contains('fastdl') ||
            lhref.contains('vegadrive') ||
            lhref.contains('filebee');
        if (!isSupported) continue;

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

        // If an episode with the same episodeNumber or title already exists, attach as alternativeUrl
        final existingIdx = episodes.indexWhere((e) =>
            (epNum != null && e.episodeNumber == epNum) ||
            e.title.toLowerCase() == formattedTitle.toLowerCase());
        if (existingIdx >= 0) {
          final existing = episodes[existingIdx];
          final isNewVcloud = href.toLowerCase().contains('vcloud') ||
              href.toLowerCase().contains('hubcloud');
          final isOldVcloud = existing.vcloudUrl.toLowerCase().contains('vcloud') ||
              existing.vcloudUrl.toLowerCase().contains('hubcloud');

          if (isNewVcloud && !isOldVcloud) {
            // Priority upgrade: V-Cloud is preferred over FastDL/others as the primary vcloudUrl!
            final oldPrimary = existing.vcloudUrl;
            final updatedAlts = List<String>.from(existing.alternativeUrls);
            if (!updatedAlts.contains(oldPrimary)) {
              updatedAlts.add(oldPrimary);
            }
            episodes[existingIdx] = existing.copyWith(
              vcloudUrl: href,
              alternativeUrls: updatedAlts,
            );
            debugPrint('[SitePostExtractor] Upgraded Ep ${existing.episodeNumber ?? existing.index} primary to VCloud: $href (was $oldPrimary)');
          } else {
            if (!existing.alternativeUrls.contains(href)) {
              existing.alternativeUrls.add(href);
            }
          }
          continue;
        }

        episodes.add(NextdriveEpisode(
          title: formattedTitle,
          vcloudUrl: href,
          alternativeUrls: [],
          index: episodes.length + 1,
          episodeNumber: epNum,
          rangeStart: rStart,
          rangeEnd: rEnd,
          isComplete: isComplete,
        ));
      }

      // Final pass: ensure vcloudUrl is strictly a V-Cloud / HubCloud link if one is available
      for (int i = 0; i < episodes.length; i++) {
        final ep = episodes[i];
        final isPrimaryVcloud = ep.vcloudUrl.toLowerCase().contains('vcloud') ||
            ep.vcloudUrl.toLowerCase().contains('hubcloud');
        if (!isPrimaryVcloud) {
          final vcloudAltIdx = ep.alternativeUrls.indexWhere((u) =>
              u.toLowerCase().contains('vcloud') ||
              u.toLowerCase().contains('hubcloud'));
          if (vcloudAltIdx >= 0) {
            final vcloudLink = ep.alternativeUrls.removeAt(vcloudAltIdx);
            final updatedAlts = [ep.vcloudUrl, ...ep.alternativeUrls];
            episodes[i] = ep.copyWith(
              vcloudUrl: vcloudLink,
              alternativeUrls: updatedAlts,
            );
            debugPrint('[SitePostExtractor] Re-prioritized Ep ${ep.episodeNumber ?? ep.index} primary to VCloud: $vcloudLink');
          }
        }
      }

      debugPrint('[SitePostExtractor] Extracted ${episodes.length} Nextdrive episodes from $nextdriveUrl');
      return episodes;
    } catch (e) {
      debugPrint('[SitePostExtractor] Error extracting Nextdrive episodes: $e');
      return [];
    }
  }

  /// Resolve a VCloud landing URL or FastDL / GoogleUserContent / Pixeldrain direct stream link.
  /// Strictly prioritizes V-Cloud / HubCloud servers (FSLv2, FSL, 10Gbps, Pixeldrain) over FastDL.
  Future<VcloudStreamResult> resolveVcloudStream(
    String vcloudUrl, {
    String? referer,
    List<String>? alternativeUrls,
  }) async {
    // 1. Collect all candidate URLs, prioritizing V-Cloud / HubCloud first over FastDL
    final candidates = <String>[];
    if (vcloudUrl.isNotEmpty) candidates.add(vcloudUrl);
    if (alternativeUrls != null) {
      for (final alt in alternativeUrls) {
        if (alt.isNotEmpty && !candidates.contains(alt)) {
          candidates.add(alt);
        }
      }
    }

    // Sort candidates: vcloud/hubcloud strictly first!
    candidates.sort((a, b) {
      final aIsVcloud = a.toLowerCase().contains('vcloud') || a.toLowerCase().contains('hubcloud');
      final bIsVcloud = b.toLowerCase().contains('vcloud') || b.toLowerCase().contains('hubcloud');
      if (aIsVcloud && !bIsVcloud) return -1;
      if (!aIsVcloud && bIsVcloud) return 1;
      return 0;
    });

    VcloudStreamResult? fallbackRes;
    for (final candidate in candidates) {
      try {
        final res = await _resolveSingleStreamLink(candidate, referer: referer);
        if (res.canStreamOnline ||
            (res.tenGbpsUrl != null && res.tenGbpsUrl!.isNotEmpty) ||
            (res.pixeldrainUrl != null && res.pixeldrainUrl!.isNotEmpty)) {
          return res;
        }
        fallbackRes ??= res;
      } catch (e) {
        debugPrint('[SitePostExtractor] Error resolving stream candidate $candidate: $e');
      }
    }

    return fallbackRes ?? VcloudStreamResult();
  }

  Future<VcloudStreamResult> _resolveSingleStreamLink(String url,
      {String? referer}) async {
    try {
      final lurl = url.toLowerCase();

      // Case A: FastDL embed link (yields direct Google User Content video stream)
      if (lurl.contains('fastdl.zip')) {
        final fHtml = await fetchHtml(url,
            referer: referer ?? 'https://fastdl.zip/');
        final gMatch = RegExp(
                r'link=(https://video-downloads\.googleusercontent\.com/[^"\x27\s]+)')
            .firstMatch(fHtml);
        if (gMatch != null) {
          return VcloudStreamResult(fastDlUrl: gMatch.group(1));
        }
        final reMatch =
            RegExp(r'''var\s+reurl\s*=\s*['"]([^'"]+)['"]''').firstMatch(fHtml);
        if (reMatch != null) {
          final reurl = reMatch.group(1)!;
          if (reurl.contains('googleusercontent.com')) {
            final inner = RegExp(
                    r'link=(https://video-downloads\.googleusercontent\.com/[^"\x27\s]+)')
                .firstMatch(reurl);
            if (inner != null) {
              return VcloudStreamResult(fastDlUrl: inner.group(1));
            }
          }
          return VcloudStreamResult(fastDlUrl: reurl);
        }
      }

      // Case B: Direct Pixeldrain link
      if (lurl.contains('pixeldrain.com/u/') ||
          lurl.contains('pixeldrain.dev/u/')) {
        final id = url.split('/u/').last.split('?').first.trim();
        return VcloudStreamResult(
            pixeldrainUrl: 'https://pixeldrain.dev/api/file/$id');
      }

      // Case C: Vegadrive landing
      if (lurl.contains('vegadrive.app/s/') ||
          lurl.contains('vegadrive.me/d/')) {
        final vdHtml =
            await fetchHtml(url, referer: referer ?? 'https://nexdrive.fit/');
        final vdDoc = html_parser.parse(vdHtml);
        for (final a in vdDoc.querySelectorAll('a[href]')) {
          final h = a.attributes['href'] ?? '';
          final lh = h.toLowerCase();
          if (lh.contains('gofile') || lh.contains('buzzheavier')) {
            return VcloudStreamResult(fastDlUrl: h);
          }
        }
      }

      // Case D: Standard V-Cloud
      String vHtml = await fastFetchStream(
        url,
        referer: referer,
        stopCondition: (text) =>
            text.contains('id="size"') &&
            (text.contains('atob(atob(') || text.contains('atob(') || text.contains('var url')),
      );
      if (vHtml.isEmpty) {
        vHtml = await fetchHtml(url, referer: referer);
      }
      String? exactFileSize = parseExactSizeFromHtml(vHtml);

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

      // 4. Check for intermediate VCloud / HubCloud landing page (e.g. vcloud.fit/api/index.php?link=...)
      String effectiveReferer = url;
      if (tokenUrl == null) {
        String? intermediateUrl;
        final vDoc = html_parser.parse(vHtml);
        for (final a in vDoc.querySelectorAll('a[href]')) {
          final href = a.attributes['href']?.trim() ?? '';
          final text = a.text.trim().toLowerCase();
          final lh = href.toLowerCase();
          if (href.isEmpty || href == '#' || lh.startsWith('javascript:')) continue;
          if (lh.contains('telegram') || lh.contains('t.me') || lh.contains('facebook')) continue;

          if (text.contains('direct download') ||
              text.contains('resume') ||
              text.contains('download [resume]') ||
              lh.contains('vcloud.zip') ||
              (lh.contains('vcloud') && !lh.contains('index.php')) ||
              (lh.contains('hubcloud') && !lh.contains('index.php'))) {
            intermediateUrl = href;
            break;
          }
        }

        if (intermediateUrl != null && intermediateUrl.isNotEmpty) {
          if (!intermediateUrl.startsWith('http')) {
            final p = Uri.parse(url);
            intermediateUrl =
                '${p.scheme}://${p.host}${intermediateUrl.startsWith('/') ? '' : '/'}$intermediateUrl';
          }
          debugPrint('[SitePostExtractor] Following intermediate VCloud link: $intermediateUrl');
          try {
            final intermediateHtml = await fetchHtml(intermediateUrl, referer: url);
            exactFileSize ??= parseExactSizeFromHtml(intermediateHtml);

            // Double atob on intermediate page
            final m2 = RegExp(
                    r'atob\(\s*atob\(\s*[\x22\x27]([^\x22\x27]+)[\x22\x27]\s*\)\s*\)')
                .firstMatch(intermediateHtml);
            if (m2 != null) {
              try {
                final s1 = utf8.decode(base64.decode(m2.group(1)!));
                tokenUrl = utf8.decode(base64.decode(s1));
              } catch (_) {}
            }

            // Single atob on intermediate page
            if (tokenUrl == null) {
              final m1 = RegExp(
                      r'atob\(\s*[\x22\x27]([^\x22\x27]+)[\x22\x27]\s*\)')
                  .firstMatch(intermediateHtml);
              if (m1 != null) {
                try {
                  final s1 = utf8.decode(base64.decode(m1.group(1)!));
                  if (s1.contains('/') || s1.startsWith('http')) {
                    tokenUrl = s1;
                  }
                } catch (_) {}
              }
            }

            // var url = '...' on intermediate page
            if (tokenUrl == null) {
              final varUrlMatch = RegExp(
                      r'''(?:location\.href|window\.location|var\s+url)\s*=\s*['"]([^'"]+)['"]''',
                      caseSensitive: false)
                  .firstMatch(intermediateHtml);
              if (varUrlMatch != null) {
                tokenUrl = varUrlMatch.group(1);
              }
            }

            effectiveReferer = intermediateUrl;
          } catch (e) {
            debugPrint('[SitePostExtractor] Error fetching intermediate link: $e');
          }
        }
      }

      if (tokenUrl == null) {
        return VcloudStreamResult(fileSize: exactFileSize);
      }

      if (!tokenUrl.startsWith('http')) {
        final p = Uri.parse(effectiveReferer);
        tokenUrl =
            '${p.scheme}://${p.host}${tokenUrl.startsWith('/') ? '' : '/'}$tokenUrl';
      }

      String dlHtml = await fastFetchStream(
        tokenUrl,
        referer: effectiveReferer,
        stopCondition: (text) =>
            (text.contains('[FSLv2 Server]') || text.contains('id="s3"') || text.contains('fslv2')) &&
            (text.contains('[FSL Server]') || text.contains('id="fsl"') || text.contains('fsl')),
      );
      if (dlHtml.isEmpty) {
        dlHtml = await fetchHtml(tokenUrl, referer: effectiveReferer);
      }
      exactFileSize ??= parseExactSizeFromHtml(dlHtml);
      if (exactFileSize != null && exactFileSize.isNotEmpty) {
        _vcloudSizeCache[url] = exactFileSize;
      }
      final dlDoc = html_parser.parse(dlHtml);

      String? fslv2Url;
      String? fslUrl;
      String? tenGbpsUrl;
      String? pixeldrainUrl;
      String? fastDlUrl;

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
        } else if (lt.contains('gofile') || lh.contains('gofile.io')) {
          fastDlUrl ??= href;
        }
      }

      final pxlMatch = RegExp(r'''var\s+pxl\s*=\s*['"]([^'"]+)['"]''',
              caseSensitive: false)
          .firstMatch(dlHtml);
      if (pxlMatch != null && pxlMatch.group(1) != null) {
        pixeldrainUrl ??= pxlMatch.group(1);
      }

      if (pixeldrainUrl != null && pixeldrainUrl.contains('/u/')) {
        final id = pixeldrainUrl.split('/u/').last.split('?').first.trim();
        pixeldrainUrl = 'https://pixeldrain.com/api/file/$id';
      }

      return VcloudStreamResult(
        fslv2Url: fslv2Url,
        fslUrl: fslUrl,
        tenGbpsUrl: tenGbpsUrl,
        pixeldrainUrl: pixeldrainUrl,
        fastDlUrl: fastDlUrl,
        fileSize: exactFileSize,
      );
    } catch (e) {
      debugPrint('[SitePostExtractor] Error resolving stream link: $e');
      return VcloudStreamResult();
    }
  }

  /// Resolve a Batch/Zip landing button to a direct `.zip` file download link.
  ///
  /// Handles multiple resolution chains:
  ///   1. Direct vcloud/hubcloud link on the batch page
  ///   2. Nexdrive/FastDL/GDFlix/VGMLink intermediary -> vcloud -> download
  ///   3. Direct download links (e.g. .zip URLs)
  Future<String?> resolveBatchZipDirectLink(String batchZipLandingUrl) async {
    try {
      final lUrl = batchZipLandingUrl.toLowerCase();

      // If the landing URL itself is already a vcloud/hubcloud URL, resolve it directly
      if (lUrl.contains('vcloud') || lUrl.contains('hubcloud')) {
        final result = await resolveVcloudStream(batchZipLandingUrl);
        final dl = result.bestDownloadUrl;
        if (dl != null && dl.isNotEmpty) return dl;
      }

      // If the landing URL is a nexdrive/fastdl/gdflix/vgmlink intermediary,
      // first extract vcloud URL from it, then resolve
      if (lUrl.contains('nexdrive') ||
          lUrl.contains('fastdl') ||
          lUrl.contains('gdflix') ||
          lUrl.contains('vgmlink') ||
          lUrl.contains('filebee')) {
        final vcloud = await _extractVcloudFromLanding(batchZipLandingUrl);
        if (vcloud != null && vcloud.isNotEmpty) {
          final result = await resolveVcloudStream(vcloud,
              referer: batchZipLandingUrl);
          final dl = result.bestDownloadUrl;
          if (dl != null && dl.isNotEmpty) return dl;
        }
        // Also try hubcloud links on the intermediary page
        final hubcloud = await _extractHubcloudFromLanding(batchZipLandingUrl);
        if (hubcloud != null && hubcloud.isNotEmpty) {
          final result = await resolveVcloudStream(hubcloud,
              referer: batchZipLandingUrl);
          final dl = result.bestDownloadUrl;
          if (dl != null && dl.isNotEmpty) return dl;
        }
      }

      // General case: parse the batch page and find download links
      final html = await fetchHtml(batchZipLandingUrl);
      final doc = html_parser.parse(html);

      String? vcloudUrl;
      String? intermediaryUrl;

      for (final a in doc.querySelectorAll('a[href]')) {
        final href = a.attributes['href'] ?? '';
        if (href.isEmpty || href.startsWith('#')) continue;
        final text = a.text.toLowerCase();
        final lh = href.toLowerCase();

        // Skip social/spam links
        if (lh.contains('telegram') ||
            lh.contains('t.me') ||
            lh.contains('facebook') ||
            lh.contains('twitter')) {
          continue;
        }

        // Direct vcloud/hubcloud link
        if (lh.contains('vcloud') || lh.contains('hubcloud') ||
            text.contains('v-cloud') || text.contains('hubcloud')) {
          vcloudUrl ??= href;
        }
        // Intermediary landing page link
        else if (lh.contains('nexdrive') ||
            lh.contains('fastdl') ||
            lh.contains('gdflix') ||
            lh.contains('vgmlink') ||
            lh.contains('filebee')) {
          intermediaryUrl ??= href;
        }
      }

      // Try direct vcloud first
      if (vcloudUrl != null && vcloudUrl.isNotEmpty) {
        final result = await resolveVcloudStream(vcloudUrl,
            referer: batchZipLandingUrl);
        final dl = result.bestDownloadUrl;
        if (dl != null && dl.isNotEmpty) return dl;
      }

      // Fallback: follow intermediary -> extract vcloud -> resolve
      if (intermediaryUrl != null && intermediaryUrl.isNotEmpty) {
        final vcloud = await _extractVcloudFromLanding(intermediaryUrl);
        if (vcloud != null && vcloud.isNotEmpty) {
          final result = await resolveVcloudStream(vcloud,
              referer: intermediaryUrl);
          final dl = result.bestDownloadUrl;
          if (dl != null && dl.isNotEmpty) return dl;
        }
      }
    } catch (e) {
      debugPrint('[SitePostExtractor] Error resolving Batch/Zip link: $e');
    }
    return null;
  }

  /// Helper to extract first hubcloud anchor from a landing page
  Future<String?> _extractHubcloudFromLanding(String landingUrl) async {
    try {
      final html = await fetchHtml(landingUrl);
      final doc = html_parser.parse(html);
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = a.attributes['href'] ?? '';
        if (href.toLowerCase().contains('hubcloud')) {
          return href;
        }
      }
    } catch (e) {
      debugPrint('[SitePostExtractor] _extractHubcloudFromLanding error: $e');
    }
    return null;
  }
}
