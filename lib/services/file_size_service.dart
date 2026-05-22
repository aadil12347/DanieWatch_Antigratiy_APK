// lib/services/file_size_service.dart
// ─────────────────────────────────────────────────────────
// Lightweight service to fetch file size info for videos.
// Used by the download modal to show estimated file sizes.
// Works with any embed URL by checking the download API
// or falling back to HTTP HEAD on the direct stream URL.
// ─────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:developer' as developer;

/// Timeout for individual HTTP requests
const Duration _httpTimeout = Duration(seconds: 5);

const String _userAgent =
    'Mozilla/5.0 (Linux; Android 13; SM-G981B) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36';

/// Regex to extract the video code from any bysebuho URL
final RegExp _codeRegex =
    RegExp(r'bysebuho\.com/(?:e|d|download)/([a-z0-9]+)');

const String _baseUrl = 'https://bysebuho.com';

/// Service for fetching video file sizes to display in download UI.
class FileSizeService {
  FileSizeService._();
  static final FileSizeService instance = FileSizeService._();

  /// Fetch the file size for a video embed URL.
  /// Returns a [FileSizeInfo] with the original and/or 720p sizes.
  /// Returns null on failure.
  Future<FileSizeInfo?> fetchFileSizeInfo(String embedUrl) async {
    try {
      return await _fetchInternal(embedUrl)
          .timeout(const Duration(seconds: 7), onTimeout: () {
        developer.log(
            '[FileSizeService] ⏱ Fetch timed out',
            name: 'FileSizeService');
        return null;
      });
    } catch (e) {
      developer.log('[FileSizeService] Error: $e',
          name: 'FileSizeService');
      return null;
    }
  }

  Future<FileSizeInfo?> _fetchInternal(String embedUrl) async {
    // Check if it's a bysebuho URL
    final match = _codeRegex.firstMatch(embedUrl);
    if (match == null) return null;

    final code = match.group(1);
    if (code == null) return null;

    developer.log('[FileSizeService] Fetching file size for code: $code',
        name: 'FileSizeService');

    // 1. Establish session
    final sessionCookies = await _establishSession(code);
    if (sessionCookies == null || sessionCookies.isEmpty) {
      developer.log('[FileSizeService] Failed to establish session',
          name: 'FileSizeService');
      return null;
    }

    // 2. Call downloads API
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
      return http.Response('', 408);
    });

    if (response.statusCode != 200) {
      developer.log(
          '[FileSizeService] Downloads API returned ${response.statusCode}',
          name: 'FileSizeService');
      return null;
    }

    final data = jsonDecode(response.body);
    final options = data is Map ? data['options'] : null;
    if (options is! List) return null;

    int? originalSize;
    int? size720p;

    for (final opt in options) {
      if (opt is! Map) continue;

      final label = opt['label']?.toString().toLowerCase() ?? '';
      final sizeBytes = opt['size_bytes'];
      if (sizeBytes is! int || sizeBytes <= 0) continue;

      if (label == 'original') {
        originalSize = sizeBytes;
      } else if (label.contains('720')) {
        size720p = sizeBytes;
      }
    }

    // Fallback: use the first available size as original
    if (originalSize == null) {
      for (final opt in options) {
        if (opt is Map) {
          final size = opt['size_bytes'];
          if (size is int && size > 0) {
            originalSize = size;
            break;
          }
        }
      }
    }

    if (originalSize == null && size720p == null) return null;

    final result = FileSizeInfo(
      originalSizeBytes: originalSize,
      size720pBytes: size720p,
    );

    developer.log(
        '[FileSizeService] ✅ Original: ${result.originalSizeFormatted}, '
        '720p: ${result.size720pFormatted}',
        name: 'FileSizeService');

    return result;
  }

  /// Establish a session by GETting the download page and capturing cookies.
  Future<String?> _establishSession(String code) async {
    try {
      final url = Uri.parse('$_baseUrl/d/$code');
      final response = await http.get(
        url,
        headers: {
          'User-Agent': _userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.5',
        },
      ).timeout(_httpTimeout);

      if (response.statusCode != 200) return null;

      // Extract cookies from response headers
      final setCookieHeaders = response.headers['set-cookie'];
      if (setCookieHeaders != null && setCookieHeaders.isNotEmpty) {
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

      return null;
    } catch (e) {
      developer.log('[FileSizeService] Session error: $e',
          name: 'FileSizeService');
      return null;
    }
  }
}

/// File size information for a video.
class FileSizeInfo {
  final int? originalSizeBytes;
  final int? size720pBytes;

  FileSizeInfo({this.originalSizeBytes, this.size720pBytes});

  /// The display size: prefer 720p, fall back to original.
  int? get displaySizeBytes => size720pBytes ?? originalSizeBytes;

  /// The original file size formatted as a human-readable string.
  String? get originalSizeFormatted =>
      originalSizeBytes != null ? _formatBytes(originalSizeBytes!) : null;

  /// The 720p file size formatted as a human-readable string.
  String? get size720pFormatted =>
      size720pBytes != null ? _formatBytes(size720pBytes!) : null;

  /// The best available display size formatted.
  String? get displaySizeFormatted =>
      displaySizeBytes != null ? _formatBytes(displaySizeBytes!) : null;

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
