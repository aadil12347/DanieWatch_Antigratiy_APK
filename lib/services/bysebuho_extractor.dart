// lib/services/bysebuho_extractor.dart
// ─────────────────────────────────────────────────────────
// Direct API extraction for bysebuho.com embed URLs.
// Bypasses the slow WebView interception by calling the
// bysebuho API directly and decrypting the AES-256-GCM
// encrypted payload to get the master m3u8 URL.
//
// Expected time: ~1-2 seconds (vs 10-20s with WebView)
// Max timeout: 7 seconds before falling back to WebView
// ─────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;

/// Timeout for individual HTTP requests (session + playback API)
const Duration _httpTimeout = Duration(seconds: 5);

/// Overall timeout for the entire direct extraction flow
const Duration _extractionTimeout = Duration(seconds: 7);

/// Result of a successful Bysebuho extraction.
class BysebuhoExtractionResult {
  /// The master HLS playlist URL (contains all qualities + audio tracks)
  final String masterUrl;

  /// All edge URLs found in the decrypted payload
  final Map<String, String> edges;

  /// The tracks array from the decrypted payload (if present)
  final List<dynamic>? tracks;

  BysebuhoExtractionResult({
    required this.masterUrl,
    this.edges = const {},
    this.tracks,
  });
}

/// Direct API-based extractor for bysebuho.com video URLs.
///
/// Flow:
/// 1. Extract video code from URL (e.g., bysebuho.com/e/abc123 → abc123)
/// 2. GET the download page to establish session cookies
/// 3. POST to /api/videos/{code}/playback with session cookies
/// 4. Decrypt the AES-256-GCM encrypted payload
/// 5. Parse the JSON to extract the master m3u8 URL
class BysebuhoExtractor {
  BysebuhoExtractor._();
  static final BysebuhoExtractor instance = BysebuhoExtractor._();

  static const String _baseUrl = 'https://bysebuho.com';

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 13; SM-G981B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36';

  /// Regex to extract the video code from any bysebuho URL
  static final RegExp _codeRegex =
      RegExp(r'bysebuho\.com/(?:e|d|download)/([a-z0-9]+)');

  /// Extract the video code from a bysebuho URL.
  /// Returns null if the URL is not a bysebuho URL.
  String? extractCode(String url) {
    final match = _codeRegex.firstMatch(url);
    return match?.group(1);
  }

  /// Check if a URL is a bysebuho.com URL.
  bool isBysebuhoUrl(String url) {
    return url.contains('bysebuho.com');
  }

  /// Directly extract the master m3u8 URL from a bysebuho embed URL.
  ///
  /// This bypasses the WebView entirely and uses the API directly.
  /// Returns null if extraction fails (caller should fall back to WebView).
  /// Auto-times out after 7 seconds.
  Future<BysebuhoExtractionResult?> extract(String embedUrl,
      {bool bypassCache = false}) async {
    final stopwatch = Stopwatch()..start();
    try {
      // Wrap entire extraction in a timeout to avoid hanging
      final result = await _extractInternal(embedUrl, bypassCache: bypassCache)
          .timeout(_extractionTimeout, onTimeout: () {
        developer.log(
            '[BysebuhoExtractor] ⏱ Extraction timed out after ${_extractionTimeout.inSeconds}s, falling back to WebView',
            name: 'BysebuhoExtractor');
        return null;
      });
      stopwatch.stop();
      developer.log(
          '[BysebuhoExtractor] Extraction took ${stopwatch.elapsedMilliseconds}ms',
          name: 'BysebuhoExtractor');
      return result;
    } catch (e, stack) {
      stopwatch.stop();
      developer.log('[BysebuhoExtractor] Error after ${stopwatch.elapsedMilliseconds}ms: $e',
          name: 'BysebuhoExtractor', error: e, stackTrace: stack);
      return null;
    }
  }

