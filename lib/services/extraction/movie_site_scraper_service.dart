import 'dart:convert';
import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../domain/models/manifest_item.dart';
import '../../data/clients/tmdb_client.dart';

class ScrapedSiteCard {
  final String site; // 'vegamovies' | 'rogmovies'
  final String postUrl;
  final String posterUrl;
  final String title;
  final double rating;

  ScrapedSiteCard({
    required this.site,
    required this.postUrl,
    required this.posterUrl,
    required this.title,
    this.rating = 7.0,
  });
}

class MovieSiteScraperService {
  MovieSiteScraperService._();
  static final MovieSiteScraperService instance = MovieSiteScraperService._();

  static const String vegaBaseUrl = 'https://vegamovies.gallery';
  static const String rogBaseUrl = 'https://rogmovies.best';

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12),
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

  // Cache in-memory for live session
  List<ManifestItem>? _cachedCarousel;
  List<ManifestItem>? _cachedTop10Indian;
  List<ManifestItem>? _cachedTop10HindiDub;
  List<ManifestItem>? _cachedTop5;
  List<ManifestItem>? _cachedTop10;
  Future<Map<String, List<ManifestItem>>>? _pendingTopLists;
  final Map<String, Future<List<ManifestItem>>> _pendingCategoryPages = {};
  final Map<String, List<ManifestItem>> _categoryPageCache = {};
  final Map<String, ManifestItem> _itemMap = {};

  Map<String, ManifestItem> get itemMap => _itemMap;

  static final RegExp _excludedIndianShowPatterns = RegExp(
    r'roadies|bigg?\s*boss|dance\s*master|hustle|top\s*1\s*%|top\s*1\s*percent|sa\s*re\s*ga\s*ma|sare\s*gama|best\s*dancer|beat\s*dancer|khatron\s*ke\s*khiladi|got\s*latent|kapil\s*show|reality|tv-show|rise\s*and\s*fall|family\s*full\s*house',
    caseSensitive: false,
  );

  static bool isExcludedIndianShow(String title) {
    return _excludedIndianShowPatterns.hasMatch(title);
  }

  void clearCache() {
    _cachedCarousel = null;
    _cachedTop10Indian = null;
    _cachedTop10HindiDub = null;
    _cachedTop5 = null;
    _cachedTop10 = null;
    _pendingTopLists = null;
    _pendingCategoryPages.clear();
    _categoryPageCache.clear();
    _itemMap.clear();
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

  /// Extract poster cards from VegaMovies / RogMovies HTML
  static List<ScrapedSiteCard> parseCards(String html, String site) {
    final cards = <ScrapedSiteCard>[];
    final seenUrls = <String>{};

    final cardRegex = RegExp(
      r'<div class="poster-card"[^>]*>([\s\S]*?)<\/div>\s*<\/div>\s*<\/div>',
      caseSensitive: false,
    );

    final urlRegex = RegExp(r'<meta itemprop="url" content="([^"]+)"|<a\s+[^>]*href="([^"]+)"', caseSensitive: false);
    final imgRegex = RegExp(r'<img[^>]+(?:src|data-src)="([^"]+)"', caseSensitive: false);
    final altRegex = RegExp(r'alt="([^"]+)"', caseSensitive: false);
    final titleRegex = RegExp(r'class="poster-title"[^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>', caseSensitive: false);
    final rateRegex = RegExp(r'<meta itemprop="ratingValue" content="([^"]+)"', caseSensitive: false);

    for (final match in cardRegex.allMatches(html)) {
      final block = match.group(1) ?? '';
      final urlM = urlRegex.firstMatch(block);
      final postUrl = urlM?.group(1) ?? urlM?.group(2);
      if (postUrl == null || seenUrls.contains(postUrl)) continue;

      final imgM = imgRegex.firstMatch(block);
      final altM = altRegex.firstMatch(block);
      final titleM = titleRegex.firstMatch(block);
      final rateM = rateRegex.firstMatch(block);

      final rawTitle = altM?.group(1) ?? (titleM?.group(1) ?? '');
      final title = cleanTitle(rawTitle);
      final poster = imgM?.group(1) ?? '';
      final rating = rateM != null ? double.tryParse(rateM.group(1) ?? '') ?? 7.2 : 7.2;

      if (title.length > 2) {
        seenUrls.add(postUrl);
        cards.add(ScrapedSiteCard(
          site: site,
          postUrl: postUrl,
          posterUrl: poster,
          title: title,
          rating: rating,
        ));
      }
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
  }) {
    String title = card.title;
    if (title.toLowerCase().startsWith('download ')) {
      title = title.substring(9).trim();
    }

    // 1. Instant match in local database index if available (0ms)
    if (localMap != null && localMap.isNotEmpty) {
      final normTitle = title.toLowerCase();
      for (final item in localMap.values) {
        final itemNorm = item.cleanTitle.toLowerCase();
        if (itemNorm.length > 4 && normTitle.contains(itemNorm)) {
          final enriched = item.copyWith(
            posterUrl: card.posterUrl.isNotEmpty ? card.posterUrl : item.posterUrl,
            isTrending: isTrending,
            trendingRank: trendingRank,
          );
          _itemMap[enriched.id.toString()] = enriched;
          return enriched;
        }
      }
    }

    // Clean clutter from raw scrape title (e.g. resolution, rip tags, audio tags)
    var displayTitle = title.replaceAll(RegExp(r'\s*[\{\[].*?[\}\]]'), ' ');
    displayTitle = displayTitle.replaceAll(
      RegExp(
        r'\s*(?:Full Movie|Complete Web Series|WEB-DL|HDTC|PreDVD|HDRip|x264|HEVC|H\.264|HQ|UnCut|ORG\.?|LiNE|Hindi|Dual Audio|Tamil|Telugu|Punjabi|JioHotstar|SonyLiv|Netflix|AMZN|Zee5|–|\*No Ads\*|480p|720p|1080p|2160p).*$',
        caseSensitive: false,
      ),
      '',
    );
    displayTitle = displayTitle.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (displayTitle.length < 3) {
      displayTitle = title;
    }

    // 2. Parse year & mediaType locally (0ms)
    int? year;
    final yearMatch = RegExp(r'\((\d{4})\)').firstMatch(title);
    if (yearMatch != null) {
      year = int.tryParse(yearMatch.group(1)!);
    } else if (card.postUrl.contains('2026')) {
      year = 2026;
    }

    final isTv = RegExp(r'season|\bs\d+\b|series|k-drama|episode|tv-show', caseSensitive: false).hasMatch(title) ||
        card.postUrl.contains('series') ||
        card.postUrl.contains('season');
    final mediaType = isTv ? 'tv' : 'movie';

    final fastId = (card.postUrl.hashCode.abs() % 9000000) + 1000000;

    final item = ManifestItem(
      id: fastId,
      mediaType: mediaType,
      title: displayTitle,
      posterUrl: card.posterUrl.isNotEmpty ? card.posterUrl : null,
      releaseYear: year ?? DateTime.now().year,
      voteAverage: card.rating,
      isTrending: isTrending,
      trendingRank: trendingRank,
    );

    _itemMap[item.id.toString()] = item;
    return item;
  }

  /// Live fetch Top 10 Indian (2026 releases) and Top 10 Hindi Dub from RogMovies & VegaMovies.
  Future<Map<String, List<ManifestItem>>> fetchHomeTopLists({
    Map<String, ManifestItem>? localMap,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedTop10Indian != null && _cachedTop10HindiDub != null) {
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

    final future = _doFetchHomeTopLists(localMap: localMap);
    _pendingTopLists = future;
    try {
      final res = await future;
      return res;
    } finally {
      _pendingTopLists = null;
    }
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
    // ─────────────────────────────────────────────────────────────────────────
    final carouselCards = <ScrapedSiteCard>[];
    for (final card in vegaCards) {
      if (carouselCards.length >= 5) break;
      carouselCards.add(card);
    }
    final carouselItems = <ManifestItem>[];
    for (int i = 0; i < carouselCards.length; i++) {
      final item = createFastManifestItem(
        carouselCards[i],
        isTrending: true,
        trendingRank: i + 1,
        localMap: localMap,
      );
      carouselItems.add(item);
    }
    _cachedCarousel = carouselItems;

    // ─────────────────────────────────────────────────────────────────────────
    // 3. Top 10 Hindi Dub Today
    // 5 from RogMovies homepage + 5 from VegaMovies homepage, dynamically interleaved,
    // strictly distinct from Top 10 Indian Today!
    // ─────────────────────────────────────────────────────────────────────────
    final top10HindiDubCards = <ScrapedSiteCard>[];
    int rIdx = 0;
    int vIdx = 0;

    for (int i = 0; i < 5; i++) {
      while (rIdx < rogCards.length && isUsed(rogCards[rIdx])) {
        rIdx++;
      }
      if (rIdx < rogCards.length) {
        top10HindiDubCards.add(rogCards[rIdx]);
        markUsed(rogCards[rIdx]);
        rIdx++;
      }

      while (vIdx < vegaCards.length && isUsed(vegaCards[vIdx])) {
        vIdx++;
      }
      if (vIdx < vegaCards.length) {
        top10HindiDubCards.add(vegaCards[vIdx]);
        markUsed(vegaCards[vIdx]);
        vIdx++;
      }
    }

    // Fill remaining if needed to guarantee 10
    while (top10HindiDubCards.length < 10 && rIdx < rogCards.length) {
      if (!isUsed(rogCards[rIdx])) {
        top10HindiDubCards.add(rogCards[rIdx]);
        markUsed(rogCards[rIdx]);
      }
      rIdx++;
    }
    while (top10HindiDubCards.length < 10 && vIdx < vegaCards.length) {
      if (!isUsed(vegaCards[vIdx])) {
        top10HindiDubCards.add(vegaCards[vIdx]);
        markUsed(vegaCards[vIdx]);
      }
      vIdx++;
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
    _cachedTop5 = carouselItems;
    _cachedTop10 = top10HindiDubItems;

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

  /// Fetch Chinese drama posts via /chinese-series/ or ts-search.php
  Future<List<ScrapedSiteCard>> _fetchChineseCards({int page = 1}) async {
    final cards = <ScrapedSiteCard>[];
    // 1. Fetch /chinese-series/ directly
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

    // 2. Fallback to ts-search.php if empty
    if (cards.isEmpty) {
      try {
        final url = '$vegaBaseUrl/ts-search.php?q=Chinese&page=$page';
        final res = await _dio.get<String>(url, options: Options(responseType: ResponseType.plain));
        if (res.statusCode == 200 && res.data != null) {
          final data = jsonDecode(res.data!) as Map<String, dynamic>;
          final hits = data['hits'] as List?;
          if (hits != null) {
            for (final hit in hits) {
              final doc = hit['document'] as Map<String, dynamic>?;
              if (doc != null) {
                final title = doc['post_title']?.toString() ?? '';
                final permalink = doc['permalink']?.toString() ?? '';
                final thumb = doc['thumb']?.toString() ?? '';
                final fullUrl = permalink.startsWith('http') ? permalink : '$vegaBaseUrl$permalink';
                if (title.isNotEmpty && fullUrl.isNotEmpty) {
                  cards.add(ScrapedSiteCard(
                    site: 'vegamovies',
                    postUrl: fullUrl,
                    posterUrl: thumb,
                    title: cleanTitle(title),
                  ));
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[MovieSiteScraperService] Chinese ts-search error: $e');
      }
    }

    return cards;
  }

  /// Live fetch category/genre posts by page (supports infinite scrolling)
  Future<List<ManifestItem>> fetchCategoryPage(
    String categoryOrGenre, {
    int page = 1,
    Map<String, ManifestItem>? localMap,
  }) async {
    final key = categoryOrGenre.toLowerCase().trim();
    final cacheKey = '${key}_page_$page';
    if (_categoryPageCache.containsKey(cacheKey) && _categoryPageCache[cacheKey]!.isNotEmpty) {
      return _categoryPageCache[cacheKey]!;
    }

    if (_pendingCategoryPages.containsKey(cacheKey)) {
      return _pendingCategoryPages[cacheKey]!;
    }

    final future = _doFetchCategoryPage(categoryOrGenre, page: page, localMap: localMap);
    _pendingCategoryPages[cacheKey] = future;
    try {
      final res = await future;
      return res;
    } finally {
      _pendingCategoryPages.remove(cacheKey);
    }
  }

  Future<List<ManifestItem>> _doFetchCategoryPage(
    String categoryOrGenre, {
    int page = 1,
    Map<String, ManifestItem>? localMap,
  }) async {
    final key = categoryOrGenre.toLowerCase().trim();
    final cacheKey = '${key}_page_$page';

    dev.log('[MovieSiteScraperService] Live fetching section: $categoryOrGenre (page $page)');
    final cards = <ScrapedSiteCard>[];

    if (key == 'korean' || key == 'k-drama' || key == 'kdrama') {
      final pageUrl = page == 1
          ? '$vegaBaseUrl/korean-series/'
          : '$vegaBaseUrl/korean-series/page/$page/';
      final html = await fetchHtml(pageUrl);
      if (html != null) cards.addAll(parseCards(html, 'vegamovies'));
    } else if (key == 'chinese') {
      cards.addAll(await _fetchChineseCards(page: page));
    } else if (key == 'anime') {
      final pageUrl = page == 1
          ? '$vegaBaseUrl/anime-series/'
          : '$vegaBaseUrl/anime-series/page/$page/';
      final html = await fetchHtml(pageUrl);
      if (html != null) cards.addAll(parseCards(html, 'vegamovies'));
    } else {
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
      ]);

      final vegaHtml = results[0] ?? '';
      final rogHtml = results[1] ?? '';

      final vegaG = parseCards(vegaHtml, 'vegamovies');
      final rogG = parseCards(rogHtml, 'rogmovies');

      final maxLen = vegaG.length > rogG.length ? vegaG.length : rogG.length;
      for (int i = 0; i < maxLen; i++) {
        if (i < vegaG.length) cards.add(vegaG[i]);
        if (i < rogG.length) cards.add(rogG[i]);
      }
    }

    final items = <ManifestItem>[];
    final seenUrls = <String>{};

    for (final card in cards) {
      if (seenUrls.contains(card.postUrl)) continue;
      seenUrls.add(card.postUrl);

      final item = createFastManifestItem(card, localMap: localMap);
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


