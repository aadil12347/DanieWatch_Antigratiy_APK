/// VegaMovies scraper — ported from CSX's VegaMoviesProvider.kt.
///
/// Live scraper for vegamovies sites. Searches, parses detail pages,
/// and extracts VCloud/HubCloud download links grouped by quality.
///
/// Reference: CSX/VegaMovies/src/main/kotlin/com/megix/VegaMoviesProvider.kt

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'extraction_utils.dart';
import 'dynamic_urls.dart';
import 'quality_tags.dart';

class VegaMoviesScraper {
  static const String name = 'VegaMovies';
  static const String _sourceKey = 'vegamovies';

  /// Search VegaMovies for a title and return matching page URLs.
  static Future<List<Map<String, String>>> search(String query) async {
    final results = <Map<String, String>>[];

    try {
      final baseUrl = await DynamicUrls()
          .getLatestBaseUrl(_sourceKey, fallback: 'https://vegamovies.mq');
      final searchUrl = '$baseUrl/?s=${Uri.encodeComponent(query)}';

      debugPrint('[VegaMovies] Searching: $searchUrl');

      final response = await http.get(
        Uri.parse(searchUrl),
        headers: defaultHeaders,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return results;

      final html = response.body;

      // Parse article titles and links from search results
      final articleRegex = RegExp(
          r'<article[^>]*>.*?<a\s+href="([^"]+)"[^>]*>\s*<img[^>]*>.*?<h2[^>]*class="blog-title"[^>]*><a[^>]*>([^<]+)</a>',
          caseSensitive: false,
          dotAll: true);

      // Simpler fallback pattern
      final simpleLinkRegex = RegExp(
          r'<h2[^>]*>\s*<a\s+href="([^"]+)"[^>]*title="([^"]*)"',
          caseSensitive: false);

      for (final match in articleRegex.allMatches(html)) {
        results.add({
          'url': match.group(1)!,
          'title': match.group(2)!.trim(),
        });
      }

      if (results.isEmpty) {
        for (final match in simpleLinkRegex.allMatches(html)) {
          results.add({
            'url': match.group(1)!,
            'title': match.group(2)!.trim(),
          });
        }
      }

      debugPrint('[VegaMovies] Found ${results.length} search results');
    } catch (e) {
      debugPrint('[VegaMovies] Search error: $e');
    }

    return results;
  }

  /// Extract download links from a VegaMovies detail page.
  ///
  /// Returns a list of VCloud/HubCloud/GDFlix URLs grouped by quality.
  static Future<List<Map<String, dynamic>>> extractLinksFromPage(
      String pageUrl) async {
    final downloadGroups = <Map<String, dynamic>>[];

    try {
      final response = await http.get(
        Uri.parse(pageUrl),
        headers: defaultHeaders,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return downloadGroups;

      final html = response.body;

      // Parse download sections — each quality group is wrapped in a div/section
      // with heading containing resolution info (e.g., "480p", "720p", "1080p")
      final sections = _parseDownloadSections(html);

      for (final section in sections) {
        downloadGroups.add(section);
      }

      debugPrint(
          '[VegaMovies] Extracted ${downloadGroups.length} quality groups from page');
    } catch (e) {
      debugPrint('[VegaMovies] Page extraction error: $e');
    }

    return downloadGroups;
  }

  /// Extract download links for a specific movie by title and year.
  static Future<List<ExtractorLink>> extractMovie({
    required String title,
    int? year,
    String? imdbId,
  }) async {
    final links = <ExtractorLink>[];

    try {
      final searchQuery = year != null ? '$title $year' : title;
      final results = await search(searchQuery);

      if (results.isEmpty) {
        debugPrint('[VegaMovies] No search results for: $searchQuery');
        return links;
      }

      // Find best match
      final bestMatch = _findBestMatch(results, title, year);
      if (bestMatch == null) {
        debugPrint('[VegaMovies] No good match found for: $title');
        return links;
      }

      debugPrint('[VegaMovies] Best match: ${bestMatch['title']} -> ${bestMatch['url']}');

      // Extract links from the matched page
      final downloadGroups = await extractLinksFromPage(bestMatch['url']!);

      for (final group in downloadGroups) {
        final quality = group['quality'] as int? ?? 0;
        final groupTitle = group['title'] as String? ?? '';
        final groupLinks = group['links'] as List<String>? ?? [];
        final tags = getQualityTags(groupTitle);

        for (final downloadUrl in groupLinks) {
          if (isAdUrl(downloadUrl)) continue;

          links.add(ExtractorLink(
            sourceName: name,
            displayName: '[$name] ${quality > 0 ? '${quality}p' : 'Unknown'} $groupTitle',
            url: downloadUrl,
            quality: quality,
            qualityTags: tags.isNotEmpty ? tags : null,
          ));
        }
      }

      debugPrint('[VegaMovies] Extracted ${links.length} total links');
    } catch (e) {
      debugPrint('[VegaMovies] Movie extraction error: $e');
    }

    return links;
  }

  /// Extract download links for a specific TV episode.
  static Future<List<ExtractorLink>> extractEpisode({
    required String title,
    int? year,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    final links = <ExtractorLink>[];

    try {
      // Search with season info
      final searchQuery = '$title Season $season';
      final results = await search(searchQuery);

      if (results.isEmpty) {
        debugPrint('[VegaMovies] No search results for: $searchQuery');
        return links;
      }

      // Find best match for the season
      final bestMatch = _findBestMatch(results, title, year, season: season);
      if (bestMatch == null) {
        debugPrint('[VegaMovies] No good match found for: $title S$season');
        return links;
      }

      debugPrint(
          '[VegaMovies] Best match: ${bestMatch['title']} -> ${bestMatch['url']}');

      // Extract links from page — for TV shows, links are usually
      // organized by episode or as full season packs
      final downloadGroups = await extractLinksFromPage(bestMatch['url']!);

      // Filter for the specific episode or include season packs
      for (final group in downloadGroups) {
        final quality = group['quality'] as int? ?? 0;
        final groupTitle = group['title'] as String? ?? '';
        final groupLinks = group['links'] as List<String>? ?? [];
        final tags = getQualityTags(groupTitle);

        // Check if this group is for the right episode
        final episodePattern = RegExp(
            'E0?$episode\\b|Episode\\s*0?$episode\\b',
            caseSensitive: false);
        final seasonPackPattern = RegExp(
            'S0?${season}[^E]|Season\\s*0?$season\\b|Complete|Pack|Zip',
            caseSensitive: false);

        final isEpisodeMatch = episodePattern.hasMatch(groupTitle);
        final isSeasonPack = seasonPackPattern.hasMatch(groupTitle);

        if (isEpisodeMatch || isSeasonPack || !groupTitle.contains('E')) {
          for (final downloadUrl in groupLinks) {
            if (isAdUrl(downloadUrl)) continue;

            links.add(ExtractorLink(
              sourceName: name,
              displayName:
                  '[$name] ${quality > 0 ? '${quality}p' : 'Unknown'} $groupTitle',
              url: downloadUrl,
              quality: quality,
              qualityTags: tags.isNotEmpty ? tags : null,
            ));
          }
        }
      }

      debugPrint('[VegaMovies] Extracted ${links.length} episode links');
    } catch (e) {
      debugPrint('[VegaMovies] Episode extraction error: $e');
    }

    return links;
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  /// Parse download sections from page HTML.
  ///
  /// VegaMovies pages typically have download sections structured as:
  /// <h3>480p | HEVC | WEB-DL | Hindi</h3>
  /// <p><a href="vcloud_link">Download</a></p>
  static List<Map<String, dynamic>> _parseDownloadSections(String html) {
    final sections = <Map<String, dynamic>>[];

    // Find download heading + links pattern
    // Headings are typically h2, h3, h4 or strong tags with quality info
    final headingRegex = RegExp(
        r'<(?:h[2-5]|strong)[^>]*>(.*?)</(?:h[2-5]|strong)>',
        caseSensitive: false,
        dotAll: true);

    final allHeadings = headingRegex.allMatches(html).toList();

    for (var i = 0; i < allHeadings.length; i++) {
      final heading = allHeadings[i];
      final headingText = _stripHtml(heading.group(1) ?? '');

      // Check if this heading looks like a download quality section
      final quality = getIndexQuality(headingText);
      if (quality <= 0 && !_looksLikeDownloadHeading(headingText)) continue;

      // Find all links between this heading and the next heading
      final startPos = heading.end;
      final endPos =
          i < allHeadings.length - 1 ? allHeadings[i + 1].start : html.length;
      final sectionHtml = html.substring(startPos, endPos);

      // Extract all href links from this section
      final linkRegex = RegExp(
          r'href="(https?://[^"]*(?:vcloud|hubcloud|gdflix|gdlink|driveleech|driveseed|gofile)[^"]*)"',
          caseSensitive: false);
      final downloadLinks = <String>[];
      for (final linkMatch in linkRegex.allMatches(sectionHtml)) {
        final href = linkMatch.group(1)!;
        if (!isAdUrl(href)) {
          downloadLinks.add(href);
        }
      }

      if (downloadLinks.isNotEmpty) {
        sections.add({
          'title': headingText,
          'quality': quality,
          'links': downloadLinks,
        });
      }
    }

    // Fallback: if no structured sections found, grab ALL qualifying links
    if (sections.isEmpty) {
      final allLinks = <String>[];
      final linkRegex = RegExp(
          r'href="(https?://[^"]*(?:vcloud|hubcloud|gdflix|gdlink|driveleech|driveseed|gofile)[^"]*)"',
          caseSensitive: false);
      for (final match in linkRegex.allMatches(html)) {
        final href = match.group(1)!;
        if (!isAdUrl(href)) allLinks.add(href);
      }
      if (allLinks.isNotEmpty) {
        sections.add({
          'title': 'Direct Links',
          'quality': 0,
          'links': allLinks,
        });
      }
    }

    return sections;
  }

  /// Check if heading text looks like a download quality section.
  static bool _looksLikeDownloadHeading(String text) {
    final lower = text.toLowerCase();
    return lower.contains('download') ||
        lower.contains('links') ||
        lower.contains('web-dl') ||
        lower.contains('bluray') ||
        lower.contains('hdrip') ||
        lower.contains('webrip') ||
        lower.contains('hevc') ||
        lower.contains('x264') ||
        lower.contains('x265') ||
        lower.contains('hindi') ||
        lower.contains('english') ||
        lower.contains('dual audio');
  }

  /// Find best matching search result for a title.
  static Map<String, String>? _findBestMatch(
    List<Map<String, String>> results,
    String targetTitle, 
    int? targetYear, {
    int? season,
  }) {
    if (results.isEmpty) return null;

    final normalizedTarget = targetTitle.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');

    Map<String, String>? bestMatch;
    int bestScore = -1;

    for (final result in results) {
      final resultTitle = (result['title'] ?? '').toLowerCase();
      var score = 0;

      // Title word matching
      final targetWords = normalizedTarget.split(RegExp(r'\s+'));
      for (final word in targetWords) {
        if (word.length > 2 && resultTitle.contains(word)) {
          score += 10;
        }
      }

      // Year matching
      if (targetYear != null && resultTitle.contains('$targetYear')) {
        score += 20;
      }

      // Season matching
      if (season != null) {
        if (resultTitle.contains('season $season') ||
            resultTitle.contains('s${season.toString().padLeft(2, '0')}') ||
            resultTitle.contains('s$season')) {
          score += 15;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        bestMatch = result;
      }
    }

    // Require minimum score to avoid false positives
    return bestScore >= 20 ? bestMatch : (results.isNotEmpty ? results.first : null);
  }

  /// Strip HTML tags from string.
  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
