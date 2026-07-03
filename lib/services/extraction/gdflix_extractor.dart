/// GDFlix extractor — ported from CSX's CineStream/Extractors.kt GDFlix class.
///
/// Supports domains: gdflix.*, gdlink.*, new.gdflix.*, new1.gdflix.*
/// Extraction flow:
/// 1. Fetch page → parse file name/size
/// 2. Find download buttons (FastServer, CF Worker, HubCloud, Gofile)
/// 3. Route through each backend to get direct URLs
///
/// Reference: CSX/CineStream/src/main/kotlin/com/megix/Extractors.kt

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'extraction_utils.dart';
import 'dynamic_urls.dart';
import 'quality_tags.dart';
import 'dart:math';

class GDFlixExtractor {
  static const String name = 'GDFlix';

  /// Extract streaming links from a GDFlix page URL.
  ///
  /// Returns a list of [ExtractorLink] from multiple backends
  /// (FastServer, CF Worker, HubCloud, Gofile).
  static Future<List<ExtractorLink>> extract(String url) async {
    final links = <ExtractorLink>[];

    try {
      // Resolve latest base URL in case domain changed
      var baseUrl = getBaseUrl(url);
      final latestBase =
          await DynamicUrls().getLatestBaseUrl('gdflix', fallback: baseUrl);
      var resolvedUrl = url;
      if (baseUrl != latestBase) {
        resolvedUrl = url.replaceFirst(baseUrl, latestBase);
        baseUrl = latestBase;
      }

      debugPrint('[GDFlix] Fetching page: $resolvedUrl');

      final response = await http.get(
        Uri.parse(resolvedUrl),
        headers: defaultHeaders,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('[GDFlix] Page fetch failed: ${response.statusCode}');
        return links;
      }

      final html = response.body;

      // Parse file name and size from list-group-item elements
      final fileNameRegex = RegExp(
          r'<li[^>]*class="list-group-item"[^>]*>.*?Name\s*:\s*(.*?)</li>',
          caseSensitive: false,
          dotAll: true);
      final fileSizeRegex = RegExp(
          r'<li[^>]*class="list-group-item"[^>]*>.*?Size\s*:\s*(.*?)</li>',
          caseSensitive: false,
          dotAll: true);

      final fileName =
          fileNameRegex.firstMatch(html)?.group(1)?.trim() ?? '';
      final fileSize =
          fileSizeRegex.firstMatch(html)?.group(1)?.trim() ?? '';
      final quality = getIndexQuality(fileName);
      final tags = fileName.isNotEmpty ? getQualityTags(fileName) : '';

      // Parse all anchor tags with their attributes
      final anchors = extractAnchorTags(html);

      for (final entry in anchors) {
        final idAndText = entry.key; // "id|innerHtml"
        final href = entry.value;
        final parts = idAndText.split('|');
        final id = parts[0];
        final innerText = parts.length > 1 ? parts[1] : '';

        if (href.isEmpty || href == '#') continue;
        if (isAdUrl(href)) continue;

        // === FastServer (id="fsl") ===
        if (id == 'fsl' ||
            innerText.contains('[FSL Server]') ||
            innerText.contains('FastServer')) {
          final minutes = DateTime.now().minute;
          final directUrl = '$href${href.contains('?') ? '&' : '?'}t=$minutes';

          links.add(ExtractorLink(
            sourceName: name,
            displayName: '[$name] $fileName [FastServer]${fileSize.isNotEmpty ? ' [$fileSize]' : ''}',
            url: directUrl,
            quality: quality,
            qualityTags: tags,
            fileSize: fileSize.isNotEmpty ? fileSize : null,
          ));
        }

        // === CF Worker (id="s3") ===
        else if (id == 's3' || innerText.contains('[FSLv2 Server]')) {
          String directUrl;
          if (href.contains('X-Amz-Signature') ||
              href.contains('r2.cloudflarestorage') ||
              href.contains('r2.dev')) {
            directUrl = href;
          } else {
            final minutes = DateTime.now().minute;
            directUrl = '${href}_1$minutes';
          }

          links.add(ExtractorLink(
            sourceName: name,
            displayName: '[$name] $fileName [CF Worker]${fileSize.isNotEmpty ? ' [$fileSize]' : ''}',
            url: directUrl,
            quality: quality,
            qualityTags: tags,
            fileSize: fileSize.isNotEmpty ? fileSize : null,
          ));
        }

        // === HubCloud / GPDL (10Gbps server) ===
        else if (innerText.contains('[Server : 10Gbps]') ||
            href.contains('hubcloud') ||
            href.contains('gpdl')) {
          if (href.contains('telegram') || href.contains('t.me')) continue;

          // Resolve the HubCloud redirect to get direct link
          try {
            final resolvedLink = await _resolveHubCloudLink(href);
            if (resolvedLink != null) {
              links.add(ExtractorLink(
                sourceName: name,
                displayName: '[$name] $fileName [HubCloud]${fileSize.isNotEmpty ? ' [$fileSize]' : ''}',
                url: resolvedLink,
                quality: quality,
                qualityTags: tags,
                fileSize: fileSize.isNotEmpty ? fileSize : null,
              ));
            }
          } catch (e) {
            debugPrint('[GDFlix] HubCloud resolution failed: $e');
          }
        }

        // === Gofile ===
        else if (href.contains('gofile.io')) {
          try {
            final gofileLinks = await _extractGofile(href, fileName, fileSize);
            links.addAll(gofileLinks);
          } catch (e) {
            debugPrint('[GDFlix] Gofile extraction failed: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[GDFlix] Extraction error: $e');
    }

    debugPrint('[GDFlix] Extracted ${links.length} links');
    return links;
  }

  /// Resolve HubCloud/GPDL redirect chain to get direct link.
  static Future<String?> _resolveHubCloudLink(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..badCertificateCallback = (cert, host, port) => true;

    try {
      // First, fetch the page and look for pxl or double atob
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', kUserAgent);
      final response = await request.close();
      final html = await response.transform(utf8.decoder).join();

      // Try pxl extraction
      final pxlUrl = extractPxlUrl(html);
      if (pxlUrl != null && pxlUrl.isNotEmpty) {
        client.close();
        return pxlUrl;
      }

      // Try double atob
      final atobUrl = extractDoubleAtob(html);
      if (atobUrl != null && atobUrl.isNotEmpty) {
        client.close();
        return await resolveFinalUrl(atobUrl);
      }

      // Fallback: follow redirects and look for ?link= parameter
      var currentUrl = url;
      var redirectCount = 0;
      while (redirectCount < 10) {
        final uri = Uri.parse(currentUrl);
        if (uri.queryParameters.containsKey('link')) {
          client.close();
          return uri.queryParameters['link'];
        }

        final req = await client.getUrl(uri);
        req.headers.set('User-Agent', kUserAgent);
        req.followRedirects = false;
        final resp = await req.close();
        await resp.drain<void>();

        final location = resp.headers.value('location');
        if (location != null && location.isNotEmpty) {
          currentUrl = location.startsWith('http')
              ? location
              : uri.resolve(location).toString();
          redirectCount++;
        } else {
          break;
        }
      }

      // Check final URL for link parameter
      final finalUri = Uri.parse(currentUrl);
      if (finalUri.queryParameters.containsKey('link')) {
        client.close();
        return finalUri.queryParameters['link'];
      }
    } catch (e) {
      debugPrint('[GDFlix] HubCloud redirect error: $e');
    } finally {
      client.close();
    }
    return null;
  }

  /// Extract download links from Gofile.
  ///
  /// Ported from CSX's Gofile extractor class.
  static Future<List<ExtractorLink>> _extractGofile(
      String url, String fileName, String fileSize) async {
    final links = <ExtractorLink>[];
    const mainApi = 'https://api.gofile.io';
    const browserLang = 'en-US';
    const secret = '9844d94d963d30';

    // Extract content ID from URL
    final idRegex = RegExp(r'/(?:\?c=|d/)([\da-zA-Z-]+)');
    final idMatch = idRegex.firstMatch(url);
    if (idMatch == null) return links;
    final contentId = idMatch.group(1)!;

    try {
      // Generate website token for account creation
      final timeSlot = DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ 14400;
      final rawForCreation = '$kUserAgent::$browserLang::::$timeSlot::$secret';
      final tokenForCreation = _simpleHash(rawForCreation);

      // Create anonymous account
      final accountResp = await http.post(
        Uri.parse('$mainApi/accounts'),
        headers: {
          'X-Website-Token': tokenForCreation,
          'X-BL': browserLang,
          'User-Agent': kUserAgent,
        },
      ).timeout(const Duration(seconds: 10));

      if (accountResp.statusCode != 200) return links;
      final accountData = jsonDecode(accountResp.body);
      final token = accountData['data']?['token'] as String?;
      if (token == null) return links;

      // Generate hashed token
      final rawForContent = '$kUserAgent::$browserLang::$token::$timeSlot::$secret';
      final hashedToken = _simpleHash(rawForContent);

      // Fetch content
      final contentResp = await http.get(
        Uri.parse('$mainApi/contents/$contentId?cache=true&sortField=createTime&sortDirection=1'),
        headers: {
          'Authorization': 'Bearer $token',
          'X-Website-Token': hashedToken,
          'X-BL': browserLang,
          'User-Agent': kUserAgent,
          'Referer': 'https://gofile.io/',
        },
      ).timeout(const Duration(seconds: 10));

      if (contentResp.statusCode != 200) return links;
      final contentData = jsonDecode(contentResp.body);
      final children = contentData['data']?['children'] as Map<String, dynamic>?;
      if (children == null) return links;

      for (final entry in children.entries) {
        final file = entry.value as Map<String, dynamic>;
        final link = file['link'] as String?;
        final type = file['type'] as String?;
        if (link == null || link.isEmpty || type != 'file') continue;

        final fName = file['name'] as String? ?? fileName;
        final fSize = file['size'] as int? ?? 0;
        final formattedSize = fSize > 0 ? formatBytes(fSize) : fileSize;

        links.add(ExtractorLink(
          sourceName: 'Gofile',
          displayName: '[Gofile] $fName${formattedSize.isNotEmpty ? ' [$formattedSize]' : ''}',
          url: link,
          quality: getIndexQuality(fName),
          qualityTags: getQualityTags(fName),
          fileSize: formattedSize.isNotEmpty ? formattedSize : null,
          headers: {'Cookie': 'accountToken=$token'},
        ));
      }
    } catch (e) {
      debugPrint('[GDFlix] Gofile extraction error: $e');
    }

    return links;
  }

  /// Simple hash function for Gofile token generation.
  static String _simpleHash(String input) {
    // SHA-256 equivalent using dart:convert
    final bytes = utf8.encode(input);
    var hash = 0x811c9dc5;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
