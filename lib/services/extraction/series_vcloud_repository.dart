import 'dart:async';
import 'package:flutter/foundation.dart';
import 'site_post_extractor.dart';

/// Represents a single episode of a TV series with all its discovered V-Cloud links
/// across multiple qualities (480p, 720p, 1080p, 2160p/4K).
class SeriesVcloudEpisode {
  final int seasonNumber;
  final int episodeNumber;
  final String title;
  String? thumbnailUrl;

  /// Map of quality -> V-Cloud URL
  /// e.g. {'480p': 'https://vcloud.fit/...', '720p': 'https://vcloud.fit/...', '1080p': 'https://vcloud.fit/...'}
  final Map<String, String> vcloudUrls;

  /// Alternative fallback URLs (e.g. FastDL mirrors if V-Cloud is unreachable)
  final Map<String, List<String>> alternativeUrls;

  /// Exact file sizes per quality (e.g. {'720p': '477.72 MB', '1080p': '1.1 GB'})
  final Map<String, String> exactSizes;

  /// Cached direct stream results resolved on-demand when user plays or downloads
  final Map<String, VcloudStreamResult> resolvedStreams;

  SeriesVcloudEpisode({
    required this.seasonNumber,
    required this.episodeNumber,
    required this.title,
    this.thumbnailUrl,
    Map<String, String>? vcloudUrls,
    Map<String, List<String>>? alternativeUrls,
    Map<String, String>? exactSizes,
    Map<String, VcloudStreamResult>? resolvedStreams,
  })  : vcloudUrls = vcloudUrls ?? {},
        alternativeUrls = alternativeUrls ?? {},
        exactSizes = exactSizes ?? {},
        resolvedStreams = resolvedStreams ?? {};

  /// Returns the primary V-Cloud URL for a quality, or null.
  String? getVcloudUrl(String quality) => vcloudUrls[quality.toLowerCase()];

  /// Check if any V-Cloud URL exists for this episode.
  bool get hasAnyVcloudUrl => vcloudUrls.isNotEmpty;

  /// Preferred default quality: 720p > 480p > 1080p > any available
  String? get bestQuality {
    if (vcloudUrls.containsKey('720p')) return '720p';
    if (vcloudUrls.containsKey('480p')) return '480p';
    if (vcloudUrls.containsKey('1080p')) return '1080p';
    return vcloudUrls.keys.firstOrNull;
  }

  /// Convert this V-Cloud episode to a NextdriveEpisode model for UI consumption
  NextdriveEpisode toNextdriveEpisode({String defaultQuality = '720p'}) {
    final primaryQuality = vcloudUrls.containsKey(defaultQuality.toLowerCase())
        ? defaultQuality.toLowerCase()
        : (bestQuality ?? '720p');
    final primaryUrl = vcloudUrls[primaryQuality] ?? (vcloudUrls.values.firstOrNull ?? '');
    return NextdriveEpisode(
      index: episodeNumber,
      title: title,
      episodeNumber: episodeNumber,
      vcloudUrl: primaryUrl,
      alternativeUrls: alternativeUrls[primaryQuality] ?? [],
      thumbnailUrl: thumbnailUrl,
      exactSize: exactSizes[primaryQuality],
      preResolvedStream: resolvedStreams[primaryQuality],
      otherResolutions: Map<String, String>.from(vcloudUrls),
      otherResolutionSizes: Map<String, String>.from(exactSizes),
    );
  }

  @override
  String toString() =>
      'SeriesVcloudEpisode(S$seasonNumber E$episodeNumber, "$title", qualities: ${vcloudUrls.keys.toList()})';
}

/// In-memory repository that manages all discovered seasons and episodes V-Cloud links
/// across all post button types (G-Direct, Instant, V-Cloud, Episode Links, Download Now, etc.).
class SeriesVcloudRepository {
  static final SeriesVcloudRepository instance = SeriesVcloudRepository._internal();
  SeriesVcloudRepository._internal();

  /// Cache: postUrl/tmdbId -> Map<int seasonNumber, Map<int episodeNumber, SeriesVcloudEpisode>>
  final Map<String, Map<int, Map<int, SeriesVcloudEpisode>>> _seriesCache = {};

  /// Tracks ongoing background crawling tasks to prevent duplicate network calls
  final Set<String> _crawlingPosts = {};

  /// Stream controller to notify UI when new seasons or qualities finish crawling
  final StreamController<String> _updatesController = StreamController<String>.broadcast();
  Stream<String> get updatesStream => _updatesController.stream;

  /// Check whether a season has any extracted episodes in memory
  bool hasSeason(String postKey, int seasonNumber) {
    final epMap = _seriesCache[postKey]?[seasonNumber];
    return epMap != null && epMap.isNotEmpty;
  }

