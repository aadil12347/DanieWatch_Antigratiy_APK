/// Source provider abstraction and provider registry.
///
/// Central orchestrator for all extraction sources. Runs all providers
/// concurrently and streams results via callbacks.
///
/// Ported from CSX's CineStreamExtractors.kt provider registry pattern.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'models.dart';
import '../vcloud_extractor.dart';
import '../vidnest_extractor.dart';
import '../peachify_extractor.dart';
import 'gdflix_extractor.dart';
import 'driveleech_extractor.dart';
import 'vegamovies_scraper.dart';
import 'extraction_utils.dart';
import 'manifest_stream_provider.dart';
import 'site_post_extractor.dart';
import 'movie_site_scraper_service.dart';

// ─── Source Provider Base ──────────────────────────────────────────────────

/// Base class for all extraction source providers.
abstract class SourceProvider {
  String get name;
  String get key;
  bool get isEnabled => true;

  /// Extract streaming links for a movie.
  Future<List<ExtractorLink>> extractMovie({
    required String tmdbId,
    String? imdbId,
    required String title,
    int? year,
  });

  /// Extract streaming links for a TV episode.
  Future<List<ExtractorLink>> extractEpisode({
    required String tmdbId,
    String? imdbId,
    required String title,
    int? year,
    required int season,
    required int episode,
  });
}

// ─── VCloud DB Provider (PRIMARY) ─────────────────────────────────────────

class VCloudDBProvider extends SourceProvider {
  @override
  String get name => 'VCloud DB';
  @override
  String get key => 'vcloud_db';

  final _extractor = VcloudExtractorService();

  @override
  Future<List<ExtractorLink>> extractMovie({
    required String tmdbId,
    String? imdbId,
    required String title,
    int? year,
  }) async {
    return _extractFromVcloud(tmdbId, title, isMovie: true, year: year);
  }

  @override
  Future<List<ExtractorLink>> extractEpisode({
    required String tmdbId,
    String? imdbId,
    required String title,
    int? year,
    required int season,
    required int episode,
  }) async {
    return _extractFromVcloud(tmdbId, title,
        isMovie: false, season: season, episode: episode, year: year);
  }

  Future<List<ExtractorLink>> _extractFromVcloud(
    String tmdbId,
    String title, {
    required bool isMovie,
    int? year,
    int? season,
    int? episode,
  }) async {
    final links = <ExtractorLink>[];
    final tmdbIdInt = int.tryParse(tmdbId) ?? 0;

    try {
      // Step 1: Get VCloud page URLs from the GitHub database, grouped by resolution
      Map<String, String> resolutionMap = await _extractor.fetchResolutionLinksMap(
        tmdbId: tmdbIdInt,
        mediaType: isMovie ? 'movie' : 'tv',
        title: title,
        season: season,
        episode: episode,
      );

      // Fallback: If GitHub DB has no entries, extract from Vegamovies/Rogmovies detail post
      if (resolutionMap.isEmpty) {
        debugPrint('[VCloudDB] No resolution links found in DB for TMDB: $tmdbId, trying SitePostExtractor...');
        try {
          final postUrl = MovieSiteScraperService.instance.getPostUrl(tmdbIdInt) ??
              await SitePostExtractor.instance.findPostUrl(
                title: title,
                tmdbId: tmdbIdInt,
                year: year,
              );
          if (postUrl != null && postUrl.isNotEmpty) {
            resolutionMap = await SitePostExtractor.instance.getAvailableResolutionsForContent(
              postUrl: postUrl,
              isMovie: isMovie,
              seasonNumber: season,
              episodeNumber: episode,
            );
          }
        } catch (e) {
          debugPrint('[VCloudDB] SitePostExtractor fallback error: $e');
        }
      }

      if (resolutionMap.isEmpty) {
        debugPrint('[VCloudDB] No resolution links found for TMDB: $tmdbId');
        return links;
      }

      // Step 2: Extract direct server URLs from each resolution's VCloud page
      // Prioritize 720p auto -> 480p -> 1080p -> others
      final sortedEntries = resolutionMap.entries.toList()
        ..sort((a, b) {
          int getPri(String r) {
            final lr = r.toLowerCase();
            if (lr.contains('720')) return 0;
            if (lr.contains('480')) return 1;
            if (lr.contains('1080')) return 2;
            return 3;
          }
          return getPri(a.key).compareTo(getPri(b.key));
        });

      for (final entry in sortedEntries) {
        final resolution = entry.key; // e.g. "480p", "720p", "1080p"
        final vcloudUrl = entry.value;

        try {
          final servers = await _extractor.extractVcloud(vcloudUrl);
          
          // Server priority for online playback: Server 2 (FSLv2) > Server 1 (FSL).
          // STRICT RULE: Never play online with 10Gbps (Server 3) links!
          final serverPriority = ['Server 2', 'Server 1'];
          bool addedServer = false;
          for (final serverName in serverPriority) {
            final serverUrl = servers[serverName];
            if (serverUrl == null || serverUrl.isEmpty) continue;

            final quality = getIndexQuality(resolution);
            final tag = serverName == 'Server 2' ? 'FSLv2' : 'FSL';
            links.add(ExtractorLink(
              sourceName: name,
              displayName: '[$name] $resolution ($tag)',
              url: serverUrl,
              quality: quality,
            ));
            addedServer = true;
          }

          // Fallback: If extractVcloud didn't produce a stream, try SitePostExtractor.resolveVcloudStream
          if (!addedServer) {
            final siteRes = await SitePostExtractor.instance.resolveVcloudStream(vcloudUrl);
            if (siteRes.canStreamOnline && siteRes.onlineStreamUrl != null) {
              final quality = getIndexQuality(resolution);
              final tag = siteRes.fslv2Url != null ? 'FSLv2' : 'FSL';
              links.add(ExtractorLink(
                sourceName: name,
                displayName: '[$name] $resolution ($tag)',
                url: siteRes.onlineStreamUrl!,
                quality: quality,
              ));
            }
          }
        } catch (e) {
          debugPrint('[VCloudDB] Error extracting $resolution from $vcloudUrl: $e');
        }
      }
    } catch (e) {
      debugPrint('[VCloudDB] Extraction error: $e');
    }

    return links;
  }
}

