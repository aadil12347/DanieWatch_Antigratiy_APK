/// Manifest Stream Provider — resolves iframe embed URLs from the local manifest database.
///
/// The local index.json / streaming JSON contains items with `watch` fields that hold
/// iframe embed URLs (e.g., bysebuho.com). This provider:
/// 1. Looks up the item in the local manifest by tmdbId
/// 2. Extracts the iframe embed URL for the correct movie/episode
/// 3. Runs it through VideoExtractorService (headless WebView) to get a playable m3u8/mp4
/// 4. Returns ExtractorLink results

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'iframe_parser.dart';
import '../video_extractor_service.dart';
import '../vcloud_extractor.dart';

class ManifestStreamProvider {
  static const String name = 'Manifest';

  /// Extract streaming links for a movie from the manifest JSON.
  static Future<List<ExtractorLink>> extractMovie({
    required int tmdbId,
    required String title,
  }) async {
    final links = <ExtractorLink>[];

    try {
      final embedUrl = await _getEmbedUrl(
        tmdbId: tmdbId,
        mediaType: 'movie',
        title: title,
      );

      if (embedUrl == null) {
        debugPrint('[ManifestStream] No embed URL found for movie tmdbId: $tmdbId');
        return links;
      }

      debugPrint('[ManifestStream] Found embed URL for movie: $embedUrl');
      final resolvedUrl = await _resolveEmbedUrl(embedUrl);
      if (resolvedUrl != null) {
        links.add(ExtractorLink(
          sourceName: name,
          displayName: '[$name] HD Stream',
          url: resolvedUrl,
          type: resolvedUrl.contains('.m3u8') ? LinkType.m3u8 : LinkType.infer,
          quality: 720,
        ));
      }
    } catch (e) {
      debugPrint('[ManifestStream] Movie extraction error: $e');
    }

    return links;
  }

  /// Extract streaming links for a TV episode from the manifest JSON.
  static Future<List<ExtractorLink>> extractEpisode({
    required int tmdbId,
    required String title,
    required int season,
    required int episode,
  }) async {
    final links = <ExtractorLink>[];

    try {
      final embedUrl = await _getEmbedUrl(
        tmdbId: tmdbId,
        mediaType: 'tv',
        title: title,
        season: season,
        episode: episode,
      );

      if (embedUrl == null) {
        debugPrint('[ManifestStream] No embed URL found for S${season}E$episode of tmdbId: $tmdbId');
        return links;
      }

      debugPrint('[ManifestStream] Found embed URL for S${season}E$episode: $embedUrl');
      final resolvedUrl = await _resolveEmbedUrl(embedUrl);
      if (resolvedUrl != null) {
        links.add(ExtractorLink(
          sourceName: name,
          displayName: '[$name] S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}',
          url: resolvedUrl,
          type: resolvedUrl.contains('.m3u8') ? LinkType.m3u8 : LinkType.infer,
          quality: 720,
        ));
      }
    } catch (e) {
      debugPrint('[ManifestStream] Episode extraction error: $e');
    }

    return links;
  }

  /// Look up the embed URL from the streaming JSON or local manifest.
  static Future<String?> _getEmbedUrl({
    required int tmdbId,
    required String mediaType,
    required String title,
    int? season,
    int? episode,
  }) async {
    // Strategy 1: Try the VCloud streaming JSON (which may contain iframe watch fields)
    try {
      final jsonUrl = await VcloudExtractorService().getStreamJsonUrl(
        tmdbId: tmdbId,
        mediaType: mediaType,
        title: title,
        season: season,
      );

      if (jsonUrl != null) {
        final response = await http.get(Uri.parse(jsonUrl)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;

          if (mediaType == 'movie') {
            // Check for iframe in the movie watch field
            final movieEmbed = IframeParser.extractMovieEmbedUrl(data);
            if (movieEmbed != null) return movieEmbed;

            // Also check top-level 'watch' field
            final topWatch = IframeParser.extractEmbedUrl(data['watch']?.toString());
            if (topWatch != null) return topWatch;
          } else {
            // TV episode
            if (season != null && episode != null) {
              final episodeEmbed = IframeParser.extractEpisodeEmbedUrl(
                data,
                season: season,
                episode: episode,
              );
              if (episodeEmbed != null) return episodeEmbed;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ManifestStream] Error checking streaming JSON for iframe: $e');
    }

    // Strategy 2: No additional inline watch fields in ManifestItem model.
    // All watch URLs come from the streaming JSON (Strategy 1 above).

    return null;
  }

  /// Resolve an embed URL to a playable streaming URL using WebView extraction.
  static Future<String?> _resolveEmbedUrl(String embedUrl) async {
    try {
      debugPrint('[ManifestStream] Resolving embed URL via WebView: $embedUrl');
      final result = await VideoExtractorService().extractVideoUrl(embedUrl);
      if (result != null && result.isNotEmpty) {
        debugPrint('[ManifestStream] Resolved to: $result');
        return result;
      }
    } catch (e) {
      debugPrint('[ManifestStream] WebView extraction error: $e');
    }
    return null;
  }
}
