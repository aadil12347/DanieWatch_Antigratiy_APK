// lib/services/google_sheets_catalog_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Cloud Catalog Service: Fetches series seasons, multi-resolution episodes,
// and batch zip archives from Google Sheets (via Apps Script Web App API)
// or embedded cloud manifest.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/env.dart';
import 'extraction/site_post_extractor.dart';
import 'embedded_catalog.dart';

class CatalogEpisode {
  final int season;
  final int episode;
  final String title;
  final String vcloudUrl;
  final String url480p;
  final String url720p;
  final String url1080p;
  final String? size480p;
  final String? size720p;
  final String? size1080p;

  CatalogEpisode({
    required this.season,
    required this.episode,
    required this.title,
    required this.vcloudUrl,
    this.url480p = '',
    this.url720p = '',
    this.url1080p = '',
    this.size480p,
    this.size720p,
    this.size1080p,
  });

  static String _filterVcloud(String? url) {
    if (url == null) return '';
    final trimmed = url.trim();
    if (trimmed.contains('vcloud.fit') || trimmed.contains('hubcloud')) {
      return trimmed;
    }
    return '';
  }

  factory CatalogEpisode.fromJson(Map<String, dynamic> json) {
    final s = int.tryParse(json['season']?.toString() ?? '') ?? 1;
    final ep = int.tryParse(json['episode']?.toString() ?? '') ?? 1;
    final labelStr = json['label']?.toString();
    final title = (labelStr != null && labelStr.isNotEmpty)
        ? labelStr
        : 'Episode $ep';
    final vcloud = _filterVcloud(json['vcloud_url']?.toString());
    final u480 = _filterVcloud(json['url_480p']?.toString());
    final u720 = _filterVcloud(json['url_720p']?.toString());
    final u1080 = _filterVcloud(json['url_1080p']?.toString());

    final primary = vcloud.isNotEmpty
        ? vcloud
        : (u720.isNotEmpty ? u720 : (u480.isNotEmpty ? u480 : u1080));

    return CatalogEpisode(
      season: s,
      episode: ep,
      title: title,
      vcloudUrl: primary,
      url480p: u480,
      url720p: u720,
      url1080p: u1080,
      size480p: json['size_480p']?.toString(),
      size720p: json['size_720p']?.toString(),
      size1080p: json['size_1080p']?.toString(),
    );
  }
}

class CatalogBatchZip {
  final int season;
  final String quality;
  final String size;
  final String vcloudUrl;
  final String label;

  CatalogBatchZip({
    required this.season,
    required this.quality,
    required this.size,
    required this.vcloudUrl,
    required this.label,
  });

  factory CatalogBatchZip.fromJson(Map<String, dynamic> json) {
    return CatalogBatchZip(
      season: int.tryParse(json['season']?.toString() ?? '') ?? 1,
      quality: json['quality']?.toString() ?? '',
      size: json['size']?.toString() ?? '',
      vcloudUrl: json['vcloud_url']?.toString() ?? json['href']?.toString() ?? '',
      label: json['label']?.toString() ?? json['text']?.toString() ?? 'Batch/Zip',
    );
  }
}

class SeriesCatalogData {
  final int tmdbId;
  final String title;
  final Map<int, List<CatalogEpisode>> seasonEpisodes;
  final Map<int, List<CatalogBatchZip>> seasonBatchZips;
  final List<CatalogBatchZip> allBatchZips;

  SeriesCatalogData({
    required this.tmdbId,
    required this.title,
    required this.seasonEpisodes,
    required this.seasonBatchZips,
    required this.allBatchZips,
  });

  bool hasSeason(int seasonNum) => seasonEpisodes.containsKey(seasonNum) || seasonBatchZips.containsKey(seasonNum);

  List<int> get availableSeasons {
    final set = <int>{...seasonEpisodes.keys, ...seasonBatchZips.keys};
    final list = set.toList()..sort();
    return list;
  }

