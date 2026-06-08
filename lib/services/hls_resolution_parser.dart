import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

/// Lightweight utility to parse HLS master playlists and extract
/// resolution options as a Map of "label" → "variant URL".
///
/// Example output:
/// ```
/// {"1080p": "https://cdn.../index-f1-v1-a1.m3u8",
///  "720p":  "https://cdn.../index-f2-v1-a1.m3u8",
///  "480p":  "https://cdn.../index-f3-v1-a1.m3u8"}
/// ```
class HlsResolutionParser {
  /// Fetches the master playlist from [masterUrl] and returns a sorted map
  /// of resolution labels to variant playlist URLs.
  ///
  /// Returns an empty map if the URL is not a master playlist or parsing fails.
  static Future<Map<String, String>> parseResolutions(
    String masterUrl, {
    Map<String, String>? headers,
  }) async {
    try {
      final defaultHeaders = {
        'Referer': 'https://peachify.top/',
        'Origin': 'https://peachify.top',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Accept': '*/*',
      };

      final mergedHeaders = {...defaultHeaders, ...?headers};

      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 8);
      dio.options.receiveTimeout = const Duration(seconds: 8);

      final response = await dio.get(
        masterUrl,
        options: Options(headers: mergedHeaders),
      );

      if (response.statusCode != 200) {
        developer.log(
          '[HlsResParser] Failed to fetch master playlist: HTTP ${response.statusCode}',
          name: 'HlsResParser',
        );
        return {};
      }

      final body = response.data.toString();

      // Quick check: is this a master playlist?
      if (!body.contains('#EXT-X-STREAM-INF')) {
        developer.log(
          '[HlsResParser] Not a master playlist (no #EXT-X-STREAM-INF found)',
          name: 'HlsResParser',
        );
        return {};
      }

      return _parseMasterPlaylist(body, masterUrl);
    } catch (e) {
      developer.log(
        '[HlsResParser] Error parsing resolutions: $e',
        name: 'HlsResParser',
      );
      return {};
    }
  }

  /// Parses the raw master playlist content and extracts resolution variants.
  static Map<String, String> _parseMasterPlaylist(
    String content,
    String masterUrl,
  ) {
    final lines = content.split('\n');
    final Map<String, _VariantInfo> variants = {};

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        // Parse the attributes
        final resolution = _extractAttribute(line, 'RESOLUTION');
        final bandwidth = _extractAttribute(line, 'BANDWIDTH');

        // Next non-empty, non-comment line is the variant URL
        String? variantUrl;
        for (int j = i + 1; j < lines.length; j++) {
          final nextLine = lines[j].trim();
          if (nextLine.isNotEmpty && !nextLine.startsWith('#')) {
            variantUrl = nextLine;
            break;
          }
        }

        if (variantUrl == null || variantUrl.isEmpty) continue;

        // Make URL absolute if relative
        if (!variantUrl.startsWith('http')) {
          final baseUri = Uri.parse(masterUrl);
          if (variantUrl.startsWith('/')) {
            variantUrl = '${baseUri.scheme}://${baseUri.host}$variantUrl';
          } else {
            final basePath = masterUrl.substring(0, masterUrl.lastIndexOf('/') + 1);
            variantUrl = '$basePath$variantUrl';
          }
        }

        // Extract resolution height
        int? height;
        if (resolution != null && resolution.contains('x')) {
          final parts = resolution.split('x');
          height = int.tryParse(parts.last);
        }

        // Parse bandwidth
        final bw = int.tryParse(bandwidth ?? '0') ?? 0;

        // Create label from resolution
        final label = _heightToLabel(height);
        if (label == null) continue;

        // Keep highest bandwidth for each resolution
        if (!variants.containsKey(label) || bw > variants[label]!.bandwidth) {
          variants[label] = _VariantInfo(
            label: label,
            url: variantUrl,
            bandwidth: bw,
            height: height ?? 0,
          );
        }
      }
    }

    // Sort by height descending (highest first)
    final sortedEntries = variants.entries.toList()
      ..sort((a, b) => b.value.height.compareTo(a.value.height));

    final result = <String, String>{};
    for (final entry in sortedEntries) {
      result[entry.key] = entry.value.url;
    }

    if (kDebugMode) {
      developer.log(
        '[HlsResParser] Parsed ${result.length} resolutions: ${result.keys.join(", ")}',
        name: 'HlsResParser',
      );
    }

    return result;
  }

  /// Extracts a named attribute from an EXT-X-STREAM-INF line.
  /// Example: `RESOLUTION=1920x1080` → `"1920x1080"`
  static String? _extractAttribute(String line, String attributeName) {
    // Pattern: ATTRIBUTE_NAME=value or ATTRIBUTE_NAME="value"
    final pattern = RegExp('$attributeName=("([^"]*)"|([^,\\s]*))');
    final match = pattern.firstMatch(line);
    if (match != null) {
      return match.group(2) ?? match.group(3);
    }
    return null;
  }

  /// Maps a resolution height to a human-readable label.
  static String? _heightToLabel(int? height) {
    if (height == null) return null;
    if (height >= 2160) return '4K';
    if (height >= 1440) return '1440p';
    if (height >= 1080) return '1080p';
    if (height >= 720) return '720p';
    if (height >= 480) return '480p';
    if (height >= 360) return '360p';
    if (height >= 240) return '240p';
    return '${height}p';
  }
}

class _VariantInfo {
  final String label;
  final String url;
  final int bandwidth;
  final int height;

  _VariantInfo({
    required this.label,
    required this.url,
    required this.bandwidth,
    required this.height,
  });
}
