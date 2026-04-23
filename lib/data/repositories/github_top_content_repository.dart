import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import '../../domain/models/manifest_item.dart';

/// Repository that fetches "Top 5" and "Top 10" curated content lists
/// from the GitHub database. Each file is named with a position number
/// (e.g. `3_normal_movie_1239134.json`) that dictates its exact slot
/// in the UI — GitHub positions ALWAYS win over TMDB ordering.
class GitHubTopContentRepository {
  GitHubTopContentRepository._();
  static final GitHubTopContentRepository instance =
      GitHubTopContentRepository._();

  // ─── GitHub API URLs ────────────────────────────────────────────────────────
  static const _owner = 'aadil12347';
  static const _repo = 'DanieWatch_Apk_Database';
  static const _branch = 'main';

  static String _contentsUrl(String folder) =>
      'https://api.github.com/repos/$_owner/$_repo/contents/${Uri.encodeComponent(folder)}?ref=$_branch';

  static String _rawUrl(String path) =>
      'https://raw.githubusercontent.com/$_owner/$_repo/$_branch/${Uri.encodeFull(path)}';

  // ─── In-Memory Cache ───────────────────────────────────────────────────────
  Map<int, ManifestItem>? _top5Cache;
  Map<int, ManifestItem>? _top10Cache;
  DateTime? _top5CacheTime;
  DateTime? _top10CacheTime;
  static const _cacheTtl = Duration(minutes: 15);

  bool _isCacheValid(DateTime? cacheTime) {
    if (cacheTime == null) return false;
    return DateTime.now().difference(cacheTime) < _cacheTtl;
  }

  /// Clears cached data (e.g. on pull-to-refresh)
  void clearCache() {
    _top5Cache = null;
    _top10Cache = null;
    _top5CacheTime = null;
    _top10CacheTime = null;
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Fetches Top 5 curated items. Returns {position: ManifestItem}.
  /// Positions are 1-indexed (1..5).
  Future<Map<int, ManifestItem>> fetchTop5() async {
    if (_isCacheValid(_top5CacheTime) && _top5Cache != null) {
      return _top5Cache!;
    }
    try {
      _top5Cache = await _fetchFolder('Top 5');
      _top5CacheTime = DateTime.now();
      return _top5Cache!;
    } catch (e, stack) {
      dev.log('[GitHubTopContent] fetchTop5 error: $e', stackTrace: stack);
      return _top5Cache ?? {};
    }
  }

  /// Fetches Top 10 curated items. Returns {position: ManifestItem}.
  /// Positions are 1-indexed (1..10).
  Future<Map<int, ManifestItem>> fetchTop10() async {
    if (_isCacheValid(_top10CacheTime) && _top10Cache != null) {
      return _top10Cache!;
    }
    try {
      _top10Cache = await _fetchFolder('Top 10');
      _top10CacheTime = DateTime.now();
      return _top10Cache!;
    } catch (e, stack) {
      dev.log('[GitHubTopContent] fetchTop10 error: $e', stackTrace: stack);
      return _top10Cache ?? {};
    }
  }

  // ─── Internal: Fetch Folder & Parse ─────────────────────────────────────────

  Future<Map<int, ManifestItem>> _fetchFolder(String folder) async {
    final result = <int, ManifestItem>{};

    // Step 1: Get directory listing from GitHub API
    final listingUrl = _contentsUrl(folder);
    final listingRes = await http.get(
      Uri.parse(listingUrl),
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );

    if (listingRes.statusCode != 200) {
      dev.log('[GitHubTopContent] Folder listing failed: ${listingRes.statusCode}');
      return result;
    }

    final listing = jsonDecode(listingRes.body) as List<dynamic>;

    // Step 2: Filter to only .json files, parse filenames
    final entries = <_ParsedEntry>[];
    for (final item in listing) {
      final name = item['name']?.toString() ?? '';
      if (!name.endsWith('.json')) continue;

      final parsed = _parseFileName(name);
      if (parsed == null) continue;

      entries.add(_ParsedEntry(
        position: parsed.position,
        mediaType: parsed.mediaType,
        tmdbId: parsed.tmdbId,
        path: item['path']?.toString() ?? '$folder/$name',
      ));
    }

    // Step 3: Fetch each JSON file in parallel
    final futures = entries.map((entry) async {
      try {
        final rawUrl = _rawUrl(entry.path);
        final res = await http.get(Uri.parse(rawUrl));
        if (res.statusCode != 200) return null;

        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final item = _jsonToManifestItem(json, entry.mediaType);
        return MapEntry(entry.position, item);
      } catch (e) {
        dev.log('[GitHubTopContent] Failed to fetch ${entry.path}: $e');
        return null;
      }
    });

    final results = await Future.wait(futures);
    for (final entry in results) {
      if (entry != null) {
        result[entry.key] = entry.value;
      }
    }

    dev.log('[GitHubTopContent] Loaded ${result.length} items from $folder');
    return result;
  }

  // ─── Filename Parser ────────────────────────────────────────────────────────
  /// Parses "3_normal_movie_1239134.json" → (position: 3, mediaType: "movie", tmdbId: 1239134)
  /// Also handles "1_admin_tv_249765.json" patterns.
  static ({int position, String mediaType, int tmdbId})? _parseFileName(
      String name) {
    // Remove .json extension
    final base = name.replaceAll('.json', '');
    // Pattern: {position}_{admin/normal}_{movie/tv}_{tmdbId}
    final parts = base.split('_');
    if (parts.length < 4) return null;

    final position = int.tryParse(parts[0]);
    if (position == null || position < 1) return null;

    // parts[1] = "normal" or "admin" (ignored for display)
    // parts[2] = "movie" or "tv"
    final mediaType = parts[2];
    if (mediaType != 'movie' && mediaType != 'tv') return null;

    // parts[3] = tmdbId (may contain extra underscores in rare edge cases)
    final tmdbId = int.tryParse(parts[3]);
    if (tmdbId == null) return null;

    return (position: position, mediaType: mediaType, tmdbId: tmdbId);
  }

  // ─── JSON → ManifestItem Converter ──────────────────────────────────────────
  /// Converts a GitHub Top-content JSON file into a ManifestItem.
  /// The JSON structure matches streaming_links format:
  /// {id, type, title, poster, backdrop, year, result, language, watch/seasons}
  static ManifestItem _jsonToManifestItem(
      Map<String, dynamic> json, String mediaType) {
    final id = int.tryParse(json['id']?.toString() ?? '') ?? 0;

    // Parse language array
    final langRaw = json['language'];
    final languages = <String>[];
    if (langRaw is List) {
      languages.addAll(langRaw.map((e) => e.toString()));
    } else if (langRaw is String && langRaw.isNotEmpty) {
      languages.add(langRaw);
    }

    return ManifestItem(
      id: id,
      mediaType: json['type']?.toString() ?? mediaType,
      title: json['title']?.toString() ?? 'Unknown',
      posterUrl: json['poster']?.toString(),
      backdropUrl: json['backdrop']?.toString(),
      releaseYear: int.tryParse(json['year']?.toString() ?? ''),
      result: json['result']?.toString(),
      language: languages,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: (json['vote_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Internal helper for parsed file entries
class _ParsedEntry {
  final int position;
  final String mediaType;
  final int tmdbId;
  final String path;

  _ParsedEntry({
    required this.position,
    required this.mediaType,
    required this.tmdbId,
    required this.path,
  });
}
