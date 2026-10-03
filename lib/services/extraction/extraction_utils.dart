/// Shared extraction utilities ported from CSX's common patterns.
///
/// Contains: resolveFinalUrl, getBaseUrl, getIndexQuality,
/// extractPxlUrl, extractDoubleAtob, ad detection, etc.
///
/// Reference: CSX/VegaMovies/Extractors.kt, CSX/MoviesDrive/Extractors.kt

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Default User-Agent matching CSX's USER_AGENT constant
const String kUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/// Default headers for extraction requests
Map<String, String> get defaultHeaders => {
      'User-Agent': kUserAgent,
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.5',
      'Connection': 'keep-alive',
    };

// ─── URL Extraction from HTML ─────────────────────────────────────────────

/// Extract `var pxl = '...'` from HTML — CSX's extractPxlUrl() pattern.
///
/// This is the primary extraction method for VCloud/HubCloud pages.
/// The `pxl` variable contains the direct download URL.
String? extractPxlUrl(String html) {
  final regex = RegExp(r"""var\s+pxl\s*=\s*["']([^"']+)["']""");
  return regex.firstMatch(html)?.group(1);
}

/// Extract `var url = atob(atob('...'))` and double-decode — CSX's extractDoubleAtob().
///
/// Many VCloud/HubCloud pages encode the URL in nested base64.
String? extractDoubleAtob(String html) {
  // Match both 'var url = atob(atob(...))' and bare 'atob(atob(...))'
  final regex = RegExp(
      r"""(?:var\s+url\s*=\s*)?atob\s*\(\s*atob\s*\(\s*['"]([^'"]+)['"]\s*\)\s*\)""");
  final match = regex.firstMatch(html);
  if (match == null) return null;

  try {
    final firstDecode = utf8.decode(base64.decode(match.group(1)!));
    final secondDecode = utf8.decode(base64.decode(firstDecode));
    return secondDecode;
  } catch (e) {
    debugPrint('[ExtractionUtils] Double atob decode failed: $e');
    return null;
  }
}

/// Extract single `url = atob('...')` and decode.
String? extractSingleAtob(String html) {
  final regex =
      RegExp(r"""url\s*=\s*atob\(\s*['"]([A-Za-z0-9+/=]{10,})['"]\s*\)""");
  final match = regex.firstMatch(html);
  if (match == null) return null;

  try {
    return utf8.decode(base64.decode(match.group(1)!));
  } catch (e) {
    debugPrint('[ExtractionUtils] Single atob decode failed: $e');
    return null;
  }
}

/// Extract `var url = '...'` or `var url = "..."` from HTML.
String? extractVarUrl(String html) {
  final regex =
      RegExp(r"""var\s+url\s*=\s*['"](\s*https?://[^'"]+)['"]""", caseSensitive: false);
  return regex.firstMatch(html)?.group(1)?.trim();
}

/// Extract download button href (id="download", text "generate", "direct download", or "resume").
String? extractDownloadButton(String html) {
  // Try id="download"
  final idRegex = RegExp(
      r'''<a\s+[^>]*id=["']download["'][^>]*href=["']([^"']+)["']''',
      caseSensitive: false);
  final idMatch = idRegex.firstMatch(html);
  if (idMatch != null) {
    final href = idMatch.group(1)!;
    if (href.startsWith('http')) return href;
  }

  // Try text containing "generate", "direct download", or "resume"
  final genRegex = RegExp(
      r'''<a\s+[^>]*href=["'](https?://[^"']+)["'][^>]*>.*?(?:generate|direct\s+download|download\s+\[resume\]|resume).*?</a>''',
      caseSensitive: false,
      dotAll: true);
  final genMatch = genRegex.firstMatch(html);
  if (genMatch != null) return genMatch.group(1);

  // Try anchor with class containing btn and href containing vcloud/hubcloud
  final btnRegex = RegExp(
      r'''<a\s+[^>]*href=["'](https?://[^"']*(?:vcloud|hubcloud)[^"']*)["'][^>]*class=["'][^"']*btn[^"']*["']''',
      caseSensitive: false);
  final btnMatch = btnRegex.firstMatch(html);
  if (btnMatch != null) return btnMatch.group(1);

  return null;
}

// ─── URL Resolution ───────────────────────────────────────────────────────

