/// Dynamic URL management for sites that change domains frequently.
///
/// Ported from CSX's `getLatestBaseUrl()` pattern which fetches
/// live domain configs from a GitHub-hosted JSON file.
///
/// Reference: CSX/VegaMovies/Extractors.kt — getLatestBaseUrl()

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DynamicUrls {
  static final DynamicUrls _instance = DynamicUrls._internal();
  factory DynamicUrls() => _instance;
  DynamicUrls._internal();

  /// GitHub raw URL for dynamic URL config.
  /// Uses CSX's original source as a reference, but you can host your own.
  static const String _configUrl =
      'https://raw.githubusercontent.com/SaurabhKaperwan/Utils/refs/heads/main/urls.json';

  static const String _cacheKey = 'dynamic_urls_cache';
  static const String _cacheTimeKey = 'dynamic_urls_cache_time';
  static const Duration _cacheDuration = Duration(hours: 24);

  /// Cached URL map: source key -> latest base URL
  Map<String, String> _urlMap = {};
  bool _isLoaded = false;

  /// Default fallback URLs for each source (hardcoded baseline).
  static const Map<String, String> _defaultUrls = {
    'vcloud': 'https://vcloud.lol',
    'hubcloud': 'https://hubcloud.club',
    'gdflix': 'https://new.gdflix.cfd',
    'vegamovies': 'https://vegamovies.mq',
    'rogmovies': 'https://rogmovies.com',
    'driveleech': 'https://driveleech.org',
    'driveseed': 'https://driveseed.org',
    'moviesmod': 'https://moviesmod.day',
    'moviesdrive': 'https://moviesdrive.world',
  };

  /// Initialize: load from cache, refresh in background if stale.
  Future<void> init() async {
    if (_isLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheStr = prefs.getString(_cacheKey);
      final cacheTime = prefs.getInt(_cacheTimeKey) ?? 0;

      if (cacheStr != null && cacheStr.isNotEmpty) {
        _parseCache(cacheStr);
        _isLoaded = true;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      if (cacheStr == null ||
          (now - cacheTime) > _cacheDuration.inMilliseconds) {
        if (cacheStr == null) {
          // First time: block until loaded
          await _refreshCache(prefs);
          _isLoaded = true;
        } else {
          // Background refresh
          _refreshCache(prefs).catchError((e) {
            debugPrint('[DynamicUrls] Background refresh failed: $e');
          });
        }
      }
    } catch (e) {
      debugPrint('[DynamicUrls] Init error: $e');
      _isLoaded = true; // Use defaults
    }
  }

  void _parseCache(String cacheStr) {
    try {
      final Map<String, dynamic> decoded = jsonDecode(cacheStr);
      _urlMap = decoded.map((k, v) => MapEntry(k, v.toString()));
      debugPrint('[DynamicUrls] Loaded ${_urlMap.length} cached URLs.');
    } catch (e) {
      debugPrint('[DynamicUrls] Cache parse error: $e');
    }
  }

  Future<void> _refreshCache(SharedPreferences prefs) async {
    debugPrint('[DynamicUrls] Fetching fresh URL config...');
    try {
      final response = await http
          .get(Uri.parse(_configUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          await prefs.setString(_cacheKey, response.body);
          await prefs.setInt(
              _cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
          _parseCache(response.body);
        }
      } else {
        debugPrint(
            '[DynamicUrls] Config fetch failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[DynamicUrls] Refresh error: $e');
    }
  }

  /// Get the latest base URL for a source.
  ///
  /// Ported from CSX's `getLatestBaseUrl(baseUrl, source)`.
  ///
  /// [source] is the key in the JSON config (e.g. "gdflix", "vegamovies").
  /// [fallback] is the hardcoded default URL to use if no config exists.
  Future<String> getLatestBaseUrl(String source, {String? fallback}) async {
    await init();
    final url = _urlMap[source];
    if (url != null && url.isNotEmpty) return url;
    return fallback ?? _defaultUrls[source] ?? '';
  }

  /// Get latest URL and replace the base in an existing URL.
  ///
  /// E.g., if `url` is `https://old-gdflix.com/file/123` and the latest
  /// base for "gdflix" is `https://new.gdflix.cfd`, returns
  /// `https://new.gdflix.cfd/file/123`.
  Future<String> resolveUrl(String url, String source) async {
    final currentBase = _getBaseFromUrl(url);
    final latestBase = await getLatestBaseUrl(source, fallback: currentBase);
    if (currentBase == latestBase) return url;
    return url.replaceFirst(currentBase, latestBase);
  }

  String _getBaseFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}';
    } catch (_) {
      return url;
    }
  }

  /// Force refresh the URL cache.
  Future<void> forceRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    await _refreshCache(prefs);
  }
}
