import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  // Cache in-memory for live session
  List<ManifestItem>? _cachedTop5;
  List<ManifestItem>? _cachedTop10;
  final Map<String, List<ManifestItem>> _categoryCache = {};
  final Map<String, List<ManifestItem>> _categoryPageCache = {};
  final Map<String, ManifestItem> _itemMap = {};

  Map<String, ManifestItem> get itemMap => _itemMap;

  void clearCache() {
    _cachedTop5 = null;
    _cachedTop10 = null;
    _categoryCache.clear();
    _categoryPageCache.clear();
    _itemMap.clear();
  }

  /// Normalize URL to use local dev proxy when available to bypass ISP block
  static String normalizeFetchUrl(String url) {
    if (url.startsWith('https://vegamovies.gallery')) {
      return url.replaceFirst('https://vegamovies.gallery', 'http://127.0.0.1:8080/api/vegamovies');
    }
    if (url.startsWith('https://rogmovies.best')) {
      return url.replaceFirst('https://rogmovies.best', 'http://127.0.0.1:8080/api/rogmovies');
    }
    return url;
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

  /// Fetch HTML with direct fetch first (fast, ~400ms), falling back to reverse proxy & public proxies
  static Future<String?> fetchHtml(String url) async {
    // 1. Direct fetch FIRST (fast, usually takes ~400ms)
    try {
      final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        return res.body;
      }
    } catch (e) {
      debugPrint('[MovieSiteScraperService] Direct fetch failed for $url: $e');
    }

    // 2. Try local proxy (127.0.0.1 via adb reverse)
    final proxyUrl = normalizeFetchUrl(url);
    if (proxyUrl != url) {
      try {
        final res = await http.get(Uri.parse(proxyUrl), headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          return res.body;
        }
      } catch (e) {
        debugPrint('[MovieSiteScraperService] Local proxy failed for $proxyUrl: $e');
      }

      // 2b. Try LAN IP proxy (when connected over Wi-Fi)
      final lanProxyUrl = proxyUrl.replaceFirst('127.0.0.1', '192.168.100.125');
      try {
        final res = await http.get(Uri.parse(lanProxyUrl), headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          return res.body;
        }
      } catch (e) {
        debugPrint('[MovieSiteScraperService] LAN proxy failed for $lanProxyUrl: $e');
      }
    }

    // 3. Public CORS proxy fallback
    try {
      final allOrigins = 'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}';
      final res = await http.get(Uri.parse(allOrigins)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        return res.body;
      }
    } catch (e) {
      debugPrint('[MovieSiteScraperService] Fallback proxy failed for $url: $e');
    }

    return null;
  }


  /// Converts a ScrapedSiteCard into a full ManifestItem with TMDB enrichment
  Future<ManifestItem> convertToManifestItem(
    ScrapedSiteCard card, {
    bool isTrending = false,
    int? trendingRank,
    Map<String, ManifestItem>? localMap,
  }) async {
    String title = card.title;
    if (title.toLowerCase().startsWith('download ')) {
      title = title.substring(9).trim();
    }

    // Try finding in localMap by title match first for instant hit
    if (localMap != null && localMap.isNotEmpty) {
      final normTitle = title.toLowerCase();
      for (final item in localMap.values) {
        final itemNorm = item.cleanTitle.toLowerCase();
        if (normTitle.contains(itemNorm) && itemNorm.length > 4) {
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

    int? year;
    final yearMatch = RegExp(r'\((\d{4})\)').firstMatch(title);
    if (yearMatch != null) {
      year = int.tryParse(yearMatch.group(1)!);
    }

    final isTv = RegExp(r'season|\bs\d+\b|series|k-drama|episode|tv-show', caseSensitive: false).hasMatch(card.title) ||
        card.postUrl.contains('series') ||
        card.postUrl.contains('season');
    final mediaType = isTv ? 'tv' : 'movie';

    final coreTitle = title
        .replaceAll(RegExp(r'\{[^}]+\}'), '')
        .replaceAll(RegExp(r'\[[^\]]+\]'), '')
        .replaceAll(RegExp(r'\([^)]+\)'), '')
        .split(RegExp(r'dual\s+audio|multi-audio|full\s+movie|hindi\s+dubbed', caseSensitive: false))[0]
        .trim();

    int tmdbId = 0;
    String? backdropUrl;
    String? tmdbPosterPath;
    String? overview;

    try {
      final query = coreTitle.isNotEmpty ? coreTitle : title;
      final results = await TmdbClient.instance.searchMulti(query);
      if (results.isNotEmpty) {
        final match = results.first;
        final id = match['id'];
        if (id is int) {
          tmdbId = id;
          final poster = match['poster_path'];
          if (poster is String && poster.isNotEmpty) {
            tmdbPosterPath = poster;
          }
          final backdrop = match['backdrop_path'];
          if (backdrop is String && backdrop.isNotEmpty) {
            backdropUrl = TmdbClient.backdropUrl(backdrop);
          }
          final over = match['overview'];
          if (over is String && over.isNotEmpty) {
            overview = over;
          }
        }
      }
    } catch (e) {
      debugPrint('[MovieSiteScraperService] TMDB search error for $coreTitle: $e');
    }

    if (tmdbId <= 0) {
      tmdbId = (card.postUrl.hashCode.abs() % 900000) + 100000;
    }

    final finalPoster = card.posterUrl.isNotEmpty
        ? card.posterUrl
        : (tmdbPosterPath != null ? TmdbClient.posterUrl(tmdbPosterPath) : null);

    final item = ManifestItem(
      id: tmdbId,
      mediaType: mediaType,
      title: title,
      posterUrl: finalPoster,
      tmdbPosterPath: tmdbPosterPath,
      backdropUrl: backdropUrl,
      overview: overview,
      releaseYear: year ?? DateTime.now().year,
      voteAverage: card.rating,
      isTrending: isTrending,
      trendingRank: trendingRank,
    );

    _itemMap[item.id.toString()] = item;
    return item;
  }

  /// Live fetch Top 5 and Top 10 from VegaMovies and RogMovies homepages.
  /// Top 5: 3 from VegaMovies + 2 from RogMovies, arranged dynamically.
  /// Top 10: 5 from RogMovies + 5 from VegaMovies, arranged dynamically.
  /// Crucial: Top 5 and Top 10 must NOT contain any same posts.
  Future<Map<String, List<ManifestItem>>> fetchHomeTopLists({
    Map<String, ManifestItem>? localMap,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedTop5 != null && _cachedTop10 != null) {
      return {'top5': _cachedTop5!, 'top10': _cachedTop10!};
    }

    dev.log('[MovieSiteScraperService] Live fetching homepages from VegaMovies & RogMovies...');

    final results = await Future.wait([
      fetchHtml(vegaBaseUrl),
      fetchHtml(rogBaseUrl),
    ]);

    final vegaHtml = results[0] ?? '';
    final rogHtml = results[1] ?? '';

    final vegaCards = parseCards(vegaHtml, 'vegamovies');
    final rogCards = parseCards(rogHtml, 'rogmovies');

    dev.log('[MovieSiteScraperService] Parsed ${vegaCards.length} Vega cards and ${rogCards.length} Rog cards.');

    final top5Cards = <ScrapedSiteCard>[];
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

    int vIdx = 0;
    int rIdx = 0;

    // Top 5: 3 from VegaMovies, 2 from RogMovies
    // Dynamic Interleave: Vega[0], Rog[0], Vega[1], Rog[1], Vega[2]
    // 1. Vega
    while (vIdx < vegaCards.length && isUsed(vegaCards[vIdx])) {
      vIdx++;
    }
    if (vIdx < vegaCards.length) {
      top5Cards.add(vegaCards[vIdx]);
      markUsed(vegaCards[vIdx]);
      vIdx++;
    }

    // 2. Rog
    while (rIdx < rogCards.length && isUsed(rogCards[rIdx])) {
      rIdx++;
    }
    if (rIdx < rogCards.length) {
      top5Cards.add(rogCards[rIdx]);
      markUsed(rogCards[rIdx]);
      rIdx++;
    }

    // 3. Vega
    while (vIdx < vegaCards.length && isUsed(vegaCards[vIdx])) {
      vIdx++;
    }
    if (vIdx < vegaCards.length) {
      top5Cards.add(vegaCards[vIdx]);
      markUsed(vegaCards[vIdx]);
      vIdx++;
    }

    // 4. Rog
    while (rIdx < rogCards.length && isUsed(rogCards[rIdx])) {
      rIdx++;
    }
    if (rIdx < rogCards.length) {
      top5Cards.add(rogCards[rIdx]);
      markUsed(rogCards[rIdx]);
      rIdx++;
    }

    // 5. Vega
    while (vIdx < vegaCards.length && isUsed(vegaCards[vIdx])) {
      vIdx++;
    }
    if (vIdx < vegaCards.length) {
      top5Cards.add(vegaCards[vIdx]);
      markUsed(vegaCards[vIdx]);
      vIdx++;
    }

    final top5Items = <ManifestItem>[];
    for (int i = 0; i < top5Cards.length; i++) {
      final item = await convertToManifestItem(
        top5Cards[i],
        isTrending: true,
        trendingRank: i + 1,
        localMap: localMap,
      );
      top5Items.add(item);
    }
    _cachedTop5 = top5Items;

    // Top 10: 5 from RogMovies, 5 from VegaMovies, strictly excluding ANY post used in Top 5!
    // Dynamic Interleave: Rog[0], Vega[0], Rog[1], Vega[1], Rog[2], Vega[2], Rog[3], Vega[3], Rog[4], Vega[4]
    final top10Cards = <ScrapedSiteCard>[];

    for (int i = 0; i < 5; i++) {
      while (rIdx < rogCards.length && isUsed(rogCards[rIdx])) {
        rIdx++;
      }
      if (rIdx < rogCards.length) {
        top10Cards.add(rogCards[rIdx]);
        markUsed(rogCards[rIdx]);
        rIdx++;
      }

      while (vIdx < vegaCards.length && isUsed(vegaCards[vIdx])) {
        vIdx++;
      }
      if (vIdx < vegaCards.length) {
        top10Cards.add(vegaCards[vIdx]);
        markUsed(vegaCards[vIdx]);
        vIdx++;
      }
    }

    final top10Items = <ManifestItem>[];
    for (int i = 0; i < top10Cards.length; i++) {
      final item = await convertToManifestItem(
        top10Cards[i],
        isTrending: true,
        trendingRank: i + 1,
        localMap: localMap,
      );
      top10Items.add(item);
    }
    _cachedTop10 = top10Items;

    dev.log('[MovieSiteScraperService] Top 5 (${top5Items.length}) & Top 10 (${top10Items.length}) ready (distinct).');
    return {'top5': top5Items, 'top10': top10Items};
  }

  /// Fetch Chinese drama posts via ts-search.php or chinese-series
  Future<List<ScrapedSiteCard>> _fetchChineseCards({int page = 1}) async {
    final cards = <ScrapedSiteCard>[];
    // 1. Try ts-search.php
    try {
      final url = '$vegaBaseUrl/ts-search.php?q=Chinese&page=$page';
      final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
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

    // 2. Try /chinese-series/ (and page X)
    try {
      final csUrl = page == 1 ? '$vegaBaseUrl/chinese-series/' : '$vegaBaseUrl/chinese-series/page/$page/';
      final html = await fetchHtml(csUrl);
      if (html != null && html.isNotEmpty) {
        final htmlCards = parseCards(html, 'vegamovies');
        for (final c in htmlCards) {
          if (!cards.any((existing) => existing.postUrl == c.postUrl)) {
            cards.add(c);
          }
        }
      }
    } catch (e) {
      debugPrint('[MovieSiteScraperService] Chinese series HTML error: $e');
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

      final item = await convertToManifestItem(card, localMap: localMap);
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