  /// Get all episodes for a specific season, sorted by episode number
  List<SeriesVcloudEpisode> getEpisodesForSeason(String postKey, int seasonNumber) {
    final seasonsMap = _seriesCache[postKey];
    if (seasonsMap == null) return [];
    final epMap = seasonsMap[seasonNumber];
    if (epMap == null) return [];
    final sortedEps = epMap.values.toList()
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    return sortedEps;
  }

  /// Get a specific episode by season and episode number
  SeriesVcloudEpisode? getEpisode(String postKey, int seasonNumber, int episodeNumber) {
    return _seriesCache[postKey]?[seasonNumber]?[episodeNumber];
  }

  /// Check if a URL is a V-Cloud / HubCloud link (domain-agnostic: matches any TLD)
  /// Checks for 'vcloud', 'v-cloud', or 'hubcloud' in the URL, ignoring changing TLDs (.fit, .lol, .zip, etc.)
  static bool isVcloudLink(String url) {
    if (url.isEmpty) return false;
    final l = url.toLowerCase();
    // Exclude social media or ad links
    if (l.contains('telegram') ||
        l.contains('t.me') ||
        l.contains('facebook') ||
        l.contains('twitter') ||
        l.contains('.fans') ||
        l.contains('whatsapp')) {
      return false;
    }
    return l.contains('vcloud') || l.contains('v-cloud') || l.contains('hubcloud');
  }

  /// Store an extracted episode link for a given quality
  void storeEpisodeLink({
    required String postKey,
    required int seasonNumber,
    required int episodeNumber,
    required String title,
    required String quality,
    required String vcloudUrl,
    List<String>? alternativeUrls,
    String? thumbnailUrl,
  }) {
    final q = quality.toLowerCase().trim();
    final seasons = _seriesCache.putIfAbsent(postKey, () => {});
    final episodes = seasons.putIfAbsent(seasonNumber, () => {});

    var ep = episodes[episodeNumber];
    if (ep == null) {
      ep = SeriesVcloudEpisode(
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        title: title,
        thumbnailUrl: thumbnailUrl,
      );
      episodes[episodeNumber] = ep;
    }

    final isNewVcloud = isVcloudLink(vcloudUrl);
    final existingUrl = ep.vcloudUrls[q];
    final isExistingVcloud = existingUrl != null && isVcloudLink(existingUrl);

    // Prioritize V-Cloud / HubCloud over FastDL / other hosts
    if (existingUrl == null || (isNewVcloud && !isExistingVcloud)) {
      ep.vcloudUrls[q] = vcloudUrl;
      if (existingUrl != null && existingUrl != vcloudUrl) {
        ep.alternativeUrls.putIfAbsent(q, () => []).add(existingUrl);
      }
    } else if (existingUrl != vcloudUrl) {
      ep.alternativeUrls.putIfAbsent(q, () => []).add(vcloudUrl);
    }

    if (alternativeUrls != null) {
      for (final alt in alternativeUrls) {
        if (alt.isNotEmpty &&
            !ep.alternativeUrls.putIfAbsent(q, () => []).contains(alt) &&
            alt != ep.vcloudUrls[q]) {
          ep.alternativeUrls[q]!.add(alt);
        }
      }
    }

    if (thumbnailUrl != null && (ep.thumbnailUrl == null || ep.thumbnailUrl!.isEmpty)) {
      ep.thumbnailUrl = thumbnailUrl;
    }
  }

