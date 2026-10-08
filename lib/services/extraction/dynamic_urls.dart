/// Dynamic URL management for sites that change domains frequently.
///
/// Fetches live domain configs primarily from Supabase `app_config` (key: 'provider_domains')
/// with automatic SharedPreferences local caching and fallback to GitHub / defaults.
///
/// Whenever domains change, updating the 'provider_domains' JSON in Supabase
/// automatically propagates the new domains to all user apps on next startup or live via Realtime.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DynamicUrls {
  static final DynamicUrls _instance = DynamicUrls._internal();
  factory DynamicUrls() => _instance;
  DynamicUrls._internal();

  static DynamicUrls get instance => _instance;

  /// GitHub raw URL fallback if Supabase is unavailable.
  static const String _fallbackConfigUrl =
      'https://raw.githubusercontent.com/SaurabhKaperwan/Utils/refs/heads/main/urls.json';

  static const String _cacheKey = 'dynamic_urls_cache';
  static const String _cacheTimeKey = 'dynamic_urls_cache_time';
  static const Duration _cacheDuration = Duration(hours: 1);

  /// Cached URL map: source key -> latest base URL
  Map<String, String> _urlMap = {};
  bool _isLoaded = false;
  RealtimeChannel? _realtimeChannel;

  /// Default baseline URLs (fallback if completely offline on first install).
  static const Map<String, String> _defaultUrls = {
    'vcloud': 'https://vcloud.lol',
    'hubcloud': 'https://hubcloud.club',
    'gdflix': 'https://new.gdflix.cfd',
    'vegamovies': 'https://vegamovies.gallery',
    'rogmovies': 'https://rogmovies.wtf',
    'driveleech': 'https://driveleech.org',
    'driveseed': 'https://driveseed.org',
    'moviesmod': 'https://moviesmod.day',
    'moviesdrive': 'https://moviesdrive.world',
  };

  /// Clean URL helper: trims whitespace and trailing slashes so URL interpolations never get double slashes.
  static String cleanUrl(String url) {
    return url.trim().replaceAll(RegExp(r'/+$'), '');
  }

  /// Instant synchronous getters for Vegamovies and Rogmovies base URLs.
  static String get vegaBase =>
      cleanUrl(_instance._urlMap['vegamovies'] ?? _defaultUrls['vegamovies']!);

  static String get rogBase =>
      cleanUrl(_instance._urlMap['rogmovies'] ?? _defaultUrls['rogmovies']!);

  /// Generic synchronous getter for any source.
  static String getBase(String source) =>
      cleanUrl(_instance._urlMap[source] ?? _defaultUrls[source] ?? '');

  /// Fast synchronous initialization from SharedPreferences (<1ms).
  /// Call this in Phase 1 of app startup.
  void initFromPrefs(SharedPreferences prefs) {
    if (_isLoaded) return;
    final cacheStr = prefs.getString(_cacheKey);
    if (cacheStr != null && cacheStr.isNotEmpty) {
      _parseCache(cacheStr);
      _isLoaded = true;
    }
  }

  /// Initialize: load from cache, then sync fresh config from Supabase.
  Future<void> init() async {
    if (!_isLoaded) {
      try {
        final prefs = await SharedPreferences.getInstance();
        initFromPrefs(prefs);
      } catch (e) {
        debugPrint('[DynamicUrls] Init prefs error: $e');
      }
    }
    await syncFromSupabase();
  }

  void _parseCache(String cacheStr) {
    try {
      final dynamic decoded = jsonDecode(cacheStr);
      if (decoded is Map) {
        final newMap = <String, String>{};
        decoded.forEach((k, v) {
          if (v != null && v.toString().isNotEmpty) {
            newMap[k.toString().toLowerCase().trim()] = cleanUrl(v.toString());
          }
        });
        _urlMap = newMap;
        debugPrint('[DynamicUrls] Loaded ${_urlMap.length} URLs (Vega: $vegaBase, Rog: $rogBase)');
      }
    } catch (e) {
      debugPrint('[DynamicUrls] Cache parse error: $e');
    }
  }

  /// Sync live provider domains from Supabase `app_config` table (key: 'provider_domains').
  Future<void> syncFromSupabase() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('app_config')
          .select('value')
          .eq('key', 'provider_domains')
          .maybeSingle();

      if (response != null && response['value'] is Map) {
        final map = Map<String, dynamic>.from(response['value'] as Map);
        final prefs = await SharedPreferences.getInstance();
        final jsonStr = jsonEncode(map);
        await prefs.setString(_cacheKey, jsonStr);
        await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
        _parseCache(jsonStr);
        _isLoaded = true;
        debugPrint('[DynamicUrls] ✅ Synced from Supabase: Vega=$vegaBase, Rog=$rogBase');

        _subscribeToRealtimeChanges();
        return;
      }
    } catch (e) {
      debugPrint('[DynamicUrls] Supabase sync failed: $e (Falling back to cache/GitHub)');
    }

    // Fallback: If cache is empty or stale, try GitHub fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheStr = prefs.getString(_cacheKey);
      final cacheTime = prefs.getInt(_cacheTimeKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (cacheStr == null || (now - cacheTime) > _cacheDuration.inMilliseconds) {
        await _fetchFallbackGitHub(prefs);
      }
    } catch (_) {}
  }

  /// Listen for live updates on `app_config` table via Supabase Realtime.
  void _subscribeToRealtimeChanges() {
    if (_realtimeChannel != null) return;
    try {
      final supabase = Supabase.instance.client;
      _realtimeChannel = supabase
          .channel('provider_domains_realtime')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'app_config',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'key',
              value: 'provider_domains',
            ),
            callback: (payload) async {
              debugPrint('[DynamicUrls] 🔔 Realtime domain update received!');
              final newRecord = payload.newRecord;
              if (newRecord.containsKey('value') && newRecord['value'] is Map) {
                final map = Map<String, dynamic>.from(newRecord['value'] as Map);
                final jsonStr = jsonEncode(map);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(_cacheKey, jsonStr);
                await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
                _parseCache(jsonStr);
                debugPrint('[DynamicUrls] 🚀 Updated live domains: Vega=$vegaBase, Rog=$rogBase');
              }
            },
          )
          ..subscribe();
      debugPrint('[DynamicUrls] 📡 Subscribed to Supabase Realtime for provider_domains');
    } catch (e) {
      debugPrint('[DynamicUrls] Realtime subscription error: $e');
    }
  }

  Future<void> _fetchFallbackGitHub(SharedPreferences prefs) async {
    try {
      final response = await http
          .get(Uri.parse(_fallbackConfigUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          await prefs.setString(_cacheKey, response.body);
          await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
          _parseCache(response.body);
          _isLoaded = true;
        }
      }
    } catch (e) {
      debugPrint('[DynamicUrls] GitHub fallback error: $e');
    }
  }

  /// Get the latest base URL for a source.
  Future<String> getLatestBaseUrl(String source, {String? fallback}) async {
    final key = source.toLowerCase().trim();
    final url = _urlMap[key];
    if (url != null && url.isNotEmpty) return cleanUrl(url);
    if (!_isLoaded) {
      await init();
      final refreshed = _urlMap[key];
      if (refreshed != null && refreshed.isNotEmpty) return cleanUrl(refreshed);
    }
    return fallback ?? _defaultUrls[key] ?? '';
  }

  /// Get latest URL and replace the base in an existing URL.
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

  /// Force refresh the URL cache from Supabase.
  Future<void> forceRefresh() async {
    await syncFromSupabase();
  }
}