  Future<BysebuhoExtractionResult?> _extractInternal(String embedUrl,
      {bool bypassCache = false}) async {
    // 1. Extract video code
    final code = extractCode(embedUrl);
    if (code == null) {
      developer.log('[BysebuhoExtractor] Could not extract code from: $embedUrl',
          name: 'BysebuhoExtractor');
      return null;
    }

    developer.log('[BysebuhoExtractor] Extracting code: $code from: $embedUrl',
        name: 'BysebuhoExtractor');

    // 2. Check cache
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'bysebuho_$code';
    if (!bypassCache) {
      final cachedUrl = prefs.getString(cacheKey);
      if (cachedUrl != null) {
        developer.log('[BysebuhoExtractor] Cache hit: $cachedUrl',
            name: 'BysebuhoExtractor');
        return BysebuhoExtractionResult(masterUrl: cachedUrl);
      }
    }

    // 3. Establish session by GETting the download page
    final sessionCookies = await _establishSession(code)
        .timeout(_httpTimeout, onTimeout: () {
      developer.log('[BysebuhoExtractor] ⏱ Session request timed out',
          name: 'BysebuhoExtractor');
      return null;
    });
    if (sessionCookies == null || sessionCookies.isEmpty) {
      developer.log('[BysebuhoExtractor] Failed to establish session',
          name: 'BysebuhoExtractor');
      return null;
    }

    developer.log('[BysebuhoExtractor] Session established, cookies: $sessionCookies',
        name: 'BysebuhoExtractor');

    // 4. Call the playback API
    final encryptedPayload = await _fetchPlaybackPayload(code, sessionCookies)
        .timeout(_httpTimeout, onTimeout: () {
      developer.log('[BysebuhoExtractor] ⏱ Playback API request timed out',
          name: 'BysebuhoExtractor');
      return null;
    });
    if (encryptedPayload == null) {
      developer.log('[BysebuhoExtractor] Failed to fetch playback payload',
          name: 'BysebuhoExtractor');
      return null;
    }

    // 5. Decrypt the payload
    final decryptedJson = await _decryptPayload(encryptedPayload);
    if (decryptedJson == null) {
      developer.log('[BysebuhoExtractor] Failed to decrypt payload',
          name: 'BysebuhoExtractor');
      return null;
    }

    developer.log('[BysebuhoExtractor] Decrypted payload: $decryptedJson',
        name: 'BysebuhoExtractor');

    // 6. Parse the decrypted JSON to extract the master URL
    final result = _parseDecryptedPayload(decryptedJson);
    if (result == null) {
      developer.log('[BysebuhoExtractor] Failed to parse decrypted payload',
          name: 'BysebuhoExtractor');
      return null;
    }

    // 7. Cache the result
    await prefs.setString(cacheKey, result.masterUrl);

    developer.log('[BysebuhoExtractor] ✅ Success! Master URL: ${result.masterUrl}',
        name: 'BysebuhoExtractor');

    return result;
  }

  /// Fetch download links from the downloads API.
  /// Returns a list of direct MP4 download URLs, or null on failure.
  /// Auto-times out after 7 seconds.
  Future<List<String>?> fetchDownloadLinks(String embedUrl) async {
    try {
      return await _fetchDownloadLinksInternal(embedUrl)
          .timeout(_extractionTimeout, onTimeout: () {
        developer.log(
            '[BysebuhoExtractor] ⏱ Download fetch timed out after ${_extractionTimeout.inSeconds}s',
            name: 'BysebuhoExtractor');
        return null;
      });
    } catch (e) {
      developer.log('[BysebuhoExtractor] Download fetch error: $e',
          name: 'BysebuhoExtractor');
      return null;
    }
  }