  /// Crawls all non-batch buttons on the post detail page and extracts all episodes'
  /// V-Cloud links for all seasons and all qualities (720p, 480p, 1080p, etc.).
  /// Prioritizes [prioritySeason] so the active season displays immediately.
  Future<void> crawlAllSeasonsVcloud({
    required String postUrl,
    int? prioritySeason,
    String? posterUrl,
  }) async {
    if (postUrl.isEmpty) return;
    if (_crawlingPosts.contains(postUrl)) {
      debugPrint('[SeriesVcloudRepository] Already crawling $postUrl');
      return;
    }
    _crawlingPosts.add(postUrl);

    try {
      debugPrint('[SeriesVcloudRepository] Starting universal V-Cloud extraction for $postUrl');
      final extractor = SitePostExtractor.instance;
      final buttons = await extractor.extractPostButtons(postUrl);
      if (buttons.isEmpty) return;

      // Filter: strictly all buttons EXCEPT batch zip archives
      final nonBatchButtons = buttons.where((b) => !b.isBatchZip).toList();
      debugPrint('[SeriesVcloudRepository] Found ${nonBatchButtons.length} non-batch buttons across post');

      // Group buttons by season
      final seasonsMap = <int, List<SitePostButton>>{};
      for (final b in nonBatchButtons) {
        seasonsMap.putIfAbsent(b.seasonNumber, () => []).add(b);
      }

      final allSeasonNums = seasonsMap.keys.toList()..sort();
      final pSeason = prioritySeason ?? (allSeasonNums.isNotEmpty ? allSeasonNums.first : 1);

      // Order seasons: active season first, then remaining seasons
      final orderedSeasons = <int>[pSeason];
      for (final s in allSeasonNums) {
        if (s != pSeason) orderedSeasons.add(s);
      }

      // Process priority season first, then remaining seasons
      for (final sNum in orderedSeasons) {
        final sButtons = seasonsMap[sNum] ?? [];
        if (sButtons.isEmpty) continue;

        // Deduplicate buttons by href to avoid redundant HTTP requests
        final uniqueButtons = <String, SitePostButton>{};
        for (final b in sButtons) {
          if (b.href.isNotEmpty && !uniqueButtons.containsKey(b.href)) {
            uniqueButtons[b.href] = b;
          }
        }

        // Crawl all non-batch buttons for this season in parallel (G-Direct, V-Cloud, Episode Links, etc.)
        await Future.wait(uniqueButtons.values.map((btn) async {
          final q = btn.quality.toLowerCase();
          try {
            // If the button href itself is already a direct V-Cloud / HubCloud link:
            if (isVcloudLink(btn.href)) {
              storeEpisodeLink(
                postKey: postUrl,
                seasonNumber: sNum,
                episodeNumber: 1,
                title: 'Episode 1',
                quality: q,
                vcloudUrl: btn.href,
                thumbnailUrl: posterUrl,
              );
              return;
            }

            // Otherwise, it's a Nextdrive / episode selector page
            final episodes = await extractor.extractNextdriveEpisodes(btn.href);
            debugPrint('[SeriesVcloudRepository] S$sNum [$q] (${btn.text}) -> Extracted ${episodes.length} episodes from ${btn.href}');

            for (final ep in episodes) {
              final epNum = ep.episodeNumber ?? ep.index;
              storeEpisodeLink(
                postKey: postUrl,
                seasonNumber: sNum,
                episodeNumber: epNum,
                title: ep.title,
                quality: q,
                vcloudUrl: ep.vcloudUrl,
                alternativeUrls: ep.alternativeUrls,
                thumbnailUrl: ep.thumbnailUrl ?? posterUrl,
              );
            }
          } catch (e) {
            debugPrint('[SeriesVcloudRepository] Error extracting S$sNum button "${btn.text}": $e');
          }
        }));

        _updatesController.add(postUrl);
        debugPrint('[SeriesVcloudRepository] Season $sNum V-Cloud links stored: '
            '${getEpisodesForSeason(postUrl, sNum).length} episodes');
      }
    } catch (e) {
      debugPrint('[SeriesVcloudRepository] Error in crawlAllSeasonsVcloud: $e');
    } finally {
      _crawlingPosts.remove(postUrl);
    }
  }

  /// Resolve direct stream link on-demand for playback
  Future<String?> resolvePlaybackStream({
    required String postKey,
    required int seasonNumber,
    required int episodeNumber,
    String? preferredQuality,
  }) async {
    final ep = getEpisode(postKey, seasonNumber, episodeNumber);
    if (ep == null || !ep.hasAnyVcloudUrl) return null;

    final quality = (preferredQuality != null && ep.vcloudUrls.containsKey(preferredQuality.toLowerCase()))
        ? preferredQuality.toLowerCase()
        : ep.bestQuality!;

    // Check if already resolved in memory
    final cachedStream = ep.resolvedStreams[quality];
    if (cachedStream?.canStreamOnline == true && cachedStream?.onlineStreamUrl != null) {
      debugPrint('[SeriesVcloudRepository] Returning cached online stream for S$seasonNumber E$episodeNumber [$quality]');
      return cachedStream!.onlineStreamUrl!;
    }

    final vcloudUrl = ep.vcloudUrls[quality]!;
    final alts = ep.alternativeUrls[quality];

    final res = await SitePostExtractor.instance.resolveVcloudStream(
      vcloudUrl,
      alternativeUrls: alts,
    );

    ep.resolvedStreams[quality] = res;
    if (res.fileSize != null && res.fileSize!.isNotEmpty) {
      ep.exactSizes[quality] = res.fileSize!;
    }

    if (res.canStreamOnline && res.onlineStreamUrl != null) {
      return res.onlineStreamUrl!;
    }
    return null;
  }
}
