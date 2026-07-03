/// Driveleech/Driveseed extractor — ported from CSX's Moviesmod/Utils.kt.
///
/// Supports domains: driveleech.*, driveseed.*
/// Extraction patterns:
/// 1. CF Type 1/2: Append ?type=1 or ?type=2 → parse a.btn-success
/// 2. ResumeCloud: Follow resume cloud URL → parse a.btn-success
/// 3. ResumeBot: Extract PHPSESSID + token → POST /download → get direct URL
///
/// Reference: CSX/Moviesmod/src/main/kotlin/com/megix/Utils.kt

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'extraction_utils.dart';
import 'dynamic_urls.dart';
import 'quality_tags.dart';

class DriveleechExtractor {
  static const String name = 'Driveleech';

  /// Extract streaming/download links from a Driveleech or Driveseed URL.
  ///
  /// Tries multiple extraction strategies in order:
  /// 1. CF Type 1 and 2 (fastest)
  /// 2. ResumeCloud links
  /// 3. ResumeBot pattern (most complex)
  static Future<List<ExtractorLink>> extract(String url) async {
    final links = <ExtractorLink>[];

    try {
      // Resolve latest base URL
      final baseUrl = getBaseUrl(url);
      final isDriveseed = url.toLowerCase().contains('driveseed');
      final sourceKey = isDriveseed ? 'driveseed' : 'driveleech';
      final sourceName = isDriveseed ? 'Driveseed' : 'Driveleech';

      final latestBase = await DynamicUrls()
          .getLatestBaseUrl(sourceKey, fallback: baseUrl);
      var resolvedUrl = url;
      if (baseUrl != latestBase) {
        resolvedUrl = url.replaceFirst(baseUrl, latestBase);
      }

      debugPrint('[$sourceName] Starting extraction: $resolvedUrl');

      // Strategy 1: CF Type extraction
      final cfLinks = await _extractCFType(resolvedUrl, sourceName);
      if (cfLinks.isNotEmpty) {
        links.addAll(cfLinks);
        debugPrint('[$sourceName] CF Type found ${cfLinks.length} links');
      }

      // Strategy 2: Direct page parse for ResumeCloud and ResumeBot
      final response = await http.get(
        Uri.parse(resolvedUrl),
        headers: defaultHeaders,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final html = response.body;

        // Look for resume cloud links
        final resumeCloudLinks = _findResumeCloudLinks(html, baseUrl);
        for (final rcUrl in resumeCloudLinks) {
          final rcLinks = await _extractResumeCloud(rcUrl, sourceName);
          links.addAll(rcLinks);
        }

        // Look for resume bot links
        final resumeBotLinks = _findResumeBotLinks(html);
        for (final rbUrl in resumeBotLinks) {
          final rbLinks = await _extractResumeBot(rbUrl, sourceName);
          links.addAll(rbLinks);
        }
      }
    } catch (e) {
      debugPrint('[Driveleech] Extraction error: $e');
    }

    debugPrint('[Driveleech] Extracted ${links.length} total links');
    return links;
  }

  /// CF Type extraction: Append ?type=1 or ?type=2 to URL and parse btn-success links.
  ///
  /// Ported from CSX's `CFType()` method.
  static Future<List<ExtractorLink>> _extractCFType(
      String url, String sourceName) async {
    final links = <ExtractorLink>[];
    final types = ['1', '2'];

    for (final type in types) {
      try {
        final cfUrl = '$url?type=$type';
        debugPrint('[$sourceName] Trying CF Type $type: $cfUrl');

        final response = await http.get(
          Uri.parse(cfUrl),
          headers: defaultHeaders,
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) continue;

        final html = response.body;
        // Extract a.btn-success hrefs
        final btnRegex = RegExp(
            r'<a[^>]*class="[^"]*btn-success[^"]*"[^>]*href="([^"]+)"',
            caseSensitive: false);

        for (final match in btnRegex.allMatches(html)) {
          final href = match.group(1);
          if (href == null || href.isEmpty || href == '#') continue;
          if (isAdUrl(href)) continue;

          final quality = getIndexQuality(href);
          links.add(ExtractorLink(
            sourceName: sourceName,
            displayName: '[$sourceName] CF-Type$type ${quality > 0 ? '${quality}p' : 'Direct'}',
            url: href,
            quality: quality,
            qualityTags: getQualityTags(href),
          ));
        }
      } catch (e) {
        debugPrint('[$sourceName] CF Type $type failed: $e');
      }
    }

    return links;
  }

  /// Find ResumeCloud URLs in page HTML.
  static List<String> _findResumeCloudLinks(String html, String baseUrl) {
    final links = <String>[];
    // Look for links containing "resumecloud" or specific resume patterns
    final regex = RegExp(
        r'href="([^"]*(?:resume|cloud)[^"]*)"',
        caseSensitive: false);
    for (final match in regex.allMatches(html)) {
      var href = match.group(1)!;
      if (href.startsWith('/')) href = '$baseUrl$href';
      if (href.startsWith('http') && !isAdUrl(href)) {
        links.add(href);
      }
    }
    return links;
  }

