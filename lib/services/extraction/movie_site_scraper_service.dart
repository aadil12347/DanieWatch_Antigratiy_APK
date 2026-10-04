import 'dart:convert';
import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/manifest_item.dart';
import '../../data/clients/tmdb_client.dart';

class ScrapedSiteCard {
  final String site; // 'vegamovies' | 'rogmovies'
  final String postUrl;
  final String posterUrl;
  final String title;
  final double rating;
  final DateTime? datePublished;

  ScrapedSiteCard({
    required this.site,
    required this.postUrl,
    required this.posterUrl,
    required this.title,
    this.rating = 7.0,
    this.datePublished,
  });
}

class MovieSiteScraperService {
  MovieSiteScraperService._();
  static final MovieSiteScraperService instance = MovieSiteScraperService._();

  static const String vegaBaseUrl = 'https://vegamovies.gallery';
  static const String rogBaseUrl = 'https://rogmovies.best';

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    },
    followRedirects: true,
    maxRedirects: 5,
  ));

  static const String edgeWorkerUrl = String.fromEnvironment('EDGE_WORKER_URL', defaultValue: '');
  static const String _diskCacheKeyHome = 'daniewatch_scraped_home_v1';
  static const String _diskCacheKeyCategories = 'daniewatch_scraped_cats_v1';
  static const Duration _staleDuration = Duration(minutes: 5);

  bool _isDiskCacheLoaded = false;
  bool get isDiskCacheLoaded => _isDiskCacheLoaded;
  DateTime? _lastHomeFetchTime;
  DateTime? _lastCategoryFetchTime;
  /// Callback invoked when background refresh completes with fresh data.
  /// Set by the provider layer to trigger UI rebuilds.
  void Function()? onHomeRefreshed;
  void Function()? onCategoriesRefreshed;

  // Cache in-memory for live session
  List<ManifestItem>? _cachedCarousel;
  List<ManifestItem>? _cachedTop10Indian;
  List<ManifestItem>? _cachedTop10HindiDub;
  Future<Map<String, List<ManifestItem>>>? _pendingTopLists;
  final Map<String, Future<List<ManifestItem>>> _pendingCategoryPages = {};
  final Map<String, List<ManifestItem>> _categoryPageCache = {};
  final Map<String, ManifestItem> _itemMap = {};
  final Map<String, String> _postUrlMap = {};
  final Map<String, String> _postImdbCache = {};
  final Map<int, int> _resolvedTmdbIds = {};
  final Map<int, String> _resolvedMediaTypes = {};

  final Map<String, int> _categoryTotalPages = {
    'dual-audio': 778,
    'dualaudio': 778,
    'indian': 392,
    'bollywood': 392,
    'all': 778,
    'explore': 778,
    'search': 778,
    'korean': 160,
    'k-drama': 160,
    'kdrama': 160,
    'chinese': 80,
    'anime': 95,
    'hollywood': 350,
    'punjabi': 45,
    'pakistani': 35,
    'action': 320,
    'sci-fi': 180,
    'scifi': 180,
    'comedy': 260,
    'thriller': 290,
    'horror': 170,
    'romance': 190,
    'adventure': 210,
    'crime': 180,
    'drama': 350,
    'mystery': 140,
    'fantasy': 160,
    'animation': 120,
  };

  /// Returns total pagination pages for a category tab (defaults to verified baseline)
  int getTotalPages(String categorySlug) {
    final key = categorySlug.toLowerCase().trim();
    return _categoryTotalPages[key] ?? 100;
  }

  /// Live fetches total page counts from Typesense instantly on app startup
  Future<void> fetchLiveTotalPages() async {
    try {
      final results = await Future.wait([
        _dio
            .get<String>(
              '$vegaBaseUrl/ts-search.php?q=&page=1',
              options: Options(responseType: ResponseType.plain),
            )
            .then((r) => r.data)
            .catchError((_) => null),
        _dio
            .get<String>(
              '$rogBaseUrl/ts-search.php?q=&page=1',
              options: Options(responseType: ResponseType.plain),
            )
            .then((r) => r.data)
            .catchError((_) => null),
      ]);

      if (results[0] != null && results[0]!.isNotEmpty) {
        final data = jsonDecode(results[0]!) as Map<String, dynamic>;
        final found = (data['found'] as num?)?.toInt() ?? 0;
        if (found > 0) {
          final pages = (found / 18).ceil();
          _categoryTotalPages['dual-audio'] = pages;
          _categoryTotalPages['dualaudio'] = pages;
          _categoryTotalPages['all'] = pages;
          _categoryTotalPages['explore'] = pages;
          _categoryTotalPages['search'] = pages;
          dev.log('[MovieSiteScraperService] Live Vega total pages: $pages ($found posts)');
        }
      }

      if (results[1] != null && results[1]!.isNotEmpty) {
        final data = jsonDecode(results[1]!) as Map<String, dynamic>;
        final found = (data['found'] as num?)?.toInt() ?? 0;
        if (found > 0) {
          final pages = (found / 20).ceil();
          _categoryTotalPages['indian'] = pages;
          _categoryTotalPages['bollywood'] = pages;
          dev.log('[MovieSiteScraperService] Live Rog total pages: $pages ($found posts)');
        }
      }
    } catch (e) {
      dev.log('[MovieSiteScraperService] Error live fetching total pages: $e');
    }
  }

  void registerResolvedTmdb(int fastId, int tmdbId, String mediaType) {
    _resolvedTmdbIds[fastId] = tmdbId;
    _resolvedMediaTypes[fastId] = mediaType;
  }

  int getResolvedTmdbId(int fastId) => _resolvedTmdbIds[fastId] ?? fastId;
  String getResolvedMediaType(int fastId, String fallback) =>
      _resolvedMediaTypes[fastId] ?? fallback;

  String? getPostUrl(dynamic fastId) => _postUrlMap[fastId?.toString() ?? ''];

  void setPostUrl(dynamic fastId, String postUrl) {
    if (fastId != null && postUrl.isNotEmpty) {
      _postUrlMap[fastId.toString()] = postUrl;
    }
  }

  /// Fetches IMDb ID from a post's detail page (e.g., https://vegamovies.gallery/...)
  Future<String?> fetchImdbIdFromPostUrl(String postUrl) async {
    if (postUrl.isEmpty) return null;
    if (_postImdbCache.containsKey(postUrl)) {
      return _postImdbCache[postUrl];
    }

    try {
      final html = await fetchHtml(postUrl);
      if (html == null || html.isEmpty) return null;

      // 1. Direct IMDb link: imdb.com/title/(tt\d+)
      final imdbLinkRegex = RegExp(r'imdb\.com/title/(tt\d+)', caseSensitive: false);
      final linkMatch = imdbLinkRegex.firstMatch(html);
      if (linkMatch != null) {
        final id = linkMatch.group(1)!;
        _postImdbCache[postUrl] = id;
        return id;
      }

      // 2. Look for tt ID near "imdb" or "rating"
      final imdbBlockRegex = RegExp(r'imdb[\s\S]{1,100}?(tt\d{6,10})', caseSensitive: false);
      final blockMatch = imdbBlockRegex.firstMatch(html);
      if (blockMatch != null) {
        final id = blockMatch.group(1)!;
        _postImdbCache[postUrl] = id;
        return id;
      }

      // 3. Fallback: Any tt\d{6,10} pattern in HTML
      final ttRegex = RegExp(r'\b(tt\d{6,10})\b', caseSensitive: false);
      final ttMatch = ttRegex.firstMatch(html);
      if (ttMatch != null) {
        final id = ttMatch.group(1)!;
        _postImdbCache[postUrl] = id;
        return id;
      }
    } catch (e) {
      dev.log('[MovieSiteScraperService] Failed to extract IMDb from $postUrl: $e');
    }
    return null;
  }

  Map<String, ManifestItem> get itemMap => _itemMap;
  bool get hasMemoryCache => _cachedTop10Indian != null && _cachedTop10HindiDub != null;
  List<ManifestItem>? get cachedTop10Indian => _cachedTop10Indian;
  List<ManifestItem>? get cachedTop10HindiDub => _cachedTop10HindiDub;
  List<ManifestItem>? get cachedCarousel => _cachedCarousel;
  List<ManifestItem>? getCachedCategory(String key) =>
      _categoryPageCache['${key.toLowerCase().trim()}_page_1'];

  static final RegExp _excludedShowPatterns = RegExp(
    r'roadies|bigg?\s*boss|dance\s*master|hustle|top\s*1\s*%|top\s*1\s*percent|sa\s*re\s*ga\s*ma|sare\s*gama|best\s*dancer|beat\s*dancer|khatron\s*ke\s*khiladi|got\s*latent|kapil\s*show|reality|tv-show|rise\s*and\s*fall|family\s*full\s*house|indian\s*idol|splitsvilla|super\s*singer|masterchef|voice\s*of\s*india|jhalak\s*dikhhla\s*jaa|nach\s*baliye|comedy\s*circus|laughter\s*challenge|fear\s*factor|lock\s*upp|temptation\s*island|talent\s*hunt|competition',
    caseSensitive: false,
  );

  static bool isExcludedShow(String title) {
    return _excludedShowPatterns.hasMatch(title);
  }

  static bool isExcludedIndianShow(String title) => isExcludedShow(title);

  /// Loads cached home sections from local disk into memory in <2ms.
  Future<void> loadDiskCache() async {
    if (_isDiskCacheLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawHome = prefs.getString(_diskCacheKeyHome);
      if (rawHome != null && rawHome.isNotEmpty) {
        final data = jsonDecode(rawHome) as Map<String, dynamic>;
        if (data['top10Indian'] is List) {
          _cachedTop10Indian = (data['top10Indian'] as List)
              .map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
              .toList();
          for (final item in _cachedTop10Indian!) {
            _itemMap[item.id.toString()] = item;
          }
        }
        if (data['top10HindiDub'] is List) {
          _cachedTop10HindiDub = (data['top10HindiDub'] as List)
              .map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
              .toList();
          for (final item in _cachedTop10HindiDub!) {
            _itemMap[item.id.toString()] = item;
          }
        }
        if (data['carousel'] is List) {
          _cachedCarousel = (data['carousel'] as List)
              .map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
              .toList();
          for (final item in _cachedCarousel!) {
            _itemMap[item.id.toString()] = item;
          }
        }
      }

      final rawCats = prefs.getString(_diskCacheKeyCategories);
      if (rawCats != null && rawCats.isNotEmpty) {
        final data = jsonDecode(rawCats) as Map<String, dynamic>;
        for (final entry in data.entries) {
          if (entry.value is List) {
            final items = (entry.value as List)
                .map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
                .toList();
            _categoryPageCache['${entry.key}_page_1'] = items;
            for (final item in items) {
              _itemMap[item.id.toString()] = item;
            }
          }
        }
      }
      _isDiskCacheLoaded = true;
      dev.log('[MovieSiteScraperService] Loaded disk cache (instant 0ms ready)');
    } catch (e) {
      dev.log('[MovieSiteScraperService] Error reading disk cache: $e');
    }
  }

  /// Saves current scraped items to local disk for 0ms startup on next launch.
  Future<void> saveDiskCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_cachedTop10Indian != null && _cachedTop10HindiDub != null) {
        final homeData = {
          'top10Indian': _cachedTop10Indian!.map((e) => e.toJson()).toList(),
          'top10HindiDub': _cachedTop10HindiDub!.map((e) => e.toJson()).toList(),
          'carousel': (_cachedCarousel ?? _cachedTop10Indian!).map((e) => e.toJson()).toList(),
          'timestamp': DateTime.now().toIso8601String(),
        };
        await prefs.setString(_diskCacheKeyHome, jsonEncode(homeData));
      }

      if (_categoryPageCache.isNotEmpty) {
        final catData = <String, dynamic>{};
        for (final entry in _categoryPageCache.entries) {
          if (entry.key.endsWith('_page_1')) {
            final catName = entry.key.replaceAll('_page_1', '');
            catData[catName] = entry.value.map((e) => e.toJson()).toList();
          }
        }
        await prefs.setString(_diskCacheKeyCategories, jsonEncode(catData));
      }
    } catch (e) {
      dev.log('[MovieSiteScraperService] Error saving disk cache: $e');
    }
  }

  void clearCache() {
    _cachedCarousel = null;
    _cachedTop10Indian = null;
    _cachedTop10HindiDub = null;
    _pendingTopLists = null;
    _pendingCategoryPages.clear();
    _categoryPageCache.clear();
    _itemMap.clear();
    _postUrlMap.clear();
    _postImdbCache.clear();
    _resolvedTmdbIds.clear();
    _resolvedMediaTypes.clear();
    _lastHomeFetchTime = null;
    _lastCategoryFetchTime = null;
  }

  /// Clears both in-memory AND on-disk caches so next launch fetches fresh.
  Future<void> clearDiskCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_diskCacheKeyHome);
      await prefs.remove(_diskCacheKeyCategories);
    } catch (e) {
      dev.log('[MovieSiteScraperService] Error clearing disk cache: $e');
    }
  }

  /// Whether the home cache is stale and needs a background refresh.
  bool get isHomeCacheStale {
    if (_lastHomeFetchTime == null) return true;
    return DateTime.now().difference(_lastHomeFetchTime!) > _staleDuration;
  }

  /// Whether category caches are stale.
  bool get isCategoryCacheStale {
    if (_lastCategoryFetchTime == null) return true;
    return DateTime.now().difference(_lastCategoryFetchTime!) > _staleDuration;
  }

  /// Clean post title
  static String cleanTitle(String rawTitle) {
    return rawTitle
        .replaceAll(RegExp(r'&#038;', caseSensitive: false), '&')
        .replaceAll(RegExp(r'&amp;', caseSensitive: false), '&')
        .replaceAll(RegExp(r'&#8211;', caseSensitive: false), '-')
        .replaceAll(RegExp(r'&#8217;', caseSensitive: false), "'")
        .replaceAll(RegExp(r'&quot;', caseSensitive: false), '"')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Extracts pure title stripped of clutter (e.g. "Slow Horses", "The Punisher").
  static String extractPureTitle(String raw) {
    return ManifestItem.cleanPostTitle(raw);
  }

  /// Extract poster cards from VegaMovies / RogMovies HTML
  static List<ScrapedSiteCard> parseCards(String html, String site) {
    final cards = <ScrapedSiteCard>[];
    final seenUrls = <String>{};

    // Robust card regex: matches each <div class="poster-card" block cleanly
    final cardRegex = RegExp(
      r'<div class="poster-card"[^>]*>([\s\S]*?)(?=<div class="poster-card"|<\/section>|<\/main>|<nav class="pagination"|$)',
      caseSensitive: false,
    );

    final urlRegex = RegExp(
      r'<meta itemprop="url" content="([^"]+)"|href="([^"]+)"',
      caseSensitive: false,
    );
    final imgRegex = RegExp(
      r'<img[^>]+(?:src|data-src)="([^"]+)"',
      caseSensitive: false,
    );
    final altRegex = RegExp(
      r'alt="([^"]+)"',
      caseSensitive: false,
    );
    final titleTagRegex = RegExp(
      r'class="poster-title"[^>]*>([\s\S]*?)<\/(?:p|div|h\d)>',
      caseSensitive: false,
    );
    final rateRegex = RegExp(
      r'itemprop="ratingValue" content="([^"]+)"|imdb-score[^>]*>[^\d]*(\d+\.?\d*)',
      caseSensitive: false,
    );
    final timeRegex = RegExp(
      r'<time[^>]*datetime="([^"]+)"',
      caseSensitive: false,
    );

    for (final match in cardRegex.allMatches(html)) {
      final block = match.group(1) ?? '';
      final urlM = urlRegex.firstMatch(block);
      final postUrl = urlM?.group(1) ?? urlM?.group(2);
      if (postUrl == null || postUrl.isEmpty || seenUrls.contains(postUrl)) continue;

      final imgM = imgRegex.firstMatch(block);
      final altM = altRegex.firstMatch(block);
      final titleTagM = titleTagRegex.firstMatch(block);
      final rateM = rateRegex.firstMatch(block);
      final timeM = timeRegex.firstMatch(block);

      String rawTitle = '';
      if (titleTagM != null) {
        rawTitle = titleTagM.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      }
      if (rawTitle.isEmpty && altM != null) {
        rawTitle = altM.group(1)!;
      }
      final title = cleanTitle(rawTitle);
      if (title.length < 2) continue;

      final poster = imgM?.group(1) ?? '';
      final ratingVal = rateM?.group(1) ?? rateM?.group(2);
      final rating = ratingVal != null ? double.tryParse(ratingVal) ?? 7.2 : 7.2;

      DateTime? datePublished;
      if (timeM != null) {
        datePublished = DateTime.tryParse(timeM.group(1)!);
      }

      seenUrls.add(postUrl);
      cards.add(ScrapedSiteCard(
        site: site,
        postUrl: postUrl,
        posterUrl: poster,
        title: title,
        rating: rating,
        datePublished: datePublished,
      ));
    }

    return cards;
  }

  /// Parse Typesense JSON hits from VegaMovies / RogMovies
  static List<ScrapedSiteCard> parseTsCards(String? jsonStr, String site, String baseUrl) {
    final cards = <ScrapedSiteCard>[];
    if (jsonStr == null || jsonStr.isEmpty) return cards;
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final hits = data['hits'] as List?;
      if (hits != null) {
        for (final hit in hits) {
          final doc = hit['document'] as Map<String, dynamic>?;
          if (doc != null) {
            final title = doc['post_title']?.toString() ?? '';
            final permalink = doc['permalink']?.toString() ?? '';
            final thumb =
                (doc['post_thumbnail'] ?? doc['thumb'])?.toString() ?? '';
            final fullUrl = permalink.startsWith('http')
                ? permalink
                : '$baseUrl$permalink';

            DateTime? datePublished;
            final sortByDate = doc['sort_by_date'];
            if (sortByDate is num && sortByDate > 0) {
              datePublished = DateTime.fromMillisecondsSinceEpoch(
                  sortByDate.toInt() * 1000);
            } else if (doc['post_date'] != null) {
              datePublished = DateTime.tryParse(doc['post_date'].toString());
            }

            if (title.isNotEmpty &&
                fullUrl.isNotEmpty &&
                !isExcludedIndianShow(title)) {
              cards.add(ScrapedSiteCard(
                site: site,
                postUrl: fullUrl,
                posterUrl: thumb,
                title: cleanTitle(title),
                datePublished: datePublished,
              ));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[MovieSiteScraperService] TS parse error ($site): $e');
    }
    return cards;
  }

  /// Query Typesense search across Vegamovies and/or Rogmovies
  Future<List<ScrapedSiteCard>> _fetchTypesenseCards(
    String query, {
    int page = 1,
    String? site, // 'vegamovies' | 'rogmovies' | null (both)
  }) async {
    final cleanQ = Uri.encodeComponent(query);
    final cards = <ScrapedSiteCard>[];
    try {
      final futures = <Future<String?>>[];
      if (site == null || site == 'vegamovies') {
        futures.add(
          _dio
              .get<String>(
                '$vegaBaseUrl/ts-search.php?q=$cleanQ&page=$page',
                options: Options(responseType: ResponseType.plain),
              )
              .then((r) => r.data)
              .catchError((_) => null),
        );
      } else {
        futures.add(Future.value(null));
      }

      if (site == null || site == 'rogmovies') {
        futures.add(
          _dio
              .get<String>(
                '$rogBaseUrl/ts-search.php?q=$cleanQ&page=$page',
                options: Options(responseType: ResponseType.plain),
              )
              .then((r) => r.data)
              .catchError((_) => null),
        );
      } else {
        futures.add(Future.value(null));
      }

      final results = await Future.wait(futures);
      if (results[0] != null) cards.addAll(parseTsCards(results[0], 'vegamovies', vegaBaseUrl));
      if (results[1] != null) cards.addAll(parseTsCards(results[1], 'rogmovies', rogBaseUrl));
    } catch (e) {
      debugPrint('[MovieSiteScraperService] TS fetch error ($query): $e');
    }
    return cards;
  }

  /// Fetch HTML with direct fetch first (fast, ~400-1200ms)
  static Future<String?> fetchHtml(String url) async {
    try {
      final res = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      if (res.statusCode == 200 && res.data != null && res.data!.isNotEmpty) {
        return res.data;
      }
    } catch (e) {
      debugPrint('[MovieSiteScraperService] Fetch failed for $url: $e');
    }
    return null;
  }

  /// Converts a ScrapedSiteCard instantly (0ms) into a ManifestItem using parsed HTML attributes.
  /// Zero blocking network calls: displays titles and UI immediately, allowing images to load smoothly.
  ManifestItem createFastManifestItem(
    ScrapedSiteCard card, {
    bool isTrending = false,
    int? trendingRank,
    Map<String, ManifestItem>? localMap,
    String? categoryTag,
  }) {
    String title = card.title;
    if (title.toLowerCase().startsWith('download ')) {
      title = title.substring(9).trim();
    }

    // 1. Instant match in local database index if available (0ms)
    if (localMap != null && localMap.isNotEmpty) {
      final cardClean = ManifestItem.cleanPostTitle(card.title).toLowerCase().trim();
      if (cardClean.isNotEmpty) {
        for (final item in localMap.values) {
          final itemClean = item.cleanTitle.toLowerCase().trim();
          // Must match exact clean title (e.g. "breaking bad" == "breaking bad", not partial single word)
          if (cardClean == itemClean) {
            final enriched = item.copyWith(
              rawTitle: card.title,
              posterUrl: card.posterUrl.isNotEmpty ? card.posterUrl : item.posterUrl,
              postUrl: card.postUrl,
              isTrending: isTrending,
              trendingRank: trendingRank,
            );
            _itemMap[enriched.id.toString()] = enriched;
            _postUrlMap[enriched.id.toString()] = card.postUrl;
            return enriched;
          }
        }
      }
    }

    // Parse pure title, year, and mediaType
    final meta = ManifestItem.parsePostTitle(card.title);
    var displayTitle = meta.cleanTitle;
    if (displayTitle.length < 2) {
      displayTitle = title;
    }

    int? year = meta.year;
    if (year == null) {
      if (card.postUrl.contains('2026')) {
        year = 2026;
      } else {
        year = card.datePublished?.year ?? DateTime.now().year;
      }
    }

    final fastId = (card.postUrl.hashCode.abs() % 9000000) + 1000000;

    final langSet = <String>{};
    final countrySet = <String>{};
    final genreSet = <String>{};
    final genreIdSet = <int>{};
    String? origLang;

    // Infer from categoryTag if provided
    if (categoryTag != null && categoryTag.isNotEmpty) {
      final tag = categoryTag.toLowerCase().trim();
      if (tag == 'korean' || tag == 'k-drama' || tag == 'kdrama') {
        langSet.add('Korean');
        countrySet.add('KR');
        origLang = 'ko';
      } else if (tag == 'chinese') {
        langSet.add('Chinese');
        countrySet.add('CN');
        origLang = 'zh';
      } else if (tag == 'anime') {
        genreSet.addAll(['Animation', 'Anime']);
        genreIdSet.add(16);
        countrySet.add('JP');
      } else if (tag == 'indian' || tag == 'bollywood') {
        langSet.add('Hindi');
        countrySet.add('IN');
        origLang = 'hi';
      } else if (tag == 'dual-audio' || tag == 'dualaudio') {
        langSet.addAll(['Hindi', 'English', 'Dual Audio']);
      } else if (tag == 'punjabi') {
        langSet.add('Punjabi');
        countrySet.add('IN');
        origLang = 'pa';
      } else if (tag == 'pakistani') {
        langSet.add('Urdu');
        countrySet.add('PK');
        origLang = 'ur';
      } else if (tag == 'hollywood') {
        langSet.add('English');
        countrySet.add('US');
        origLang = 'en';
      } else if (tag != 'all' && tag != 'explore' && tag != 'search') {
        final capitalized = tag.substring(0, 1).toUpperCase() + tag.substring(1);
        genreSet.add(capitalized);
      }
    }

    // Infer from title text
    final lowerTitle = card.title.toLowerCase();
    if (lowerTitle.contains('hindi')) langSet.add('Hindi');
    if (lowerTitle.contains('english')) langSet.add('English');
    if (lowerTitle.contains('korean') || lowerTitle.contains('k-drama')) {
      langSet.add('Korean');
      countrySet.add('KR');
      origLang ??= 'ko';
    }
    if (lowerTitle.contains('chinese') || lowerTitle.contains('c-drama')) {
      langSet.add('Chinese');
      countrySet.add('CN');
      origLang ??= 'zh';
    }
    if (lowerTitle.contains('anime')) {
      genreSet.addAll(['Animation', 'Anime']);
      genreIdSet.add(16);
    }
    if (lowerTitle.contains('dual audio') || lowerTitle.contains('dubbed')) {
      langSet.addAll(['Dual Audio', 'Hindi']);
    }

    final item = ManifestItem(
      id: fastId,
      mediaType: meta.mediaType,
      title: displayTitle,
      rawTitle: card.title,
      posterUrl: card.posterUrl.isNotEmpty ? card.posterUrl : null,
      postUrl: card.postUrl,
      releaseYear: year,
      releaseDate: card.datePublished?.toIso8601String(),
      voteAverage: card.rating,
      isTrending: isTrending,
      trendingRank: trendingRank,
      language: langSet.toList(),
      originCountry: countrySet.toList(),
      originalLanguage: origLang,
      genres: genreSet.toList(),
      genreIds: genreIdSet.toList(),
    );

    _itemMap[item.id.toString()] = item;
    _postUrlMap[item.id.toString()] = card.postUrl;
    return item;
  }

  /// Live fetch Top 10 Indian (2026 releases) and Top 10 Hindi Dub from RogMovies & VegaMovies.
  Future<Map<String, List<ManifestItem>>> fetchHomeTopLists({
    Map<String, ManifestItem>? localMap,
    bool forceRefresh = false,
  }) async {
    // 0. If in-memory is empty and not force-refreshing, check disk cache first (0ms load)
    if (!forceRefresh && (_cachedTop10Indian == null || _cachedTop10HindiDub == null)) {
      await loadDiskCache();
    }

    // If we have cached data and this is NOT a forced refresh,
    // return cache immediately but schedule background refresh if stale
    if (!forceRefresh && _cachedTop10Indian != null && _cachedTop10HindiDub != null) {
      if (isHomeCacheStale) {
        // Schedule a background refresh — does NOT block the caller
        _backgroundRefreshHome(localMap: localMap);
      }
      return {
        'carousel': _cachedCarousel ?? _cachedTop10Indian!,
        'top10Indian': _cachedTop10Indian!,
        'top10HindiDub': _cachedTop10HindiDub!,
        'top5': _cachedCarousel ?? _cachedTop10Indian!,
        'top10': _cachedTop10HindiDub!,
      };
    }

    if (!forceRefresh && _pendingTopLists != null) {
      return _pendingTopLists!;
    }

    // 1. Try Cloudflare Edge Worker if configured
    if (edgeWorkerUrl.isNotEmpty) {
      final workerRes = await _fetchHomeFromWorker(localMap: localMap);
      if (workerRes != null) {
        _lastHomeFetchTime = DateTime.now();
        saveDiskCache(); // Async save to disk
        return workerRes;
      }
    }

    final future = _doFetchHomeTopLists(localMap: localMap);
    _pendingTopLists = future;
    try {
      final res = await future;
      _lastHomeFetchTime = DateTime.now();
      saveDiskCache(); // Async save to disk
      return res;
    } finally {
      _pendingTopLists = null;
    }
  }

  /// Non-blocking background refresh for home sections.
  /// Fetches fresh data from sites, updates caches, saves to disk,
  /// and notifies the UI to rebuild.
  Future<void>? _backgroundRefreshFuture;
  void _backgroundRefreshHome({Map<String, ManifestItem>? localMap}) {
    // Prevent duplicate concurrent background refreshes
    if (_backgroundRefreshFuture != null) return;
    _backgroundRefreshFuture = _doBackgroundRefreshHome(localMap: localMap);
    _backgroundRefreshFuture!.whenComplete(() {
      _backgroundRefreshFuture = null;
    });
  }

  Future<void> _doBackgroundRefreshHome({Map<String, ManifestItem>? localMap}) async {
    try {
      dev.log('[MovieSiteScraperService] Background refresh started...');

      if (edgeWorkerUrl.isNotEmpty) {
        final workerRes = await _fetchHomeFromWorker(localMap: localMap);
        if (workerRes != null) {
          _lastHomeFetchTime = DateTime.now();
          await saveDiskCache();
          onHomeRefreshed?.call();
          dev.log('[MovieSiteScraperService] Background refresh (worker) done — UI notified');
          return;
        }
      }

      await _doFetchHomeTopLists(localMap: localMap);
      _lastHomeFetchTime = DateTime.now();
      await saveDiskCache();
      onHomeRefreshed?.call();
      dev.log('[MovieSiteScraperService] Background refresh (direct) done — UI notified');
    } catch (e) {
      dev.log('[MovieSiteScraperService] Background refresh error: $e');
    }
  }

  /// Fetches pre-parsed home JSON from Cloudflare Edge Worker in ~50-80ms
  Future<Map<String, List<ManifestItem>>?> _fetchHomeFromWorker({
    Map<String, ManifestItem>? localMap,
  }) async {
    try {
      final res = await _dio.get<String>(
        '$edgeWorkerUrl/api/home',
        options: Options(responseType: ResponseType.plain),
      );
      if (res.statusCode == 200 && res.data != null && res.data!.isNotEmpty) {
        final data = jsonDecode(res.data!) as Map<String, dynamic>;
        final carouselRaw = data['carousel'] as List? ?? [];
        final indianRaw = data['top10Indian'] as List? ?? [];
        final hindiDubRaw = data['top10HindiDub'] as List? ?? [];

        final carousel = carouselRaw.map((e) => ManifestItem.fromJson(e as Map<String, dynamic>)).toList();
        final indian = indianRaw.map((e) => ManifestItem.fromJson(e as Map<String, dynamic>)).toList();
        final hindiDub = hindiDubRaw.map((e) => ManifestItem.fromJson(e as Map<String, dynamic>)).toList();

        _cachedCarousel = carousel;
        _cachedTop10Indian = indian;
        _cachedTop10HindiDub = hindiDub;

        for (final item in [...carousel, ...indian, ...hindiDub]) {
          _itemMap[item.id.toString()] = item;
        }

        dev.log('[MovieSiteScraperService] Loaded from Cloudflare Worker in <80ms');
        return {
          'carousel': carousel,
          'top10Indian': indian,
          'top10HindiDub': hindiDub,
          'top5': carousel,
          'top10': hindiDub,
        };
      }
    } catch (e) {
      dev.log('[MovieSiteScraperService] Worker home fetch error: $e');
    }
    return null;
  }

  /// Fetches pre-parsed category items from Cloudflare Edge Worker in ~50-80ms
  Future<List<ManifestItem>?> _fetchCategoryFromWorker(
    String categoryOrGenre, {
    int page = 1,
    Map<String, ManifestItem>? localMap,
  }) async {
    try {
      final key = categoryOrGenre.toLowerCase().trim();
      final res = await _dio.get<String>(
        '$edgeWorkerUrl/api/category?name=$key&page=$page',
        options: Options(responseType: ResponseType.plain),
      );
      if (res.statusCode == 200 && res.data != null && res.data!.isNotEmpty) {
        final data = jsonDecode(res.data!) as Map<String, dynamic>;
        final itemsRaw = data['items'] as List? ?? [];
        final items = <ManifestItem>[];
        for (final c in itemsRaw) {
          final card = ScrapedSiteCard(
            site: c['site'] as String? ?? 'vegamovies',
            postUrl: c['postUrl'] as String? ?? '',
            posterUrl: c['posterUrl'] as String? ?? '',
            title: c['title'] as String? ?? '',
            rating: (c['rating'] as num?)?.toDouble() ?? 7.2,
          );
          if (card.postUrl.isNotEmpty) {
            final item = createFastManifestItem(card, localMap: localMap);
            items.add(item);
          }
        }
        if (items.isNotEmpty) {
          final cacheKey = '${key}_page_$page';
          _categoryPageCache[cacheKey] = items;
          dev.log('[MovieSiteScraperService] Worker loaded category $key page $page (${items.length} items)');
          return items;
        }
      }
    } catch (e) {
      dev.log('[MovieSiteScraperService] Worker category fetch error: $e');
    }
    return null;
  }

  Future<Map<String, List<ManifestItem>>> _doFetchHomeTopLists({
    Map<String, ManifestItem>? localMap,
  }) async {
    dev.log('[MovieSiteScraperService] Live fetching Rog 2026, Vega & Rog homepages...');

    // Fetch RogMovies 2026 (p1 & p2), VegaMovies homepage, and RogMovies homepage in parallel
    final results = await Future.wait([
      fetchHtml('$rogBaseUrl/movies-by-year/2026/'),
      fetchHtml('$rogBaseUrl/movies-by-year/2026/page/2/'),
      fetchHtml(vegaBaseUrl),
      fetchHtml(rogBaseUrl),
    ]);

    final rog2026Html1 = results[0] ?? '';
    final rog2026Html2 = results[1] ?? '';
    final vegaHtml = results[2] ?? '';
    final rogHtml = results[3] ?? '';

    final rog2026Cards1 = parseCards(rog2026Html1, 'rogmovies');
    final vegaCards = parseCards(vegaHtml, 'vegamovies');
    final rogCards = parseCards(rogHtml, 'rogmovies');

    final usedUrls = <String>{};
    final usedTitles = <String>{};

    String cleanKey(String t) {
      return t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    }

    void markUsed(ScrapedSiteCard card) {
      usedUrls.add(card.postUrl);
      final k = cleanKey(card.title);
      if (k.length > 5) usedTitles.add(k);
    }

    bool isUsed(ScrapedSiteCard card) {
      if (usedUrls.contains(card.postUrl)) return true;
      final k = cleanKey(card.title);
      if (k.length > 5) {
        for (final u in usedTitles) {
          if (k.contains(u) || u.contains(k)) return true;
        }
      }
      return false;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Top 10 Indian Today (RogMovies 2026 - page 1 + page 2 fallback)
    // Exclude TV/reality shows (MTV Roadies, Big Boss, Dance Master, Hustle, etc.)
    // ─────────────────────────────────────────────────────────────────────────
    final top10IndianCards = <ScrapedSiteCard>[];

    for (final card in rog2026Cards1) {
      if (isExcludedIndianShow(card.title)) continue;
      if (!isUsed(card)) {
        top10IndianCards.add(card);
        markUsed(card);
        if (top10IndianCards.length >= 10) break;
      }
    }

    if (top10IndianCards.length < 10 && rog2026Html2.isNotEmpty) {
      final rog2026Cards2 = parseCards(rog2026Html2, 'rogmovies');
      for (final card in rog2026Cards2) {
        if (isExcludedIndianShow(card.title)) continue;
        if (!isUsed(card)) {
          top10IndianCards.add(card);
          markUsed(card);
          if (top10IndianCards.length >= 10) break;
        }
      }
    }

    if (top10IndianCards.length < 10) {
      for (final card in rogCards) {
        if (isExcludedIndianShow(card.title)) continue;
        if (!isUsed(card)) {
          top10IndianCards.add(card);
          markUsed(card);
          if (top10IndianCards.length >= 10) break;
        }
      }
    }

    final top10IndianItems = <ManifestItem>[];
    for (int i = 0; i < top10IndianCards.length; i++) {
      final item = createFastManifestItem(
        top10IndianCards[i],
        isTrending: true,
        trendingRank: i + 1,
        localMap: localMap,
      );
      top10IndianItems.add(item);
    }
    _cachedTop10Indian = top10IndianItems;

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Carousel Items (Top 5 featured from VegaMovies homepage)
    // Directly enrich with real TMDB IDs, pure titles, and logos in parallel
    // ─────────────────────────────────────────────────────────────────────────
    final carouselCards = <ScrapedSiteCard>[];
    for (final card in vegaCards) {
      if (isExcludedShow(card.title)) continue;
      carouselCards.add(card);
      if (carouselCards.length >= 5) break;
    }

    final carouselItems = await Future.wait(carouselCards.map((card) async {
      markUsed(card);
      final pureTitle = extractPureTitle(card.title);
      String? imdbId = await fetchImdbIdFromPostUrl(card.postUrl);
      int? tmdbId;
      String mediaType = RegExp(r'season|\bs\d+\b|series|k-drama|episode|tv-show', caseSensitive: false).hasMatch(card.title) ||
              card.postUrl.contains('series') ||
              card.postUrl.contains('season')
          ? 'tv'
          : 'movie';

      if (imdbId != null && imdbId.isNotEmpty) {
        final findData = await TmdbClient.instance.findByImdbId(imdbId);
        if (findData != null) {
          tmdbId = findData['id'] as int?;
          final type = findData['media_type']?.toString();
          if (type == 'tv' || type == 'movie') {
            mediaType = type!;
          }
        }
      }

      if (tmdbId == null) {
        final searchResults = await TmdbClient.instance.searchMulti(pureTitle);
        if (searchResults.isNotEmpty) {
          final firstMatch = searchResults.first;
          tmdbId = firstMatch['id'] as int?;
          final type = firstMatch['media_type']?.toString();
          if (type == 'tv' || type == 'movie') {
            mediaType = type!;
          }
        }
      }

      String? logoUrl;
      if (tmdbId != null) {
        registerResolvedTmdb(tmdbId, tmdbId, mediaType);
        logoUrl = await TmdbClient.instance.fetchTmdbLogo(tmdbId, mediaType);
      }

      final fastId = tmdbId ?? ((card.postUrl.hashCode.abs() % 9000000) + 1000000);
      registerResolvedTmdb(fastId, tmdbId ?? fastId, mediaType);

      final meta = ManifestItem.parsePostTitle(card.title);
      final item = ManifestItem(
        id: fastId,
        mediaType: mediaType,
        title: meta.cleanTitle,
        rawTitle: card.title,
        posterUrl: card.posterUrl.isNotEmpty ? card.posterUrl : null,
        postUrl: card.postUrl,
        logoUrl: logoUrl,
        imdbId: imdbId,
        releaseYear: meta.year ?? (card.datePublished?.year ?? DateTime.now().year),
        releaseDate: card.datePublished?.toIso8601String(),
        voteAverage: card.rating,
        isTrending: true,
      );
      _itemMap[item.id.toString()] = item;
      _postUrlMap[item.id.toString()] = card.postUrl;
      return item;
    }));
    _cachedCarousel = carouselItems;

    // ─────────────────────────────────────────────────────────────────────────
    // 3. Top 10 Hindi Dub Today (VegaMovies only - strictly excluding reality/competition shows)
    // ─────────────────────────────────────────────────────────────────────────
    final top10HindiDubCards = <ScrapedSiteCard>[];
    for (final card in vegaCards) {
      if (isExcludedShow(card.title)) continue;
      if (!isUsed(card)) {
        top10HindiDubCards.add(card);
        markUsed(card);
        if (top10HindiDubCards.length >= 10) break;
      }
    }

    // If Vega page 1 has fewer than 10 valid non-reality cards, fetch Vega page 2
    if (top10HindiDubCards.length < 10) {
      final vegaPage2Html = await fetchHtml('$vegaBaseUrl/page/2/');
      if (vegaPage2Html != null && vegaPage2Html.isNotEmpty) {
        final vegaPage2Cards = parseCards(vegaPage2Html, 'vegamovies');
        for (final card in vegaPage2Cards) {
          if (isExcludedShow(card.title)) continue;
          if (!isUsed(card)) {
            top10HindiDubCards.add(card);
            markUsed(card);
            if (top10HindiDubCards.length >= 10) break;
          }
        }
      }
    }

    final top10HindiDubItems = <ManifestItem>[];
    for (int i = 0; i < top10HindiDubCards.length; i++) {
      final item = createFastManifestItem(
        top10HindiDubCards[i],
        isTrending: true,
        trendingRank: i + 1,
        localMap: localMap,
      );
      top10HindiDubItems.add(item);
    }
    _cachedTop10HindiDub = top10HindiDubItems;

    dev.log(
      '[MovieSiteScraperService] Ready: Top 10 Indian (${top10IndianItems.length}), '
      'Top 10 Hindi Dub (${top10HindiDubItems.length}), Carousel (${carouselItems.length})',
    );

    return {
      'carousel': carouselItems,
      'top10Indian': top10IndianItems,
      'top10HindiDub': top10HindiDubItems,
      'top5': carouselItems,
      'top10': top10HindiDubItems,
    };
  }

  /// Fetch Chinese drama posts strictly via /chinese-series/ on Vegamovies
  Future<List<ScrapedSiteCard>> _fetchChineseCards({int page = 1}) async {
    final cards = <ScrapedSiteCard>[];
    try {
      final csUrl = page == 1 ? '$vegaBaseUrl/chinese-series/' : '$vegaBaseUrl/chinese-series/page/$page/';
      final html = await fetchHtml(csUrl);
      if (html != null && html.isNotEmpty) {
        final htmlCards = parseCards(html, 'vegamovies');
        cards.addAll(htmlCards);
      }
    } catch (e) {
      debugPrint('[MovieSiteScraperService] Chinese series HTML error: $e');
    }
    return cards;
  }

  /// Search across both Vegamovies and Rogmovies, merging results and sorting latest to oldest.
  Future<List<ManifestItem>> searchBothSites(
    String query, {
    int page = 1,
    Map<String, ManifestItem>? localMap,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final cleanQ = Uri.encodeComponent(q);
    final cards = <ScrapedSiteCard>[];
    final seenUrls = <String>{};

    try {
      final results = await Future.wait([
        // 1. Vegamovies Typesense search
        _dio
            .get<String>(
              '$vegaBaseUrl/ts-search.php?q=$cleanQ&page=$page',
              options: Options(responseType: ResponseType.plain),
            )
            .then((r) => r.data)
            .catchError((_) => null),
        // 2. Rogmovies Typesense search
        _dio
            .get<String>(
              '$rogBaseUrl/ts-search.php?q=$cleanQ&page=$page',
              options: Options(responseType: ResponseType.plain),
            )
            .then((r) => r.data)
            .catchError((_) => null),
        // 3. Rogmovies HTML search
        fetchHtml('$rogBaseUrl/?s=$cleanQ'),
        // 4. Vegamovies HTML search
        fetchHtml('$vegaBaseUrl/?s=$cleanQ'),
      ]);

      for (final c in parseTsCards(results[0], 'vegamovies', vegaBaseUrl)) {
        if (!seenUrls.contains(c.postUrl) && !isExcludedShow(c.title)) {
          seenUrls.add(c.postUrl);
          cards.add(c);
        }
      }
      for (final c in parseTsCards(results[1], 'rogmovies', rogBaseUrl)) {
        if (!seenUrls.contains(c.postUrl) && !isExcludedShow(c.title)) {
          seenUrls.add(c.postUrl);
          cards.add(c);
        }
      }

      // Parse Rogmovies HTML search cards
      if (results[2] != null && results[2]!.isNotEmpty) {
        for (final c in parseCards(results[2]!, 'rogmovies')) {
          if (!seenUrls.contains(c.postUrl) && !isExcludedShow(c.title)) {
            seenUrls.add(c.postUrl);
            cards.add(c);
          }
        }
      }

      // Parse Vegamovies HTML search cards
      if (results[3] != null && results[3]!.isNotEmpty) {
        for (final c in parseCards(results[3]!, 'vegamovies')) {
          if (!seenUrls.contains(c.postUrl) && !isExcludedShow(c.title)) {
            seenUrls.add(c.postUrl);
            cards.add(c);
          }
        }
      }
    } catch (e) {
      debugPrint('[MovieSiteScraperService] searchBothSites error: $e');
    }

    // Sort by query relevance (closest match from top to bottom) with date tie-breaker
    cards.sort((a, b) {
      final scoreA = computeRelevanceScore(a.title, q);
      final scoreB = computeRelevanceScore(b.title, q);
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA); // Higher relevance score at the top
      }
      if (a.datePublished == null && b.datePublished == null) return 0;
      if (a.datePublished == null) return 1;
      if (b.datePublished == null) return -1;
      return b.datePublished!.compareTo(a.datePublished!);
    });

    final items = <ManifestItem>[];
    for (final card in cards) {
      final item = createFastManifestItem(card, localMap: localMap);
      items.add(item);
    }
    return items;
  }

  /// Computes a relevance score (higher = closer match) comparing [rawTitle] against [rawQuery].
  /// Accounts for exact phrase matching, prefix matching (ignoring "Download" prefix),
  /// token matching, token density, and position bonuses.
  int computeRelevanceScore(String rawTitle, String rawQuery) {
    final q = rawQuery.toLowerCase().trim();
    if (q.isEmpty) return 0;

    final title = rawTitle.toLowerCase().trim();
    if (title.isEmpty) return 0;

    // Remove leading "download" prefix common on Vegamovies
    final strippedTitle = title.replaceFirst(RegExp(r'^download\s+'), '');

    int score = 0;

    // 1. Exact or whole phrase match bonus
    if (strippedTitle == q || title == q) {
      score += 50000;
    } else if (strippedTitle.startsWith(q) || title.startsWith(q)) {
      score += 25000;
    } else if (strippedTitle.contains(q) || title.contains(q)) {
      score += 15000;
    }

    // Tokenize query and title (alphanumeric words)
    final qTokens = q
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final titleTokens = strippedTitle
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final titleTokenSet = titleTokens.toSet();

    if (qTokens.isEmpty) return score;

    int matchedTokensCount = 0;
    int exactTokenMatches = 0;

    for (int i = 0; i < qTokens.length; i++) {
      final qt = qTokens[i];

      if (titleTokenSet.contains(qt)) {
        matchedTokensCount++;
        exactTokenMatches++;
        score += 2000;

        // Position bonus: earlier token = higher relevance
        final idx = titleTokens.indexOf(qt);
        if (idx == 0) {
          score += 1500;
        } else if (idx <= 3) {
          score += 800;
        }
      } else {
        // Check if any title token starts with or contains query token
        bool foundPrefix = false;
        for (final tt in titleTokens) {
          if (tt.startsWith(qt)) {
            matchedTokensCount++;
            score += 1000;
            foundPrefix = true;
            break;
          } else if (tt.contains(qt)) {
            score += 500;
            foundPrefix = true;
            break;
          }
        }
        if (!foundPrefix && title.contains(qt)) {
          score += 300;
        }
      }
    }

    // Bonus if 100% of query tokens matched
    if (matchedTokensCount >= qTokens.length) {
      score += 10000;
    } else {
      final matchRatio = matchedTokensCount / qTokens.length;
      score += (matchRatio * 5000).toInt();
    }

    // Density bonus: favor titles where query tokens make up a higher percentage of the title
    if (titleTokens.isNotEmpty) {
      final density = (exactTokenMatches / titleTokens.length) * 2000;
      score += density.toInt();
    }

    return score;
  }

  /// Live fetch category/genre posts by page (supports infinite scrolling)
  Future<List<ManifestItem>> fetchCategoryPage(
    String categoryOrGenre, {
    int page = 1,
    Map<String, ManifestItem>? localMap,
  }) async {
    final key = categoryOrGenre.toLowerCase().trim();
    final cacheKey = '${key}_page_$page';

    // Return cache immediately if available, but schedule background refresh if stale
    if (_categoryPageCache.containsKey(cacheKey) && _categoryPageCache[cacheKey]!.isNotEmpty) {
      if (isCategoryCacheStale && page == 1) {
        // Background refresh for page 1 only
        _backgroundRefreshCategory(categoryOrGenre, localMap: localMap);
      }
      return _categoryPageCache[cacheKey]!;
    }

    if (_pendingCategoryPages.containsKey(cacheKey)) {
      return _pendingCategoryPages[cacheKey]!;
    }

    final future = _doFetchCategoryPage(categoryOrGenre, page: page, localMap: localMap);
    _pendingCategoryPages[cacheKey] = future;
    try {
      final res = await future;
      if (page == 1) _lastCategoryFetchTime = DateTime.now();
      return res;
    } finally {
      _pendingCategoryPages.remove(cacheKey);
    }
  }

  /// Background refresh for a single category page 1
  final Set<String> _pendingBgCategoryRefreshes = {};
  void _backgroundRefreshCategory(String categoryOrGenre, {Map<String, ManifestItem>? localMap}) {
    final key = categoryOrGenre.toLowerCase().trim();
    if (_pendingBgCategoryRefreshes.contains(key)) return;
    _pendingBgCategoryRefreshes.add(key);

    () async {
      try {
        dev.log('[MovieSiteScraperService] Background category refresh: $key');
        // Clear old cache for this key so _doFetchCategoryPage re-fetches
        _categoryPageCache.remove('${key}_page_1');
        await _doFetchCategoryPage(categoryOrGenre, page: 1, localMap: localMap);
        _lastCategoryFetchTime = DateTime.now();
        await saveDiskCache();
        onCategoriesRefreshed?.call();
        dev.log('[MovieSiteScraperService] Background category refresh done: $key');
      } catch (e) {
        dev.log('[MovieSiteScraperService] Background category refresh error ($key): $e');
      } finally {
        _pendingBgCategoryRefreshes.remove(key);
      }
    }();
  }

  Future<List<ManifestItem>> _doFetchCategoryPage(
    String categoryOrGenre, {
    int page = 1,
    Map<String, ManifestItem>? localMap,
  }) async {
    final key = categoryOrGenre.toLowerCase().trim();
    final cacheKey = '${key}_page_$page';

    dev.log('[MovieSiteScraperService] Live fetching section: $categoryOrGenre (page $page)');

    if (edgeWorkerUrl.isNotEmpty) {
      final workerItems = await _fetchCategoryFromWorker(categoryOrGenre, page: page, localMap: localMap);
      if (workerItems != null && workerItems.isNotEmpty) {
        return workerItems;
      }
    }

    final cards = <ScrapedSiteCard>[];

    if (key == 'all' || key == 'explore' || key == 'search') {
      final vegaUrl = page == 1 ? vegaBaseUrl : '$vegaBaseUrl/page/$page/';
      final rogUrl = page == 1 ? rogBaseUrl : '$rogBaseUrl/page/$page/';
      final results = await Future.wait([
        fetchHtml(vegaUrl),
        fetchHtml(rogUrl),
      ]);
      if (results[0] != null) cards.addAll(parseCards(results[0]!, 'vegamovies'));
      if (results[1] != null) cards.addAll(parseCards(results[1]!, 'rogmovies'));
    } else if (key == 'korean' || key == 'k-drama' || key == 'kdrama') {
      final pageUrl = page == 1
          ? '$vegaBaseUrl/korean-series/'
          : '$vegaBaseUrl/korean-series/page/$page/';
      final html = await fetchHtml(pageUrl);
      if (html != null && html.isNotEmpty) {
        cards.addAll(parseCards(html, 'vegamovies'));
      }
      if (cards.isEmpty) {
        cards.addAll(await _fetchTypesenseCards('Korean', page: page, site: 'vegamovies'));
      }
    } else if (key == 'chinese') {
      cards.addAll(await _fetchChineseCards(page: page));
      if (cards.isEmpty) {
        cards.addAll(await _fetchTypesenseCards('Chinese', page: page, site: 'vegamovies'));
      }
    } else if (key == 'anime') {
      final pageUrl = page == 1
          ? '$vegaBaseUrl/anime-series/'
          : '$vegaBaseUrl/anime-series/page/$page/';
      final html = await fetchHtml(pageUrl);
      if (html != null && html.isNotEmpty) {
        cards.addAll(parseCards(html, 'vegamovies'));
      }
      if (cards.isEmpty) {
        cards.addAll(await _fetchTypesenseCards('Anime', page: page, site: 'vegamovies'));
      }
    } else if (key == 'indian' || key == 'bollywood') {
      // Rogmovies homepage feed and pagination ONLY (never Vegamovies)
      final pageUrl = page == 1 ? rogBaseUrl : '$rogBaseUrl/page/$page/';
      final html = await fetchHtml(pageUrl);
      if (html != null && html.isNotEmpty) {
        cards.addAll(parseCards(html, 'rogmovies'));
      }
      if (cards.isEmpty) {
        cards.addAll(await _fetchTypesenseCards('Hindi', page: page, site: 'rogmovies'));
      }
    } else if (key == 'dual-audio' || key == 'dualaudio') {
      // Vegamovies homepage feed and pagination ONLY (never Rogmovies)
      final pageUrl = page == 1 ? vegaBaseUrl : '$vegaBaseUrl/page/$page/';
      final html = await fetchHtml(pageUrl);
      if (html != null && html.isNotEmpty) {
        cards.addAll(parseCards(html, 'vegamovies'));
      }
      if (cards.isEmpty) {
        cards.addAll(await _fetchTypesenseCards('Dual Audio', page: page, site: 'vegamovies'));
      }
    } else if (key == 'hollywood') {
      final vegaUrl = page == 1 ? '$vegaBaseUrl/?s=Hollywood' : '$vegaBaseUrl/page/$page/?s=Hollywood';
      final rogUrl = page == 1 ? '$rogBaseUrl/?s=Hollywood' : '$rogBaseUrl/page/$page/?s=Hollywood';
      final results = await Future.wait([
        fetchHtml(vegaUrl),
        fetchHtml(rogUrl),
        _fetchTypesenseCards('English', page: page),
      ]);
      if (results[0] != null) cards.addAll(parseCards(results[0]! as String, 'vegamovies'));
      if (results[1] != null) cards.addAll(parseCards(results[1]! as String, 'rogmovies'));
      cards.addAll(results[2] as List<ScrapedSiteCard>);
    } else if (key == 'punjabi') {
      final vegaUrl = page == 1 ? '$vegaBaseUrl/?s=Punjabi' : '$vegaBaseUrl/page/$page/?s=Punjabi';
      final rogUrl = page == 1 ? '$rogBaseUrl/?s=Punjabi' : '$rogBaseUrl/page/$page/?s=Punjabi';
      final results = await Future.wait([
        fetchHtml(vegaUrl),
        fetchHtml(rogUrl),
        _fetchTypesenseCards('Punjabi', page: page),
      ]);
      if (results[0] != null) cards.addAll(parseCards(results[0]! as String, 'vegamovies'));
      if (results[1] != null) cards.addAll(parseCards(results[1]! as String, 'rogmovies'));
      cards.addAll(results[2] as List<ScrapedSiteCard>);
    } else if (key == 'pakistani') {
      final vegaUrl = page == 1 ? '$vegaBaseUrl/?s=Pakistani' : '$vegaBaseUrl/page/$page/?s=Pakistani';
      final rogUrl = page == 1 ? '$rogBaseUrl/?s=Pakistani' : '$rogBaseUrl/page/$page/?s=Pakistani';
      final results = await Future.wait([
        fetchHtml(vegaUrl),
        fetchHtml(rogUrl),
        _fetchTypesenseCards('Pakistani', page: page),
      ]);
      if (results[0] != null) cards.addAll(parseCards(results[0]! as String, 'vegamovies'));
      if (results[1] != null) cards.addAll(parseCards(results[1]! as String, 'rogmovies'));
      cards.addAll(results[2] as List<ScrapedSiteCard>);
    } else {
      // All other genres: Action, Sci-Fi, Comedy, Thriller, Horror, Romance, Adventure, Crime, Drama, Mystery, Fantasy, Animation
      final genreSlug = key;
      final vegaGenreUrl = page == 1
          ? '$vegaBaseUrl/movies-by-genres/$genreSlug/'
          : '$vegaBaseUrl/movies-by-genres/$genreSlug/page/$page/';
      final rogGenreUrl = page == 1
          ? '$rogBaseUrl/movies-by-genres/$genreSlug/'
          : '$rogBaseUrl/movies-by-genres/$genreSlug/page/$page/';

      final results = await Future.wait([
        fetchHtml(vegaGenreUrl),
        fetchHtml(rogGenreUrl),
        _fetchTypesenseCards(key, page: page),
      ]);

      if (results[0] != null) cards.addAll(parseCards(results[0]! as String, 'vegamovies'));
      if (results[1] != null) cards.addAll(parseCards(results[1]! as String, 'rogmovies'));
      cards.addAll(results[2] as List<ScrapedSiteCard>);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Dynamically sort posts chronologically descending by actual upload date
    // (Latest uploaded posts at the top, seamless dynamic flow from both sites)
    // ─────────────────────────────────────────────────────────────────────────
    if (key != 'dual-audio' && key != 'dualaudio' && key != 'indian' && key != 'bollywood') {
      cards.sort((a, b) {
        if (a.datePublished == null && b.datePublished == null) return 0;
        if (a.datePublished == null) return 1;
        if (b.datePublished == null) return -1;
        return b.datePublished!.compareTo(a.datePublished!);
      });
    }

    final items = <ManifestItem>[];
    final seenUrls = <String>{};

    for (final card in cards) {
      if (seenUrls.contains(card.postUrl)) continue;
      seenUrls.add(card.postUrl);

      final item = createFastManifestItem(
        card,
        localMap: localMap,
        categoryTag: key,
      );
      items.add(item);
    }

    _categoryPageCache[cacheKey] = items;
    dev.log('[MovieSiteScraperService] Section $categoryOrGenre page $page ready with ${items.length} items.');
    return items;
  }

  /// Live fetch category/genre posts (page 1)
  Future<List<ManifestItem>> fetchCategoryItems(
    String categoryOrGenre, {
    Map<String, ManifestItem>? localMap,
  }) async {
    return fetchCategoryPage(categoryOrGenre, page: 1, localMap: localMap);
  }
}