// ─── VidNest Provider ─────────────────────────────────────────────────────

class VidNestProvider extends SourceProvider {
  @override
  String get name => 'VidNest';
  @override
  String get key => 'vidnest';

  final _extractor = VidNestExtractorService();

  @override
  Future<List<ExtractorLink>> extractMovie({
    required String tmdbId,
    String? imdbId,
    required String title,
    int? year,
  }) async {
    return _extract(tmdbId, imdbId, title, 'movie');
  }

  @override
  Future<List<ExtractorLink>> extractEpisode({
    required String tmdbId,
    String? imdbId,
    required String title,
    int? year,
    required int season,
    required int episode,
  }) async {
    return _extract(tmdbId, imdbId, title, 'tv',
        season: season, episode: episode);
  }

  Future<List<ExtractorLink>> _extract(
    String tmdbId,
    String? imdbId,
    String title,
    String mediaType, {
    int? season,
    int? episode,
  }) async {
    final links = <ExtractorLink>[];

    try {
      final streams = await _extractor.extractStreams(
        tmdbId: int.tryParse(tmdbId) ?? 0,
        mediaType: mediaType,
        season: season ?? 1,
        episode: episode ?? 1,
      );

      for (final stream in streams) {
        final url = stream.url;
        if (url.isEmpty) continue;

        links.add(ExtractorLink(
          sourceName: name,
          displayName: '[$name] ${stream.providerName} ${stream.quality != null ? '${stream.quality}p' : ''}',
          url: url,
          type: stream.type.contains('m3u8') || stream.type.contains('hls')
              ? LinkType.m3u8
              : LinkType.infer,
          quality: stream.quality ?? 0,
          headers: stream.headers,
        ));
      }
    } catch (e) {
      debugPrint('[VidNest] Extraction error: $e');
    }

    return links;
  }
}

// ─── Peachify Provider ────────────────────────────────────────────────────

class PeachifyProvider extends SourceProvider {
  @override
  String get name => 'Peachify';
  @override
  String get key => 'peachify';

  final _extractor = PeachifyExtractorService();

  @override
  Future<List<ExtractorLink>> extractMovie({
    required String tmdbId,
    String? imdbId,
    required String title,
    int? year,
  }) async {
    return _extract(tmdbId, imdbId, 'movie');
  }