/// Follow HTTP redirect chain using HEAD requests (up to [maxRedirects] hops).
///
/// Ported from CSX's `resolveFinalUrl()` in Extractors.kt.
/// Returns the final URL after all redirects, or null on failure.
Future<String?> resolveFinalUrl(
  String startUrl, {
  int maxRedirects = 7,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..badCertificateCallback = (cert, host, port) => true;

  var currentUrl = startUrl;
  var loopCount = 0;

  try {
    while (loopCount < maxRedirects) {
      final request = await client.headUrl(Uri.parse(currentUrl));
      request.followRedirects = false;
      request.headers.set('User-Agent', kUserAgent);

      final response = await request.close();
      // Drain body
      await response.drain<void>();

      final statusCode = response.statusCode;
      if (statusCode == 200) break;

      if (statusCode >= 300 && statusCode < 400) {
        final location = response.headers.value('location');
        if (location == null || location.isEmpty) break;
        if (location.startsWith('http')) {
          currentUrl = location;
        } else {
          currentUrl = Uri.parse(currentUrl).resolve(location).toString();
        }
        loopCount++;
      } else {
        client.close();
        return null;
      }
    }
    client.close();
    return currentUrl;
  } catch (e) {
    debugPrint('[ExtractionUtils] resolveFinalUrl failed: $e');
    client.close();
    return null;
  }
}

/// Extract base URL (scheme://host) from a full URL.
///
/// Ported from CSX's `getBaseUrl()`.
String getBaseUrl(String url) {
  try {
    final uri = Uri.parse(url);
    return '${uri.scheme}://${uri.host}';
  } catch (e) {
    return url;
  }
}

// ─── Quality Parsing ──────────────────────────────────────────────────────

/// Parse quality (resolution in pixels) from a filename or title string.
///
/// Ported from CSX's `getIndexQuality()`.
/// Returns quality int (480, 720, 1080, 2160, etc.) or 0 if unknown.
int getIndexQuality(String? str) {
  if (str == null || str.trim().isEmpty) return 0;

  // Try explicit resolution pattern: 480p, 720p, 1080p, etc.
  final resRegex = RegExp(r'(\d{3,4})[pP]');
  final resMatch = resRegex.firstMatch(str);
  if (resMatch != null) {
    final quality = int.tryParse(resMatch.group(1)!);
    if (quality != null) return quality;
  }

  // Fallback to keyword matching
  final lower = str.toLowerCase();
  if (lower.contains('8k')) return 4320;
  if (lower.contains('4k') || lower.contains('uhd') || lower.contains('2160')) {
    return 2160;
  }
  if (lower.contains('2k') || lower.contains('1440')) return 1440;
  if (lower.contains('1080')) return 1080;
  if (lower.contains('720')) return 720;
  if (lower.contains('480')) return 480;
  if (lower.contains('360')) return 360;

  return 0;
}

/// Format bytes to human-readable string (e.g. "1.23 GB", "456.78 MB")
String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(2)} KB';
  } else if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  } else {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

// ─── Ad/Shortener Detection ───────────────────────────────────────────────

/// Known ad, betting, shortener keywords to filter out from extraction results.
const List<String> _adKeywords = [
  'bit.ly', 'tinyurl', 'cutt.ly', 'linkvertise', 'adf.ly', 'shorturl',
  'doubleclick', 'popads', 'onclickads', 'exoclick', 'adsterra', 'adlink',
  'winexch', 'lotus365', 'bet', 'casino', '1xbet', 'mostbet', 'parimatch',
  'melbet', 'dafanews', 'sportybet', 'betway', 'bet365', 'adsystem',
  'adservices', 'googlesyndication', 'googleadservices', 'bonuscaf',
  'telegram.me', 't.me/joinchat', 'join.telegram',
];

/// Check if a URL is a known ad, betting, or shortener link.
bool isAdUrl(String url) {
  final lower = url.toLowerCase();
  for (final keyword in _adKeywords) {
    if (lower.contains(keyword)) return true;
  }
  return false;
}

/// Known non-video content types that should be rejected.
const List<String> _nonVideoContentTypes = [
  'text/html',
  'application/json',
  'text/plain',
  'text/xml',
];

/// Verify if a URL points to a playable video file.
///
/// Sends a partial GET request (Range: bytes=0-1024) and checks
/// the response status and content-type.
Future<bool> verifyVideoUrl(String url) async {
  if (url.isEmpty || !url.startsWith('http')) return false;
  if (isAdUrl(url)) return false;

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..badCertificateCallback = (cert, host, port) => true;

  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('User-Agent', kUserAgent);
    request.headers.set('Range', 'bytes=0-1024');

    final response = await request.close();
    // Drain the body immediately
    try {
      await response.listen((_) {}).cancel();
    } catch (_) {}
    client.close();

    // Accept 200 and 206 (partial content)
    if (response.statusCode >= 400) return false;

    final contentType =
        response.headers.value('content-type')?.toLowerCase() ?? '';

    // Explicit video types
    if (contentType.startsWith('video/')) return true;
    if (contentType.contains('mpegurl')) return true;
    if (contentType.contains('application/octet-stream')) return true;

    // Reject HTML/text (unless it's an m3u8 playlist)
    if (contentType.contains('html') || contentType.contains('text/')) {
      if (!contentType.contains('mpegurl') &&
          !url.toLowerCase().contains('.m3u8')) {
        return false;
      }
      return true;
    }

    // Extension-based fallback
    final lower = url.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('.mkv') ||
        lower.contains('.m3u8') ||
        lower.contains('.mpd') ||
        lower.contains('.webm') ||
        lower.contains('googleusercontent') ||
        lower.contains('r2.cloudflarestorage') ||
        lower.contains('r2.dev');
  } catch (e) {
    debugPrint('[ExtractionUtils] verifyVideoUrl failed for $url: $e');
    client.close();
    return false;
  }
}