  List<NextdriveEpisode> getEpisodesForSeason(int seasonNum, {String? posterUrl}) {
    final eps = seasonEpisodes[seasonNum] ?? [];
    return eps.asMap().entries.map((entry) {
      final idx = entry.key;
      final ep = entry.value;

      final resMap = <String, String>{};
      if (ep.url480p.isNotEmpty) resMap['480p'] = ep.url480p;
      if (ep.url720p.isNotEmpty) resMap['720p'] = ep.url720p;
      if (ep.url1080p.isNotEmpty) resMap['1080p'] = ep.url1080p;

      final resSizes = <String, String>{};
      if (ep.size480p != null) resSizes['480p'] = ep.size480p!;
      if (ep.size720p != null) resSizes['720p'] = ep.size720p!;
      if (ep.size1080p != null) resSizes['1080p'] = ep.size1080p!;

      final primaryUrl = ep.vcloudUrl.isNotEmpty
          ? ep.vcloudUrl
          : (resMap['720p'] ?? resMap['480p'] ?? resMap['1080p'] ?? '');

      return NextdriveEpisode(
        title: ep.title,
        vcloudUrl: primaryUrl,
        index: idx,
        episodeNumber: ep.episode,
        thumbnailUrl: posterUrl,
        otherResolutions: resMap.isNotEmpty ? resMap : null,
        otherResolutionSizes: resSizes.isNotEmpty ? resSizes : null,
      );
    }).toList();
  }

  List<SitePostButton> getBatchButtonsForSeason(int seasonNum) {
    final list = seasonBatchZips[seasonNum] ?? [];
    return list.map((bz) {
      return SitePostButton(
        text: bz.label.isNotEmpty ? bz.label : '⚡ Batch/Zip [${bz.size}]',
        href: bz.vcloudUrl,
        quality: bz.quality,
        seasonNumber: bz.season,
        isBatchZip: true,
        sizeLabel: bz.size,
      );
    }).toList();
  }

  List<SitePostButton> getAllButtons() {
    final result = <SitePostButton>[];
    for (final bz in allBatchZips) {
      result.add(SitePostButton(
        text: bz.label.isNotEmpty ? bz.label : '⚡ Batch/Zip [${bz.size}]',
        href: bz.vcloudUrl,
        quality: bz.quality,
        seasonNumber: bz.season,
        isBatchZip: true,
        sizeLabel: bz.size,
      ));
    }
    return result;
  }
}

class GoogleSheetsCatalogService {
  GoogleSheetsCatalogService._();
  static final GoogleSheetsCatalogService instance = GoogleSheetsCatalogService._();

  static const String prefCustomUrlKey = 'custom_google_sheets_catalog_url';
  final Map<int, SeriesCatalogData> _cache = {};