  /// Extract download link from a ResumeCloud page.
  ///
  /// Ported from CSX's `resumeCloudLink()` method.
  static Future<List<ExtractorLink>> _extractResumeCloud(
      String url, String sourceName) async {
    final links = <ExtractorLink>[];

    try {
      debugPrint('[$sourceName] ResumeCloud: $url');
      final response = await http.get(
        Uri.parse(url),
        headers: defaultHeaders,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return links;

      final html = response.body;
      final btnRegex = RegExp(
          r'<a[^>]*class="[^"]*btn-success[^"]*"[^>]*href="([^"]+)"',
          caseSensitive: false);
      final match = btnRegex.firstMatch(html);
      if (match != null) {
        final href = match.group(1)!;
        if (href.isNotEmpty && href != '#' && !isAdUrl(href)) {
          final quality = getIndexQuality(href);
          links.add(ExtractorLink(
            sourceName: sourceName,
            displayName: '[$sourceName] ResumeCloud ${quality > 0 ? '${quality}p' : 'Direct'}',
            url: href,
            quality: quality,
          ));
        }
      }
    } catch (e) {
      debugPrint('[$sourceName] ResumeCloud error: $e');
    }

    return links;
  }

  /// Find ResumeBot URLs in page HTML.
  static List<String> _findResumeBotLinks(String html) {
    final links = <String>[];
    final regex = RegExp(
        r'href="([^"]*download[^"]*)"',
        caseSensitive: false);
    for (final match in regex.allMatches(html)) {
      final href = match.group(1)!;
      if (href.startsWith('http') && href.contains('/download') && !isAdUrl(href)) {
        links.add(href);
      }
    }
    return links;
  }

  /// Extract download link using the ResumeBot pattern.
  ///
  /// Ported from CSX's `resumeBot()` method:
  /// 1. GET the page → extract PHPSESSID cookie
  /// 2. Parse formData.append('token', '...') from HTML
  /// 3. Parse fetch('/download?id=...') path from HTML
  /// 4. POST to download endpoint with token + PHPSESSID
  /// 5. Parse JSON response for direct URL
  static Future<List<ExtractorLink>> _extractResumeBot(
      String url, String sourceName) async {
    final links = <ExtractorLink>[];

    try {
      debugPrint('[$sourceName] ResumeBot: $url');

      // Step 1: GET the page, capture PHPSESSID cookie
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        ..badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', kUserAgent);
      final response = await request.close();
      final html = await response.transform(utf8.decoder).join();

      // Extract PHPSESSID from Set-Cookie header
      String? phpSessionId;
      response.headers.forEach((name, values) {
        if (name.toLowerCase() == 'set-cookie') {
          for (final value in values) {
            final match = RegExp(r'PHPSESSID=([^;]+)').firstMatch(value);
            if (match != null) {
              phpSessionId = match.group(1);
            }
          }
        }
      });

      if (phpSessionId == null) {
        client.close();
        return links;
      }

      // Step 2: Extract token from formData.append('token', '...')
      final tokenRegex =
          RegExp(r"""formData\.append\('token',\s*'([a-f0-9]+)'\)""");
      final tokenMatch = tokenRegex.firstMatch(html);
      if (tokenMatch == null) {
        client.close();
        return links;
      }
      final token = tokenMatch.group(1)!;

      // Step 3: Extract download path from fetch('/download?id=...')
      final pathRegex =
          RegExp(r"""fetch\('/download\?id=([a-zA-Z0-9/+]+)'""");
      final pathMatch = pathRegex.firstMatch(html);
      if (pathMatch == null) {
        client.close();
        return links;
      }
      final downloadPath = pathMatch.group(1)!;

      // Step 4: POST to download endpoint
      final resumeBotBaseUrl = url.split('/download')[0];
      final downloadUrl = '$resumeBotBaseUrl/download?id=$downloadPath';

      final postRequest = await client.postUrl(Uri.parse(downloadUrl));
      postRequest.headers.set('User-Agent', kUserAgent);
      postRequest.headers.set('Accept', '*/*');
      postRequest.headers.set('Origin', resumeBotBaseUrl);
      postRequest.headers.set('Referer', url);
      postRequest.headers.set('Sec-Fetch-Site', 'same-origin');
      postRequest.headers.set('Cookie', 'PHPSESSID=$phpSessionId');
      postRequest.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded');
      postRequest.write('token=$token');

      final postResponse = await postRequest.close();
      final responseBody = await postResponse.transform(utf8.decoder).join();
      client.close();

      // Step 5: Parse JSON response
      try {
        final jsonData = jsonDecode(responseBody) as Map<String, dynamic>;
        final directUrl = jsonData['url'] as String?;
        if (directUrl != null && directUrl.isNotEmpty) {
          final quality = getIndexQuality(directUrl);
          links.add(ExtractorLink(
            sourceName: sourceName,
            displayName: '[$sourceName] ResumeBot ${quality > 0 ? '${quality}p' : 'Direct'}',
            url: directUrl,
            quality: quality,
          ));
        }
      } catch (e) {
        debugPrint('[$sourceName] ResumeBot JSON parse error: $e');
      }
    } catch (e) {
      debugPrint('[$sourceName] ResumeBot error: $e');
    }

    return links;
  }
}

/// Driveseed extractor — same logic as Driveleech, different domain.
class DriveseedExtractor {
  static Future<List<ExtractorLink>> extract(String url) async {
    return DriveleechExtractor.extract(url);
  }
}