  @override
  Future<List<ExtractorLink>> extractEpisode({
    required String tmdbId,
    String? imdbId,
    required String title,
    int? year,
    required int season,
    required int episode,
  }) async {
    return _extract(tmdbId, imdbId, 'tv',
        season: season, episode: episode);
  }

  Future<List<ExtractorLink>> _extract(
    String tmdbId,
    String? imdbId,
    String mediaType, {
    int? season,
    int? episode,
  }) async {
    final links = <ExtractorLink>[];

    try {
      final streams = await _extractor.extractStreams(
        tmdbId: int.tryParse(tmdbId) ?? 0,
        mediaType: mediaType,
        season: season ?? 1,
        episode: episode ?? 1,
      );

      for (final stream in streams) {
        final url = stream.url;
        if (url.isEmpty) continue;

        links.add(ExtractorLink(
          sourceName: name,
          displayName: '[$name] ${stream.providerName} ${stream.quality != null ? '${stream.quality}p' : ''}',
          url: url,
          type: stream.type.contains('m3u8') || stream.type.contains('hls')
              ? LinkType.m3u8
              : LinkType.infer,
          quality: stream.quality ?? 0,
          headers: stream.headers,
        ));
      }
    } catch (e) {
      debugPrint('[Peachify] Extraction error: $e');
    }

    return links;
  }
}

// ─── VegaMovies Scraper Provider ──────────────────────────────────────────

class VegaMoviesProvider extends SourceProvider {
  @override
  String get name => 'VegaMovies';
  @override
  String get key => 'vegamovies';

  @override
  Future<List<ExtractorLink>> extractMovie({
    required String tmdbId,
    String? imdbId,
    required String title,
    int? year,
  }) async {
    return VegaMoviesScraper.extractMovie(
      title: title,
      year: year,
      imdbId: imdbId,
    );
  }

  @override
  Future<List<ExtractorLink>> extractEpisode({
    required String tmdbId,
    String? imdbId,
    required String title,
    int? year,
    required int season,
    required int episode,
  }) async {
    return VegaMoviesScraper.extractEpisode(
      title: title,
      year: year,
      season: season,
      episode: episode,
      imdbId: imdbId,
    );
  }
}

// ─── Manifest Iframe Provider ─────────────────────────────────────────────

class ManifestIframeProvider extends SourceProvider {
  @override
  String get name => 'Manifest';
  @override
  String get key => 'manifest_iframe';

  @override
  Future<List<ExtractorLink>> extractMovie({
    required String tmdbId,
    String? imdbId,
    required String title,
    int? year,
  }) async {
    return ManifestStreamProvider.extractMovie(
      tmdbId: int.tryParse(tmdbId) ?? 0,
      title: title,
    );
  }

  @override
  Future<List<ExtractorLink>> extractEpisode({
    required String tmdbId,
    String? imdbId,
    required String title,
    int? year,
    required int season,
    required int episode,
  }) async {
    return ManifestStreamProvider.extractEpisode(
      tmdbId: int.tryParse(tmdbId) ?? 0,
      title: title,
      season: season,
      episode: episode,
    );
  }
}

// ─── GDFlix Provider ──────────────────────────────────────────────────────

class GDFlixProvider extends SourceProvider {
  @override
  String get name => 'GDFlix';
  @override
  String get key => 'gdflix';

  @override
  Future<List<ExtractorLink>> extractMovie({
    required String tmdbId,
    String? imdbId,
    required String title,
    int? year,
  }) async {
    // GDFlix needs a direct URL — it's typically used as a secondary
    // extractor when VegaMovies/RogMovies provide GDFlix links.
    // For direct extraction, we'd need a GDFlix search which isn't available.
    return [];
  }

  @override
  Future<List<ExtractorLink>> extractEpisode({
    required String tmdbId,
    String? imdbId,
    required String title,
    int? year,
    required int season,
    required int episode,
  }) async {
    return [];
  }

  /// Extract from a specific GDFlix URL (called by other providers).
  static Future<List<ExtractorLink>> extractFromUrl(String url) async {
    return GDFlixExtractor.extract(url);
  }
}

// ─── Provider Registry ────────────────────────────────────────────────────

class ProviderRegistry {
  static final ProviderRegistry _instance = ProviderRegistry._internal();
  factory ProviderRegistry() => _instance;
  ProviderRegistry._internal();

