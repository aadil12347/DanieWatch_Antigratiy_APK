import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class VcloudExtractorService {
  static final VcloudExtractorService _instance = VcloudExtractorService._internal();
  factory VcloudExtractorService() => _instance;
  VcloudExtractorService._internal();

  static const String _githubApiUrl =
      'https://api.github.com/repos/aadil12347/DanieWatch_Apk_Database/contents/streaming_links';
  static const String _rawBaseUrl =
      'https://raw.githubusercontent.com/aadil12347/DanieWatch_Apk_Database/main/streaming_links';
  
  static const String _cacheKey = 'vcloud_files_cache';
  static const String _cacheTimeKey = 'vcloud_files_cache_time';
  static const Duration _cacheDuration = Duration(hours: 24);

  // In-memory mapping of tmdbId -> download_url
  final Map<int, String> _fileMap = {};
  bool _isInitialized = false;

  /// Initializes the service. Loads the file map cache from SharedPreferences,
  /// and triggers a background refresh if empty or expired.
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheStr = prefs.getString(_cacheKey);
      final cacheTime = prefs.getInt(_cacheTimeKey) ?? 0;

      if (cacheStr != null && cacheStr.isNotEmpty) {
        _parseCache(cacheStr);
        _isInitialized = true;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      if (cacheStr == null || (now - cacheTime) > _cacheDuration.inMilliseconds) {
        // Fetch fresh list from GitHub (inline if no cache, else background)
        if (cacheStr == null) {
          await _refreshCache(prefs);
          _isInitialized = true;
        } else {
          // Fire-and-forget in background to not block startup
          _refreshCache(prefs).catchError((e) {
            debugPrint('[VcloudExtractor] Background cache refresh failed: $e');
          });
        }
      }
    } catch (e) {
      debugPrint('[VcloudExtractor] Initialization error: $e');
    }
  }

  void _parseCache(String cacheStr) {
    try {
      final List<dynamic> list = jsonDecode(cacheStr);
      _fileMap.clear();
      final idRegExp = RegExp(r'_(?:movie|series|custom_series)_(\d+)');
      for (var file in list) {
        if (file is Map) {
          final name = file['name']?.toString() ?? '';
          final downloadUrl = file['download_url']?.toString() ?? '';
          if (name.isNotEmpty && downloadUrl.isNotEmpty) {
            final match = idRegExp.firstMatch(name);
            if (match != null) {
              final id = int.tryParse(match.group(1)!);
              if (id != null) {
                _fileMap[id] = downloadUrl;
              }
            }
          }
        }
      }
      debugPrint('[VcloudExtractor] Loaded ${_fileMap.length} items from cache.');
    } catch (e) {
      debugPrint('[VcloudExtractor] Error parsing cache: $e');
    }
  }

  Future<void> _refreshCache(SharedPreferences prefs) async {
    debugPrint('[VcloudExtractor] Fetching fresh file listing from GitHub...');
    try {
      final response = await http.get(Uri.parse(_githubApiUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final rawBody = response.body;
        // Verify JSON is valid before saving
        final decoded = jsonDecode(rawBody);
        if (decoded is List) {
          await prefs.setString(_cacheKey, rawBody);
          await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
          _parseCache(rawBody);
        }
      } else {
        debugPrint('[VcloudExtractor] GitHub API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('[VcloudExtractor] Refresh cache error: $e');
    }
  }

  /// Gets the remote JSON URL for a movie/series from the stream links database.
  Future<String?> getStreamJsonUrl({
    required int tmdbId,
    required String mediaType,
    required String title,
  }) async {
    await init();

    // 1. Try to guess the URL (works for 95% of cases)
    final sanitizedTitle = title
        .replaceAll(':', '-')
        .replaceAll('/', '-')
        .replaceAll('\\', '-')
        .replaceAll('*', '-')
        .replaceAll('?', '-')
        .replaceAll('"', '-')
        .replaceAll('<', '-')
        .replaceAll('>', '-')
        .replaceAll('|', '-')
        .trim();
    
    final type = mediaType == 'movie' ? 'movie' : 'series';
    final guessedName = Uri.encodeComponent('${sanitizedTitle}_${type}_$tmdbId.json');
    final guessedUrl = '$_rawBaseUrl/$guessedName';

    debugPrint('[VcloudExtractor] Guessed URL: $guessedUrl');

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final req = await client.headUrl(Uri.parse(guessedUrl));
      final resp = await req.close();
      client.close();
      if (resp.statusCode == 200) {
        debugPrint('[VcloudExtractor] Guessed URL exists (HTTP 200)');
        return guessedUrl;
      }
    } catch (_) {
      // Ignored, proceed to fallback lookup
    }

    // 2. Fallback: Lookup in the cached file map
    if (_fileMap.containsKey(tmdbId)) {
      final cachedUrl = _fileMap[tmdbId]!;
      debugPrint('[VcloudExtractor] Resolved URL from cache map: $cachedUrl');
      return cachedUrl;
    }

    debugPrint('[VcloudExtractor] Could not resolve stream JSON URL for ID: $tmdbId');
    return null;
  }

  /// Fetches the stream links file from GitHub and extracts direct URLs parallelly for all resolutions.
  ///
  /// Returns a Map: resolution -> { 'Server 1': url, 'Server 2': url, 'Server 3': url }
  Future<Map<String, Map<String, String>>> fetchStreamLinks({
    required int tmdbId,
    required String mediaType,
    required String title,
    int? season,
    int? episode,
  }) async {
    final Map<String, Map<String, String>> resolvedResMap = {};

    final jsonUrl = await getStreamJsonUrl(
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
    );

    if (jsonUrl == null) {
      debugPrint('[VcloudExtractor] Streaming database file not found.');
      return resolvedResMap;
    }

    try {
      debugPrint('[VcloudExtractor] Fetching streaming links file from: $jsonUrl');
      final response = await http.get(Uri.parse(jsonUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        debugPrint('[VcloudExtractor] Failed to fetch JSON: ${response.statusCode}');
        return resolvedResMap;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint('[VcloudExtractor] JSON loaded. post_title: ${data['post_title']}, post_type: ${data['post_type']}, tmdb_id: ${data['tmdb_id']}');
      final Map<String, String> vcloudLinksMap = {};

      debugPrint('[VcloudExtractor] Parameters received: mediaType=$mediaType, season=$season, episode=$episode');

      if (mediaType == 'movie') {
        // Movies: read from links
        final links = data['links'] as Map<String, dynamic>?;
        if (links != null) {
          for (var res in links.keys) {
            final itemsList = links[res] as List<dynamic>?;
            if (itemsList != null && itemsList.isNotEmpty) {
              final firstItem = itemsList.first as Map<String, dynamic>;
              final link = firstItem['link']?.toString() ?? '';
              if (link.isNotEmpty) {
                vcloudLinksMap[res] = link;
              }
            }
          }
        }
      } else {
        // TV Series: read from seasons
        final seasons = data['seasons'] as Map<String, dynamic>?;
        debugPrint('[VcloudExtractor] Seasons map is null? ${seasons == null}');
        if (seasons != null && season != null) {
          debugPrint('[VcloudExtractor] Seasons keys: ${seasons.keys.toList()}');
          final sKey = season.toString().padLeft(2, '0');
          debugPrint('[VcloudExtractor] Looking for season key: $sKey or ${season.toString()}');
          var seasonData = seasons[sKey] as Map<String, dynamic>?;
          if (seasonData == null) {
            seasonData = seasons[season.toString()] as Map<String, dynamic>?;
          }
          debugPrint('[VcloudExtractor] seasonData is null? ${seasonData == null}');
          if (seasonData != null) {
            final epNum = episode ?? 1;
            final targetTitlePadded = 'Episode ${epNum.toString().padLeft(2, '0')}';
            final targetTitleUnpadded = 'Episode $epNum';
            debugPrint('[VcloudExtractor] Looking for episode matching: "$targetTitlePadded" or "$targetTitleUnpadded"');
            for (var res in seasonData.keys) {
              final itemsList = seasonData[res] as List<dynamic>?;
              debugPrint('[VcloudExtractor] Resolution $res has items: $itemsList');
              if (itemsList != null) {
                final epMatch = itemsList.firstWhere(
                  (item) {
                    final title = item['episode_title']?.toString().toLowerCase() ?? '';
                    final match = title == targetTitlePadded.toLowerCase() ||
                           title == targetTitleUnpadded.toLowerCase();
                    debugPrint('[VcloudExtractor]   Comparing item episode_title: "$title" -> Match? $match');
                    return match;
                  },
                  orElse: () => null,
                );
                if (epMatch != null) {
                  final link = epMatch['link']?.toString() ?? '';
                  debugPrint('[VcloudExtractor]   Found link for resolution $res: $link');
                  if (link.isNotEmpty) {
                    vcloudLinksMap[res] = link;
                  }
                }
              }
            }
          }
        }
      }

      if (vcloudLinksMap.isEmpty) {
        debugPrint('[VcloudExtractor] No vcloud links found for the active item. vcloudLinksMap is empty.');
        return resolvedResMap;
      }

      // Parallelly extract direct streaming URLs from all resolutions
      final List<Future<void>> extractTasks = [];
      for (var entry in vcloudLinksMap.entries) {
        final res = entry.key; // e.g. "480p", "720p", "1080p"
        final vcloudUrl = entry.value;
        extractTasks.add(() async {
          debugPrint('[VcloudExtractor] Parallel extraction starting for resolution: $res');
          final resolvedServers = await extractVcloud(vcloudUrl);
          if (resolvedServers.isNotEmpty) {
            resolvedResMap[res] = resolvedServers;
            debugPrint('[VcloudExtractor] Resolved $res: ${resolvedServers.keys.join(", ")}');
          }
        }());
      }

      await Future.wait(extractTasks);
    } catch (e) {
      debugPrint('[VcloudExtractor] Error parsing streaming links JSON: $e');
    }

    return resolvedResMap;
  }

  /// Resolves the vcloud.zip page and extracts Server 1, Server 2, and Server 3 direct URLs.
  Future<Map<String, String>> extractVcloud(String vcloudUrl) async {
    final Map<String, String> resolved = {};
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..badCertificateCallback = (cert, host, port) => true;

    final headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };

    try {
      // Step 1: Fetch base page
      final req = await client.getUrl(Uri.parse(vcloudUrl));
      headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        client.close();
        return resolved;
      }
      final html = await resp.transform(utf8.decoder).join();

      // Step 2: Extract token URL
      final tokenRegExp = RegExp(r"var url\s*=\s*'(https?://[^'\s]+token=[^'\s]+)'");
      final match = tokenRegExp.firstMatch(html);
      if (match == null) {
        client.close();
        return resolved;
      }
      final tokenUrl = match.group(1)!;

      // Step 3: Fetch token page with Referer header
      final req2 = await client.getUrl(Uri.parse(tokenUrl));
      headers.forEach((k, v) => req2.headers.set(k, v));
      req2.headers.set('Referer', vcloudUrl);
      final resp2 = await req2.close();
      if (resp2.statusCode != 200) {
        client.close();
        return resolved;
      }
      final html2 = await resp2.transform(utf8.decoder).join();

      // Step 4: Parse all href links from token page
      final hrefRegExp = RegExp(r'''href=["']([^"']+)["']''');
      final matches = hrefRegExp.allMatches(html2);
      final hrefs = matches.map((m) => m.group(1)!).toList();

      // Step 5: Categorize and resolve links parallelly
      final List<Future<void>> resolveTasks = [];

      for (var href in hrefs) {
        if (href.contains('css') ||
            href.contains('fonts') ||
            href.contains('favicon') ||
            href.contains('manifest') ||
            href.contains('telegram') ||
            href == '#') {
          continue;
        }

        if (href.contains('hub.obsession.buzz') || href.contains('obsession.buzz')) {
          resolved['Server 1'] = href; // High-Speed Hub Link (Server 1)
        } else if (href.contains('r2.cloudflarestorage.com') || href.contains('r2.dev') || href.contains('.r2.')) {
          resolved['Server 3'] = href; // Cloudflare R2 Storage (Server 3)
        } else if (href.contains('hubcloud') || href.contains('gpdl')) {
          // Resolve Google Drive direct link via HubCloud redirection
          resolveTasks.add(() async {
            try {
              var currentUrl = href;
              var redirectCount = 0;
              String? finalUrl;
              final followClient = HttpClient()
                ..connectionTimeout = const Duration(seconds: 4)
                ..badCertificateCallback = (cert, host, port) => true;

              while (redirectCount < 5) {
                final hcReq = await followClient.getUrl(Uri.parse(currentUrl));
                headers.forEach((k, v) => hcReq.headers.set(k, v));
                hcReq.followRedirects = false;
                final hcResp = await hcReq.close();
                
                final loc = hcResp.headers.value('location');
                if (loc != null) {
                  if (loc.startsWith('http')) {
                    currentUrl = loc;
                  } else {
                    currentUrl = Uri.parse(currentUrl).resolve(loc).toString();
                  }
                  redirectCount++;
                } else {
                  finalUrl = currentUrl;
                  break;
                }
              }
              followClient.close();

              if (finalUrl != null) {
                final finalUri = Uri.parse(finalUrl);
                if (finalUri.queryParameters.containsKey('link')) {
                  resolved['Server 2'] = finalUri.queryParameters['link']!; // Google Drive (Server 2)
                } else {
                  final uri = Uri.parse(currentUrl);
                  if (uri.queryParameters.containsKey('link')) {
                    resolved['Server 2'] = uri.queryParameters['link']!; // Google Drive (Server 2)
                  }
                }
              }
            } catch (e) {
              debugPrint('[VcloudExtractor] Error resolving redirect for $href: $e');
            }
          }());
        }
      }

      await Future.wait(resolveTasks);
    } catch (e) {
      debugPrint('[VcloudExtractor] Error during vcloud extraction: $e');
    } finally {
      client.close();
    }

    return resolved;
  }
}