  Future<List<String>?> _fetchDownloadLinksInternal(String embedUrl) async {
    final code = extractCode(embedUrl);
    if (code == null) return null;

    final sessionCookies = await _establishSession(code)
        .timeout(_httpTimeout, onTimeout: () => null);
    if (sessionCookies == null || sessionCookies.isEmpty) return null;

    final url = Uri.parse('$_baseUrl/api/videos/$code/downloads');
    final response = await http.get(
      url,
      headers: {
        'User-Agent': _userAgent,
        'Referer': '$_baseUrl/d/$code',
        'Origin': _baseUrl,
        'Cookie': sessionCookies,
        'Accept': 'application/json',
      },
    ).timeout(_httpTimeout, onTimeout: () {
      developer.log('[BysebuhoExtractor] ⏱ Downloads API request timed out',
          name: 'BysebuhoExtractor');
      return http.Response('', 408);
    });

    if (response.statusCode != 200) {
      developer.log('[BysebuhoExtractor] Downloads API returned ${response.statusCode}',
          name: 'BysebuhoExtractor');
      return null;
    }

    final data = jsonDecode(response.body);
    final links = <String>[];

    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          final downloadUrl = item['url']?.toString();
          if (downloadUrl != null && downloadUrl.isNotEmpty) {
            links.add(downloadUrl);
          }
        }
      }
    } else if (data is Map) {
      // Handle if it's a map with download entries
      for (final entry in data.entries) {
        if (entry.value is Map) {
          final downloadUrl = entry.value['url']?.toString();
          if (downloadUrl != null && downloadUrl.isNotEmpty) {
            links.add(downloadUrl);
          }
        } else if (entry.value is String && entry.value.toString().contains('.mp4')) {
          links.add(entry.value.toString());
        }
      }
    }

    if (links.isNotEmpty) {
      developer.log('[BysebuhoExtractor] Found ${links.length} download links',
          name: 'BysebuhoExtractor');
    }

    return links.isNotEmpty ? links : null;
  }

  /// Establish a session by GETting the download page and capturing cookies.
  Future<String?> _establishSession(String code) async {
    try {
      final url = Uri.parse('$_baseUrl/d/$code');
      final response = await http.get(
        url,
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.5',
        },
      );

      if (response.statusCode != 200) {
        developer.log('[BysebuhoExtractor] Session page returned ${response.statusCode}',
            name: 'BysebuhoExtractor');
        return null;
      }

      // Extract cookies from response headers
      final setCookieHeaders = response.headers['set-cookie'];
      if (setCookieHeaders != null && setCookieHeaders.isNotEmpty) {
        // Parse cookies: take just the name=value part before any semicolons
        final cookies = setCookieHeaders
            .split(',')
            .map((cookie) {
              final parts = cookie.trim().split(';');
              return parts[0].trim();
            })
            .where((c) => c.isNotEmpty)
            .join('; ');
        return cookies.isNotEmpty ? cookies : null;
      }

      // Some servers use different header casing
      final allHeaders = response.headers;
      final cookieParts = <String>[];
      for (final entry in allHeaders.entries) {
        if (entry.key.toLowerCase() == 'set-cookie') {
          final parts = entry.value.split(';');
          if (parts.isNotEmpty && parts[0].trim().isNotEmpty) {
            cookieParts.add(parts[0].trim());
          }
        }
      }

      return cookieParts.isNotEmpty ? cookieParts.join('; ') : null;
    } catch (e) {
      developer.log('[BysebuhoExtractor] Session establishment error: $e',
          name: 'BysebuhoExtractor');
      return null;
    }
  }

  /// Call the playback API and return the encrypted payload map.
  Future<Map<String, dynamic>?> _fetchPlaybackPayload(
      String code, String cookies) async {
    try {
      final url = Uri.parse('$_baseUrl/api/videos/$code/playback');
      final response = await http.post(
        url,
        headers: {
          'User-Agent': _userAgent,
          'Referer': '$_baseUrl/d/$code',
          'Origin': _baseUrl,
          'Cookie': cookies,
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        developer.log(
            '[BysebuhoExtractor] Playback API returned ${response.statusCode}: ${response.body}',
            name: 'BysebuhoExtractor');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // Validate that the expected fields are present
      if (!data.containsKey('payload') || !data.containsKey('key_parts')) {
        developer.log('[BysebuhoExtractor] Missing expected fields in response: ${data.keys}',
            name: 'BysebuhoExtractor');
        return null;
      }

      return data;
    } catch (e) {
      developer.log('[BysebuhoExtractor] Playback API error: $e',
          name: 'BysebuhoExtractor');
      return null;
    }
  }

  /// Decrypt the AES-256-GCM encrypted payload.
  Future<String?> _decryptPayload(Map<String, dynamic> encryptedData) async {
    try {
      // 1. Construct the 32-byte AES key from key_parts
      final keyParts = encryptedData['key_parts'] as List;
      if (keyParts.length < 2) {
        developer.log('[BysebuhoExtractor] Not enough key_parts: ${keyParts.length}',
            name: 'BysebuhoExtractor');
        return null;
      }

      final keyPart1 = base64Decode(keyParts[0].toString());
      final keyPart2 = base64Decode(keyParts[1].toString());
      final keyBytes = Uint8List.fromList([...keyPart1, ...keyPart2]);

      if (keyBytes.length != 32) {
        developer.log('[BysebuhoExtractor] Key is not 32 bytes: ${keyBytes.length}',
            name: 'BysebuhoExtractor');
        return null;
      }

      // 2. Decode the IV
      final ivString = encryptedData['iv'].toString();
      final ivBytes = base64Decode(ivString);

      // 3. Decode the payload (ciphertext + auth tag)
      final payloadBytes = base64Decode(encryptedData['payload'].toString());

      // 4. Split payload into ciphertext and GCM auth tag (last 16 bytes)
      if (payloadBytes.length < 16) {
        developer.log('[BysebuhoExtractor] Payload too short: ${payloadBytes.length}',
            name: 'BysebuhoExtractor');
        return null;
      }

      final ciphertextLength = payloadBytes.length - 16;
      final ciphertext = Uint8List.sublistView(payloadBytes, 0, ciphertextLength);
      final authTag = Uint8List.sublistView(payloadBytes, ciphertextLength);

      // 5. Decrypt using AES-256-GCM
      final algorithm = AesGcm.with256bits();
      final secretKey = SecretKey(keyBytes.toList());

      // Construct SecretBox with separate ciphertext, nonce, and MAC
      final secretBox = SecretBox(
        ciphertext.toList(),
        nonce: ivBytes.toList(),
        mac: Mac(authTag.toList()),
      );

      final decryptedBytes = await algorithm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      // 6. Convert to string
      final decryptedString = utf8.decode(decryptedBytes);
      return decryptedString;
    } catch (e, stack) {
      developer.log('[BysebuhoExtractor] Decryption error: $e',
          name: 'BysebuhoExtractor', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Parse the decrypted JSON payload to extract the master m3u8 URL.
  BysebuhoExtractionResult? _parseDecryptedPayload(String jsonString) {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      // Extract the master URL
      final masterUrl = data['master']?.toString();
      if (masterUrl == null || masterUrl.isEmpty) {
        developer.log('[BysebuhoExtractor] No master URL in decrypted payload',
            name: 'BysebuhoExtractor');
        return null;
      }

      // Extract edge URLs
      final edges = <String, String>{};
      for (final entry in data.entries) {
        if (entry.key.startsWith('edge_') && entry.value is String) {
          edges[entry.key] = entry.value.toString();
        }
      }

      // Extract tracks
      final tracks = data['tracks'] as List<dynamic>?;

      return BysebuhoExtractionResult(
        masterUrl: masterUrl,
        edges: edges,
        tracks: tracks,
      );
    } catch (e) {
      developer.log('[BysebuhoExtractor] Parse error: $e',
          name: 'BysebuhoExtractor');
      return null;
    }
  }
}