  /// All registered providers in priority order.
  /// GitHub database (VCloud DB) is PRIMARY and runs first.
  /// VidNest and Peachify are disabled for now — kept as fallback code.
  final List<SourceProvider> _providers = [
    VCloudDBProvider(),       // PRIMARY — GitHub database JSON
    ManifestIframeProvider(), // Manifest iframe WebView extraction
    VegaMoviesProvider(),     // Live scraper
    // VidNestProvider(),     // DISABLED — fallback for later
    // PeachifyProvider(),    // DISABLED — fallback for later
  ];

  List<SourceProvider> get providers => List.unmodifiable(_providers);

  /// Extract from ALL providers concurrently.
  ///
  /// Results stream via [onLinkFound] callback as each provider resolves.
  /// First valid link can be used to auto-start playback.
  /// [onProviderStatus] reports each provider's progress.
  Future<List<ExtractorLink>> extractAll({
    required String tmdbId,
    String? imdbId,
    required String title,
    required String mediaType,
    int? year,
    int? season,
    int? episode,
    Function(ExtractorLink)? onLinkFound,
    Function(String providerName, ProviderStatus status)? onProviderStatus,
  }) async {
    final allLinks = <ExtractorLink>[];

    final futures = <Future<void>>[];

    for (final provider in _providers) {
      if (!provider.isEnabled) continue;

      final future = _runProvider(
        provider: provider,
        tmdbId: tmdbId,
        imdbId: imdbId,
        title: title,
        mediaType: mediaType,
        year: year,
        season: season,
        episode: episode,
        onLinkFound: (link) {
          allLinks.add(link);
          onLinkFound?.call(link);
        },
        onStatusChanged: (status) {
          onProviderStatus?.call(provider.name, status);
        },
      );

      futures.add(future);
    }

    // Wait for all providers to complete
    await Future.wait(futures);

    debugPrint(
        '[ProviderRegistry] All providers complete. Total links: ${allLinks.length}');
    return allLinks;
  }

  /// Run a single provider with error handling.
  Future<void> _runProvider({
    required SourceProvider provider,
    required String tmdbId,
    String? imdbId,
    required String title,
    required String mediaType,
    int? year,
    int? season,
    int? episode,
    required Function(ExtractorLink) onLinkFound,
    required Function(ProviderStatus) onStatusChanged,
  }) async {
    try {
      onStatusChanged(ProviderStatus.loading);
      debugPrint('[ProviderRegistry] Starting ${provider.name}...');

      List<ExtractorLink> links;
      if (mediaType == 'movie') {
        links = await provider.extractMovie(
          tmdbId: tmdbId,
          imdbId: imdbId,
          title: title,
          year: year,
        );
      } else {
        links = await provider.extractEpisode(
          tmdbId: tmdbId,
          imdbId: imdbId,
          title: title,
          year: year,
          season: season ?? 1,
          episode: episode ?? 1,
        );
      }

      // Process any VCloud/HubCloud/GDFlix URLs found by scrapers
      final resolvedLinks = <ExtractorLink>[];
      for (final link in links) {
        final url = link.url.toLowerCase();
        if (url.contains('gdflix') || url.contains('gdlink')) {
          // Resolve through GDFlix extractor
          try {
            final gdflixLinks = await GDFlixExtractor.extract(link.url);
            resolvedLinks.addAll(gdflixLinks);
          } catch (e) {
            resolvedLinks.add(link);
          }
        } else if (url.contains('driveleech') || url.contains('driveseed')) {
          // Resolve through Driveleech extractor
          try {
            final dlLinks = await DriveleechExtractor.extract(link.url);
            resolvedLinks.addAll(dlLinks);
          } catch (e) {
            resolvedLinks.add(link);
          }
        } else {
          resolvedLinks.add(link);
        }
      }

      for (final link in resolvedLinks) {
        onLinkFound(link);
      }

      onStatusChanged(resolvedLinks.isEmpty
          ? ProviderStatus.empty
          : ProviderStatus.done);
      debugPrint(
          '[ProviderRegistry] ${provider.name} complete: ${resolvedLinks.length} links');
    } catch (e) {
      debugPrint('[ProviderRegistry] ${provider.name} failed: $e');
      onStatusChanged(ProviderStatus.error);
    }
  }
}

/// Status of a provider during extraction.
enum ProviderStatus {
  idle,
  loading,
  done,
  empty,
  error,
}