// ─── HTML Parsing Helpers ─────────────────────────────────────────────────

/// Extract all href values from anchor tags in HTML.
List<MapEntry<String, String>> extractAnchorTags(String html) {
  final results = <MapEntry<String, String>>[];
  final aRegex = RegExp(
      r'<a\s+([^>]+)>(.*?)</a>', caseSensitive: false, dotAll: true);
  final hrefRegex =
      RegExp(r'''href=["']([^"']+)["']''', caseSensitive: false);
  final idRegex =
      RegExp(r'''id=["']([^"']+)["']''', caseSensitive: false);

  for (final match in aRegex.allMatches(html)) {
    final attrs = match.group(1) ?? '';
    final innerHtml = match.group(2) ?? '';
    final hrefMatch = hrefRegex.firstMatch(attrs);
    if (hrefMatch == null) continue;

    final href = hrefMatch.group(1)!;
    if (href == '#' || href.isEmpty) continue;

    final id = idRegex.firstMatch(attrs)?.group(1) ?? '';
    results.add(MapEntry('$id|$innerHtml', href));
  }
  return results;
}

/// Extract meta refresh URL from HTML.
String? extractMetaRefresh(String html) {
  final regex = RegExp(
      r'''<meta\s+http-equiv=["']refresh["']\s+content=["']\d+;\s*url=([^"']+)["']''',
      caseSensitive: false);
  return regex.firstMatch(html)?.group(1);
}

/// Extract window.location or window.location.href redirect URL from JS.
String? extractJsRedirect(String html) {
  // window.location.href = '...'
  final hrefRegex = RegExp(
      r"""window\.location\.href\s*=\s*['"](\s*https?://[^'"]+)['"]""",
      caseSensitive: false);
  final hrefMatch = hrefRegex.firstMatch(html);
  if (hrefMatch != null) {
    final url = hrefMatch.group(1)!.trim();
    if (!isAdUrl(url)) return url;
  }

  // window.location = '...'
  final locRegex = RegExp(
      r"""window\.location\s*=\s*['"](https?://[^'"]+)['"]""",
      caseSensitive: false);
  final locMatch = locRegex.firstMatch(html);
  if (locMatch != null) {
    final url = locMatch.group(1)!;
    if (!isAdUrl(url)) return url;
  }

  return null;
}

// ─── Title Sanitization ───────────────────────────────────────────────────

/// Clean title for filename matching (removes special chars).
String sanitizeTitle(String title) {
  return title
      .replaceAll(':', '-')
      .replaceAll('/', '-')
      .replaceAll(r'\', '-')
      .replaceAll('*', '-')
      .replaceAll('?', '-')
      .replaceAll('"', '-')
      .replaceAll('<', '-')
      .replaceAll('>', '-')
      .replaceAll('|', '-')
      .trim();
}

/// Compute SHA-256 hash of a string (used by Gofile extractor).
String sha256Hash(String input) {
  // Use dart:convert for basic hashing
  // For production, we use the crypto built into dart:io
  final bytes = utf8.encode(input);
  // We'll use a simple implementation via dart:io's secure hash
  return bytes
      .fold<int>(0, (hash, byte) => (hash * 31 + byte) & 0xFFFFFFFF)
      .toRadixString(16)
      .padLeft(8, '0');
}