  /// Returns cached or fetched catalog data for a TMDB ID.
  Future<SeriesCatalogData?> getSeriesData(int tmdbId) async {
    if (_cache.containsKey(tmdbId)) {
      return _cache[tmdbId];
    }

    // 1. Try remote Google Sheets API if URL is configured
    final remoteUrl = await _resolveCatalogApiUrl();
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      try {
        final queryUrl = remoteUrl.contains('?')
            ? '$remoteUrl&tmdb_id=$tmdbId'
            : '$remoteUrl?tmdb_id=$tmdbId';
        debugPrint('[GoogleSheetsCatalog] Fetching from API: $queryUrl');
        final response = await http.get(Uri.parse(queryUrl)).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200 && response.body.isNotEmpty) {
          final decoded = jsonDecode(response.body);
          final data = _parseApiResponse(decoded, tmdbId);
          if (data != null) {
            _cache[tmdbId] = data;
            debugPrint('[GoogleSheetsCatalog] Loaded TMDB $tmdbId from remote Google Sheet: ${data.availableSeasons.length} seasons');
            return data;
          }
        }
      } catch (e) {
        debugPrint('[GoogleSheetsCatalog] Remote fetch error: $e');
      }
    }

    // 2. Check embedded catalog fallback (Game of Thrones, Vikings, Breaking Bad)
    if (EmbeddedCatalog.isAvailable(tmdbId)) {
      final embedded = EmbeddedCatalog.getCatalog(tmdbId);
      if (embedded != null) {
        _cache[tmdbId] = embedded;
        debugPrint('[GoogleSheetsCatalog] Serving TMDB $tmdbId from embedded catalog (${embedded.availableSeasons.length} seasons)');
        return embedded;
      }
    }

    return null;
  }

  /// Sets a custom Google Sheets Apps Script URL in SharedPreferences.
  Future<void> setCustomApiUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url.trim().isEmpty) {
      await prefs.remove(prefCustomUrlKey);
    } else {
      await prefs.setString(prefCustomUrlKey, url.trim());
    }
    _cache.clear();
  }

  Future<String?> _resolveCatalogApiUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final custom = prefs.getString(prefCustomUrlKey);
      if (custom != null && custom.trim().isNotEmpty) {
        return custom.trim();
      }
    } catch (_) {}

    if (Env.googleSheetsCatalogUrl.isNotEmpty) {
      return Env.googleSheetsCatalogUrl;
    }
    return null;
  }

  SeriesCatalogData? _parseApiResponse(dynamic json, int targetTmdbId) {
    if (json == null) return null;

    dynamic rawSeries;
    if (json is Map) {
      if (json['data'] != null) {
        rawSeries = json['data'];
      } else {
        rawSeries = json;
      }
    } else if (json is List) {
      // Flat list of rows from CSV or flat Apps Script
      return _parseFlatRows(json, targetTmdbId);
    }

    if (rawSeries is List) {
      return _parseFlatRows(rawSeries, targetTmdbId);
    }

    if (rawSeries is Map) {
      final sMap = rawSeries as Map<String, dynamic>;
      final title = sMap['title']?.toString() ?? 'Series';
      final seasonEps = <int, List<CatalogEpisode>>{};
      final seasonBatch = <int, List<CatalogBatchZip>>{};
      final allBatch = <CatalogBatchZip>[];

      // Parse seasons map or list
      final seasonsObj = sMap['seasons'];
      if (seasonsObj is Map) {
        for (final entry in seasonsObj.entries) {
          final sNum = int.tryParse(entry.key.toString()) ?? 1;
          final sData = entry.value as Map<String, dynamic>;
          final epList = (sData['episodes'] as List?)
                  ?.map((e) => CatalogEpisode.fromJson(Map<String, dynamic>.from(e)))
                  .toList() ??
              [];
          seasonEps[sNum] = epList;

          final bList = (sData['batch_zips'] as List?)
                  ?.map((b) => CatalogBatchZip.fromJson(Map<String, dynamic>.from(b)))
                  .toList() ??
              [];
          seasonBatch[sNum] = bList;
          allBatch.addAll(bList);
        }
      }

      return SeriesCatalogData(
        tmdbId: targetTmdbId,
        title: title,
        seasonEpisodes: seasonEps,
        seasonBatchZips: seasonBatch,
        allBatchZips: allBatch,
      );
    }

    return null;
  }

  SeriesCatalogData? _parseFlatRows(List rows, int targetTmdbId) {
    final seasonEps = <int, List<CatalogEpisode>>{};
    final seasonBatch = <int, List<CatalogBatchZip>>{};
    final allBatch = <CatalogBatchZip>[];
    String title = 'Series';

    for (final row in rows) {
      if (row is! Map) continue;
      final rowMap = Map<String, dynamic>.from(row);
      final tmdbId = int.tryParse(rowMap['tmdb_id']?.toString() ?? '');
      if (tmdbId != null && tmdbId != targetTmdbId) continue;

      if (rowMap['title'] != null) {
        title = rowMap['title'].toString();
      }

      final type = rowMap['type']?.toString().toLowerCase() ?? '';
      final sNum = int.tryParse(rowMap['season']?.toString() ?? '') ?? 1;

      if (type == 'batch_zip') {
        final bz = CatalogBatchZip.fromJson(rowMap);
        seasonBatch.putIfAbsent(sNum, () => []).add(bz);
        allBatch.add(bz);
      } else if (type == 'episode') {
        final ep = CatalogEpisode.fromJson(rowMap);
        seasonEps.putIfAbsent(sNum, () => []).add(ep);
      }
    }

    if (seasonEps.isEmpty && allBatch.isEmpty) return null;

    return SeriesCatalogData(
      tmdbId: targetTmdbId,
      title: title,
      seasonEpisodes: seasonEps,
      seasonBatchZips: seasonBatch,
      allBatchZips: allBatch,
    );
  }
}
