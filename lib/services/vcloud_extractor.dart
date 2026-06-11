import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../data/services/database_sync_service.dart';
import '../domain/models/manifest_item.dart';

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

  // In-memory mapping of tmdbId/imdbId -> download_url
  final Map<String, String> _fileMap = {};
  bool _isInitialized = false;
  List<String> lastLanguages = [];

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
      final imdbRegExp = RegExp(r'(tt\d+)');
      for (var file in list) {
        if (file is Map) {
          final name = file['name']?.toString() ?? '';
          final downloadUrl = file['download_url']?.toString() ?? '';
          if (name.isNotEmpty && downloadUrl.isNotEmpty) {
            // Index by TMDB ID
            final matchTmdb = idRegExp.firstMatch(name);
            if (matchTmdb != null) {
              final id = int.tryParse(matchTmdb.group(1)!);
              if (id != null) {
                _fileMap['tmdb_$id'] = downloadUrl;
              }
            }
            // Index by IMDB ID
            final matchImdb = imdbRegExp.firstMatch(name);
            if (matchImdb != null) {
              final imdbId = matchImdb.group(1)!;
              _fileMap['imdb_$imdbId'] = downloadUrl;
            }
          }
        }
      }
      debugPrint('[VcloudExtractor] Loaded ${_fileMap.length} cache mappings.');
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
  /// Gets the remote JSON URL for a movie/series from the stream links database.
  Future<String?> getStreamJsonUrl({
    required int tmdbId,
    required String mediaType,
    required String title,
    int? season,
  }) async {
    await init();

    // Look up the content in the local manifest index to find the releaseYear and imdbId
    ManifestItem? dbItem;
    try {
      final items = await DatabaseSyncService.instance.loadLocalIndex();
      for (final item in items) {
        if (item.id == tmdbId) {
          dbItem = item;
          break;
        }
      }
    } catch (e) {
      debugPrint('[VcloudExtractor] Error loading local index: $e');
    }

    // 1. Direct Cache Lookup (Extremely robust & quick)
    final tmdbKey = 'tmdb_$tmdbId';
    if (_fileMap.containsKey(tmdbKey)) {
      final cachedUrl = _fileMap[tmdbKey]!;
      debugPrint('[VcloudExtractor] Resolved URL from cache map via TMDB ID: $cachedUrl');
      return cachedUrl;
    }

    if (dbItem?.imdbId != null) {
      final imdbKey = 'imdb_${dbItem!.imdbId}';
      if (_fileMap.containsKey(imdbKey)) {
        final cachedUrl = _fileMap[imdbKey]!;
        debugPrint('[VcloudExtractor] Resolved URL from cache map via IMDB ID: $cachedUrl');
        return cachedUrl;
      }
    }

    // 2. Forced Cache Refresh if not found (helps with newly added movies)
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastRefresh = prefs.getInt('vcloud_last_forced_refresh') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastRefresh > 60000) { // Limit force refresh to once per minute
        debugPrint('[VcloudExtractor] ID $tmdbId not found in cache. Forcing fresh list refresh...');
        await prefs.setInt('vcloud_last_forced_refresh', now);
        await _refreshCache(prefs);
        if (_fileMap.containsKey(tmdbKey)) {
          final cachedUrl = _fileMap[tmdbKey]!;
          debugPrint('[VcloudExtractor] Resolved URL after forced refresh via TMDB ID: $cachedUrl');
          return cachedUrl;
        }
        if (dbItem?.imdbId != null) {
          final imdbKey = 'imdb_${dbItem!.imdbId}';
          if (_fileMap.containsKey(imdbKey)) {
            final cachedUrl = _fileMap[imdbKey]!;
            debugPrint('[VcloudExtractor] Resolved URL after forced refresh via IMDB ID: $cachedUrl');
            return cachedUrl;
          }
        }
      }
    } catch (e) {
      debugPrint('[VcloudExtractor] Error during forced cache refresh: $e');
    }

    // 3. Fallback: Guess the URL patterns (useful as final fallback)
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
    
    final releaseYear = dbItem?.releaseYear;
    final List<String> guessedNames = [];
    if (mediaType == 'movie') {
      if (releaseYear != null) {
        guessedNames.add('${sanitizedTitle} (${releaseYear})_movie_$tmdbId.json');
      }
      guessedNames.add('${sanitizedTitle}_movie_$tmdbId.json');
    } else {
      final sNum = season ?? 1;
      if (releaseYear != null) {
        guessedNames.add('${sanitizedTitle} (Season $sNum) (${releaseYear})_series_$tmdbId.json');
      }
      guessedNames.add('${sanitizedTitle} (Season $sNum)_series_$tmdbId.json');
      guessedNames.add('${sanitizedTitle}_series_$tmdbId.json');
    }

    for (final name in guessedNames) {
      final encodedName = Uri.encodeComponent(name);
      final guessedUrl = '$_rawBaseUrl/$encodedName';
      debugPrint('[VcloudExtractor] Checking guessed URL fallback: $guessedUrl');
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
        final req = await client.headUrl(Uri.parse(guessedUrl));
        final resp = await req.close();
        client.close();
        if (resp.statusCode == 200) {
          debugPrint('[VcloudExtractor] Guessed URL fallback exists: $guessedUrl');
          return guessedUrl;
        }
      } catch (_) {
        // Ignored
      }
    }

    debugPrint('[VcloudExtractor] Could not resolve stream JSON URL for ID: $tmdbId');
    return null;
  }

  /// Fetches the stream JSON URL and parses the available resolution mapping (resolution -> vcloudUrl).
  ///
  /// Returns a Map: resolution -> vcloudUrl (zip page URL)
  Future<Map<String, String>> fetchResolutionLinksMap({
    required int tmdbId,
    required String mediaType,
    required String title,
    int? season,
    int? episode,
  }) async {
    final Map<String, String> vcloudLinksMap = {};

    final jsonUrl = await getStreamJsonUrl(
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      season: season,
    );

    if (jsonUrl == null) {
      debugPrint('[VcloudExtractor] Streaming database file not found.');
      return vcloudLinksMap;
    }

    try {
      debugPrint('[VcloudExtractor] Fetching streaming links file from: $jsonUrl');
      final response = await http.get(Uri.parse(jsonUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        debugPrint('[VcloudExtractor] Failed to fetch JSON: ${response.statusCode}');
        return vcloudLinksMap;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint('[VcloudExtractor] JSON loaded. post_title: ${data['post_title']}, post_type: ${data['post_type']}, tmdb_id: ${data['tmdb_id']}');
      if (data.containsKey('languages') && data['languages'] is List) {
        lastLanguages = (data['languages'] as List).map((e) => e.toString()).toList();
        debugPrint('[VcloudExtractor] Languages parsed: $lastLanguages');
      } else {
        lastLanguages = [];
      }

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
    } catch (e) {
      debugPrint('[VcloudExtractor] Error parsing streaming links JSON: $e');
    }

    return vcloudLinksMap;
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

    final vcloudLinksMap = await fetchResolutionLinksMap(
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      season: season,
      episode: episode,
    );

    if (vcloudLinksMap.isEmpty) {
      return resolvedResMap;
    }

    try {
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

  /// Helper to parse download server links from page HTML.
  Map<String, String> _parseServerLinks(String html) {
    final Map<String, String> resolved = {};
    final aTagRegExp = RegExp(r'<a\s+([^>]+)>(.*?)</a>', caseSensitive: false, dotAll: true);
    final hrefAttrRegExp = RegExp(r'''href=["']([^"']+)["']''', caseSensitive: false);
    final idAttrRegExp = RegExp(r'''id=["']([^"']+)["']''', caseSensitive: false);
    
    final matches = aTagRegExp.allMatches(html);

    // List of known ad, betting, shortener keywords to ignore in URL
    const List<String> adKeywords = [
      'bit.ly', 'tinyurl', 'cutt.ly', 'linkvertise', 'adf.ly', 'shorturl',
      'doubleclick', 'popads', 'onclickads', 'exoclick', 'adsterra', 'adlink',
      'winexch', 'lotus', 'bet', 'casino', '1xbet', 'mostbet', 'parimatch',
      'melbet', 'dafanews', 'sportybet', 'betway', 'bet365', 'adsystem',
      'adservices', 'googlesyndication', 'googleadservices'
    ];

    for (var match in matches) {
      final attributes = match.group(1)!;
      final innerHtml = match.group(2) ?? '';
      
      final hrefMatch = hrefAttrRegExp.firstMatch(attributes);
      if (hrefMatch == null) continue;
      
      final href = hrefMatch.group(1)!;
      if (href == '#' || href.isEmpty) continue;
      
      // Exclude irrelevant links and ad keywords
      final hrefLower = href.toLowerCase();
      if (hrefLower.contains('css') || 
          hrefLower.contains('fonts') || 
          hrefLower.contains('favicon') || 
          hrefLower.contains('manifest') || 
          hrefLower.contains('telegram') || 
          hrefLower.contains('t.me') || 
          hrefLower.contains('google.com') ||
          hrefLower.contains('github.com') ||
          hrefLower.contains('admin') ||
          hrefLower.contains('login') ||
          hrefLower.contains('signup') ||
          hrefLower.contains('sign-up') ||
          hrefLower.contains('create') ||
          hrefLower.contains('account') ||
          hrefLower.contains('hubcloud.php')) {
        continue;
      }

      bool isAd = false;
      for (final keyword in adKeywords) {
        if (hrefLower.contains(keyword)) {
          isAd = true;
          break;
        }
      }
      if (isAd) {
        debugPrint('[VcloudExtractor] Skipping parsed ad link: $href');
        continue;
      }

      final idMatch = idAttrRegExp.firstMatch(attributes);
      final id = idMatch?.group(1) ?? '';

      // Specific matched servers based on known attributes/text
      if (id == 'fsl' || innerHtml.contains('[FSL Server]')) {
        final minutes = DateTime.now().minute;
        resolved['Server 1'] = href.contains('X-Amz-Signature') || href.contains('r2.cloudflarestorage') || href.contains('r2.dev')
            ? href
            : href + '1$minutes';
      } else if (id == 's3' || innerHtml.contains('[FSLv2 Server]')) {
        final minutes2 = DateTime.now().minute;
        resolved['Server 2'] = href.contains('X-Amz-Signature') || href.contains('r2.cloudflarestorage') || href.contains('r2.dev')
            ? href
            : href + '1$minutes2';
      } else if (innerHtml.contains('[Server : 10Gbps]') || 
                 (href.contains('hubcloud') && (href.contains('id=') || href.contains('/tg/'))) || 
                 href.contains('gpdl') ||
                 href.contains('gamerxyt') ||
                 (attributes.contains('btn-danger') && 
                  (href.contains('hubcloud') || 
                   href.contains('gpdl') || 
                   href.contains('gamerxyt') || 
                   href.contains('vcloud') || 
                   href.contains('gofile') || 
                   href.contains('pixeldrain') || 
                   href.contains('cloudflarestorage') || 
                   href.contains('auvps')))) {
        resolved['Server 3'] = href;
      } else if ((attributes.toLowerCase().contains('btn') || innerHtml.toLowerCase().contains('server')) && href.contains('token=')) {
        if (!resolved.containsKey('Server 1')) {
          resolved['Server 1'] = href;
        } else if (!resolved.containsKey('Server 2')) {
          resolved['Server 2'] = href;
        } else if (!resolved.containsKey('Server 3')) {
          resolved['Server 3'] = href;
        }
      }
    }

    return resolved;
  }

  /// Resolves the page (vcloud/hubcloud/etc.) and extracts Server 1, Server 2, and Server 3 direct URLs.
  Future<Map<String, String>> extractVcloud(String vcloudUrl) async {
    final Map<String, String> resolved = {};
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
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

      // Step 2: Try to parse server links directly from the first page (in case it is already pre-generated)
      final directServers = _parseServerLinks(html);
      if (directServers.containsKey('Server 1') || directServers.containsKey('Server 2') || directServers.containsKey('Server 3')) {
        debugPrint('[VcloudExtractor] Found server links directly on the initial page.');
        return directServers;
      }

      // Step 3: Extract token URL from JS variable or download buttons
      String? tokenUrl;

      // Try 3a: Extract from JS variable var url = '...' or var url = "..."
      final varUrlRegExp = RegExp(r'''var\s+url\s*=\s*['"](https?://[^'"]+)['"]''', caseSensitive: false);
      final varUrlMatch = varUrlRegExp.firstMatch(html);
      if (varUrlMatch != null) {
        tokenUrl = varUrlMatch.group(1);
        debugPrint('[VcloudExtractor] Extracted token URL from JS variable: $tokenUrl');
      }

      // Try 3b: Extract from anchor tag with id="download" or containing text "generate"
      if (tokenUrl == null) {
        final aTagRegExp = RegExp(r'<a\s+([^>]+)>(.*?)</a>', caseSensitive: false, dotAll: true);
        final hrefAttrRegExp = RegExp(r'''href=["']([^"']+)["']''', caseSensitive: false);
        final idAttrRegExp = RegExp(r'''id=["']([^"']+)["']''', caseSensitive: false);
        
        final matches = aTagRegExp.allMatches(html);
        for (var match in matches) {
          final attributes = match.group(1)!;
          final innerHtml = match.group(2) ?? '';
          
          final idMatch = idAttrRegExp.firstMatch(attributes);
          final id = idMatch?.group(1) ?? '';
          
          if (id == 'download' || 
              innerHtml.toLowerCase().contains('generate direct download') || 
              innerHtml.toLowerCase().contains('generate download')) {
            final hrefMatch = hrefAttrRegExp.firstMatch(attributes);
            if (hrefMatch != null) {
              final href = hrefMatch.group(1)!;
              if (href.isNotEmpty && href.startsWith('http')) {
                tokenUrl = href;
                debugPrint('[VcloudExtractor] Extracted token URL from download button: $tokenUrl');
                break;
              }
            }
          }
        }
      }

      if (tokenUrl == null) {
        debugPrint('[VcloudExtractor] Could not locate token URL or download button on main page.');
        client.close();
        return resolved;
      }

      // Step 4: Fetch token page with Referer header
      final req2 = await client.getUrl(Uri.parse(tokenUrl));
      headers.forEach((k, v) => req2.headers.set(k, v));
      req2.headers.set('Referer', vcloudUrl);
      final resp2 = await req2.close();
      if (resp2.statusCode != 200) {
        client.close();
        return resolved;
      }
      final html2 = await resp2.transform(utf8.decoder).join();

      // Step 5: Parse server links from token page HTML
      return _parseServerLinks(html2);

    } catch (e) {
      debugPrint('[VcloudExtractor] Error during vcloud extraction: $e');
    } finally {
      client.close();
    }

    return resolved;
  }

  /// Resolves GPDL / HubCloud redirect URL dynamically checking for 'link=' at each hop.
  Future<String?> resolveHubCloudRedirect(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..badCertificateCallback = (cert, host, port) => true;

    final headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };

    try {
      var currentUrl = url;
      var redirectCount = 0;

      while (redirectCount < 8) {
        // Quick check: if the URL itself contains '?link=' or '&link=', capture the direct video link immediately!
        final uri = Uri.parse(currentUrl);
        if (uri.queryParameters.containsKey('link')) {
          final directLink = uri.queryParameters['link']!;
          debugPrint('[VcloudExtractor] Captured direct link dynamically at hop $redirectCount: $directLink');
          return directLink;
        }

        final req = await client.getUrl(Uri.parse(currentUrl));
        headers.forEach((k, v) => req.headers.set(k, v));
        req.followRedirects = false;
        final resp = await req.close();

        final loc = resp.headers.value('location');
        if (loc != null) {
          if (loc.startsWith('http')) {
            currentUrl = loc;
          } else {
            currentUrl = Uri.parse(currentUrl).resolve(loc).toString();
          }
          redirectCount++;
        } else {
          break;
        }
      }

      // Final URL query parameter check
      final uri = Uri.parse(currentUrl);
      if (uri.queryParameters.containsKey('link')) {
        final directLink = uri.queryParameters['link']!;
        debugPrint('[VcloudExtractor] Captured direct link from final redirect URL: $directLink');
        return directLink;
      }
    } catch (e) {
      debugPrint('[VcloudExtractor] Error resolving HubCloud redirect: $e');
    } finally {
      client.close();
    }
    return null;
  }

  /// Checks if the direct link is playable by sending a quick HEAD request (2s timeout).
  /// Verifies that the status code is < 400 and the Content-Type starts with 'video/' or is HLS/media format.
  Future<bool> verifyDirectLink(String url) async {
    if (url.isEmpty || !url.startsWith('http')) return false;

    // Filter out obvious ad/shortener/betting URLs before doing a network request
    final lowerUrl = url.toLowerCase();
    const List<String> adKeywords = [
      'bit.ly', 'tinyurl', 'cutt.ly', 'linkvertise', 'adf.ly', 'shorturl',
      'doubleclick', 'popads', 'onclickads', 'exoclick', 'adsterra', 'adlink',
      'winexch', 'lotus', 'bet', 'casino', '1xbet', 'mostbet', 'parimatch',
      'melbet', 'dafanews', 'sportybet', 'betway', 'bet365', 'adsystem',
      'adservices', 'googlesyndication', 'googleadservices'
    ];

    for (final keyword in adKeywords) {
      if (lowerUrl.contains(keyword)) {
        debugPrint('[VcloudExtractor] Rejecting known ad/shortener/betting link pattern: $url');
        return false;
      }
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..badCertificateCallback = (cert, host, port) => true;

    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      req.headers.set('Range', 'bytes=0-1024');
      final resp = await req.close();
      
      // Abort downloading the rest of the stream immediately
      try {
        await resp.listen((_) {}).cancel();
      } catch (_) {}
      client.close();

      if (resp.statusCode >= 400 && resp.statusCode != 206) {
        debugPrint('[VcloudExtractor] Direct link returned failure status: ${resp.statusCode}');
        return false;
      }

      final contentType = resp.headers.value('content-type')?.toLowerCase() ?? '';
      
      // If the content type is HTML/Text, it is NOT a playable raw video file/stream.
      // (Exception: HLS playlists are sometimes served as text/plain or similar, so check extension)
      if (contentType.contains('html') || contentType.contains('text/')) {
        if (!contentType.contains('mpegurl') && !contentType.contains('mpeg-url') && !url.toLowerCase().contains('.m3u8')) {
          debugPrint('[VcloudExtractor] Rejecting link due to non-video HTML/Text content type: $contentType');
          return false;
        }
      }

      final isPlayable = contentType.startsWith('video/') ||
          contentType.contains('mpegurl') ||
          contentType.contains('application/octet-stream') ||
          url.toLowerCase().contains('.mkv') ||
          url.toLowerCase().contains('.mp4') ||
          url.toLowerCase().contains('.m3u8') ||
          url.toLowerCase().contains('googleusercontent') ||
          url.toLowerCase().contains('r2.cloudflarestorage') ||
          url.toLowerCase().contains('r2.dev');
      
      debugPrint('[VcloudExtractor] Verification result for $url: $isPlayable (type: $contentType)');
      return isPlayable;
    } catch (e) {
      debugPrint('[VcloudExtractor] Verification exception for $url: $e');
      client.close();
      return false;
    }
  }
}

