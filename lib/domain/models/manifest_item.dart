/// Represents a single item in the GitHub index.json manifest.
/// This is the single source of truth for what's available in the app.
/// Items NOT in the manifest are NEVER rendered (DB-only visibility policy).
class ManifestItem {
  final int id;
  final String mediaType;
  final String title;
  final String? posterUrl;
  final String? backdropUrl;
  final String? logoUrl;
  final String? hoverImageUrl;
  final double voteAverage;
  final int voteCount;
  final int? releaseYear;
  final String? originalLanguage;
  final List<String> originCountry;
  final List<int> genreIds;
  final List<String> genres;
  final String? overview;
  final String? tagline;
  final int? runtime;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;
  final String? status;
  final String? imdbId;
  final List<String> language;
  final String? result;
  final bool isTrending;
  final bool isPopular;
  final bool is3rdPartyHosted;
  final int? trendingRank;
  final String? tmdbPosterPath;
  final String? tmdbBackdropPath;
  final String? releaseDate; // ISO format: "2026-05-15" from TMDB
  final String? postUrl; // Detail page URL on source site (e.g. VegaMovies/RogMovies)
  final String? rawTitle; // Original scraped title containing language, season, quality tags

  ManifestItem({
    required this.id,
    required this.mediaType,
    required this.title,
    this.rawTitle,
    this.posterUrl,
    this.backdropUrl,
    this.logoUrl,
    this.hoverImageUrl,
    this.voteAverage = 0.0,
    this.voteCount = 0,
    this.releaseYear,
    this.originalLanguage,
    this.originCountry = const [],
    this.genreIds = const [],
    this.genres = const [],
    this.overview,
    this.tagline,
    this.runtime,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.status,
    this.imdbId,
    this.language = const [],
    this.result,
    this.isTrending = false,
    this.isPopular = false,
    this.is3rdPartyHosted = false,
    this.trendingRank,
    this.tmdbPosterPath,
    this.tmdbBackdropPath,
    this.releaseDate,
    this.postUrl,
  });

  /// Safe display year — checks releaseYear, parses releaseDate, or extracts 4-digit year from title
  int? get displayYear {
    if (releaseYear != null && releaseYear! > 0) return releaseYear;
    if (releaseDate != null && releaseDate!.isNotEmpty) {
      final m = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(releaseDate!);
      if (m != null) return int.tryParse(m.group(1)!);
      final dt = DateTime.tryParse(releaseDate!);
      if (dt != null) return dt.year;
    }
    final m = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(rawTitle ?? title);
    if (m != null) return int.tryParse(m.group(1)!);
    return null;
  }

  // ─── Post Title Cleaning & Parsing ──────────────────────────────────────────
  
  /// Cleans raw VegaMovies / RogMovies post title into pure clean title.
  static String cleanPostTitle(String raw) {
    var t = raw
        .replaceAll(RegExp(r'&#038;', caseSensitive: false), '&')
        .replaceAll(RegExp(r'&amp;', caseSensitive: false), '&')
        .replaceAll(RegExp(r'&#8211;', caseSensitive: false), '-')
        .replaceAll(RegExp(r'&#8217;', caseSensitive: false), "'")
        .replaceAll(RegExp(r'&#8216;', caseSensitive: false), "'")
        .replaceAll(RegExp(r'&quot;', caseSensitive: false), '"')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (t.toLowerCase().startsWith('download ')) {
      t = t.substring(9).trim();
    }

    // Remove curly and square brackets: {S01E04 Added}, [Hindi DD5.1], [400MB], etc.
    t = t.replaceAll(RegExp(r'\s*[\{\[].*?[\}\]]'), ' ');
    // Remove season or episode in parentheses: (Season 1 - 6), (Season 2), (Episode 1 - 5 Added), (S01), (S1-S2)
    t = t.replaceAll(RegExp(r'\s*\((?:Season|\d{4}|S\d+|Episode).*?\)', caseSensitive: false), ' ');
    // Remove standalone season tags: "- Season 5"
    t = t.replaceAll(RegExp(r'\s*[-–]\s*Season\s*\d+', caseSensitive: false), ' ');
    // Remove isolated year in parentheses: (2026)
    t = t.replaceAll(RegExp(r'\s*\(\d{4}\)'), ' ');
    // Remove trailing specs starting with colon or dash: ": English with Substitle", "- Episode 1 - 5 Added"
    t = t.replaceAll(
      RegExp(r'\s*[:\-–]\s*(?:English|Hindi|Dual|Multi|Tamil|Telugu|Punjabi|Season|Substitle|Subtitle|Episode).*$', caseSensitive: false),
      '',
    );
    // Remove common release words and quality tags
    t = t.replaceAll(
      RegExp(
        r'\s*(?:Full Movie|Complete Web Series|WEB-Series|Anime Series|TV-Show|Full Indian Show|Full WWE Show|WEB-DL|WeB-DL|HDTC|PreDVD|HDRip|BluRay|x264|x265|HEVC|H\.264|HQ|UnCut|ORG\.?|LiNE|Hindi|Dual Audio|Multi-Audio|Tamil|Telugu|Punjabi|JHS|Sony-Liv|SonyLiv|Netflix|AMZN|Zee5|JioHotstar|–|\*No Ads\*|480p|720p|1080p|2160p|10Bit).*$',
        caseSensitive: false,
      ),
      '',
    );
    t = t.replaceAll(RegExp(r'\s*\(\d{4}\)'), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  /// Display-ready title with year, season, audio, and resolution info stripped.
  /// e.g. "Download The Punisher {S01E04 Added} Dual Audio..." → "The Punisher"
  String get cleanTitle {
    final cleaned = cleanPostTitle(rawTitle ?? title);
    return cleaned.isNotEmpty ? cleaned : title;
  }

  /// Season and episode added badge displayed over poster top-right.
  /// e.g. "S04 Episode 6 Added", "S01 Episode 04 Added", "S01-S02", "S01".
  String? get seasonDetail {
    final source = rawTitle ?? title;

    // 1. Episode added pattern: e.g. {S01E04 Added}, [S01 E01 Added], [S20E24 Added], [E18 Added], (Episode 1 - 5 Added), {S06E01-3 Added}
    final epAddedMatch = RegExp(
      r'[\{\[\(]\s*(?:(S\d+)\s*)?(?:E|Ep|Episode)\s*(\d+(?:\s*[-–]\s*\d+)?)\s*(?:Added)?\s*[\}\]\)]',
      caseSensitive: false,
    ).firstMatch(source);

    // 2. Base season pattern: e.g. (Season 1 - 6), (Season 1 – 2), (Season 20), (Season 1), (S01), (S1-S2), - Season 5
    String? seasonText;
    final seasonMatch = RegExp(
      r'(?:\(|\b)(?:Season|S)\s*(\d+)(?:\s*[-–]\s*(?:Season|S)?\s*(\d+))?\s*(?:\)|\b)',
      caseSensitive: false,
    ).firstMatch(source);

    if (seasonMatch != null) {
      final s1 = int.tryParse(seasonMatch.group(1) ?? '');
      final s2 = int.tryParse(seasonMatch.group(2) ?? '');
      if (s1 != null && s2 != null) {
        seasonText = 'S${s1.toString().padLeft(2, '0')}-S${s2.toString().padLeft(2, '0')}';
      } else if (s1 != null) {
        seasonText = 'S${s1.toString().padLeft(2, '0')}';
      }
    }

    if (epAddedMatch != null) {
      final sTag = epAddedMatch.group(1);
      final rawEpNum = epAddedMatch.group(2)!.trim();
      
      // Format episode number nicely, e.g. "5" -> "E05", "04" -> "E04", "1 - 5" -> "E01-05"
      String epFormatted;
      if (rawEpNum.contains(RegExp(r'[-–]'))) {
        final parts = rawEpNum.split(RegExp(r'\s*[-–]\s*'));
        if (parts.length == 2) {
          final p1 = int.tryParse(parts[0]);
          final p2 = int.tryParse(parts[1]);
          if (p1 != null && p2 != null) {
            epFormatted = 'E${p1.toString().padLeft(2, '0')}-${p2.toString().padLeft(2, '0')}';
          } else {
            epFormatted = 'E$rawEpNum';
          }
        } else {
          epFormatted = 'E$rawEpNum';
        }
      } else {
        final epInt = int.tryParse(rawEpNum);
        epFormatted = epInt != null ? 'E${epInt.toString().padLeft(2, '0')}' : 'E$rawEpNum';
      }

      String sPrefix = '';
      // If seasonText has a range like S01-S06, prioritize the full range over single sTag like S06
      if (seasonText != null && seasonText.contains('-')) {
        sPrefix = seasonText;
      } else if (sTag != null && sTag.isNotEmpty) {
        final sInt = int.tryParse(sTag.replaceAll(RegExp(r'\D'), ''));
        sPrefix = sInt != null ? 'S${sInt.toString().padLeft(2, '0')}' : sTag.toUpperCase();
      } else if (seasonText != null) {
        sPrefix = seasonText;
      }

      if (sPrefix.isNotEmpty) {
        return '$sPrefix $epFormatted New!';
      } else {
        return '$epFormatted New!';
      }
    }

    if (seasonText != null) {
      return seasonText;
    }

    // Also check pattern like (S1-S2) or (S01) from manifest
    final manifestSeasonMatch = RegExp(r'\((S\d+(?:-S?\d+)?)\)', caseSensitive: false).firstMatch(source);
    if (manifestSeasonMatch != null) {
      return manifestSeasonMatch.group(1)!.toUpperCase();
    }

    if (numberOfSeasons != null && numberOfSeasons! > 1) {
      return 'S01-S${numberOfSeasons!.toString().padLeft(2, '0')}';
    } else if (numberOfSeasons == 1) {
      return 'S01';
    }

    return null;
  }

  /// Deduplication key used when merging multiple site indices.
  /// Key = tmdbId + mediaType + seasonDetail (so different seasons are kept).
  String get deduplicationKey => '${id}_${mediaType}_${seasonDetail ?? ""}';

  /// Helper to extract clean title, year, and mediaType in one pass.
  static ParsedPostMetadata parsePostTitle(String raw) {
    final clean = cleanPostTitle(raw);
    
    int? year;
    final yearMatch = RegExp(r'\((\d{4})\)|\b(19\d\d|20\d\d)\b').firstMatch(raw);
    if (yearMatch != null) {
      year = int.tryParse(yearMatch.group(1) ?? yearMatch.group(2) ?? '');
    }

    final isTv = RegExp(r'season|\bs\d+\b|series|k-drama|episode|tv-show|anime series', caseSensitive: false).hasMatch(raw);
    final mediaType = isTv ? 'tv' : 'movie';

    return ParsedPostMetadata(
      cleanTitle: clean.isNotEmpty ? clean : raw,
      year: year,
      mediaType: mediaType,
    );
  }


  static int? _safeInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  /// Safe double parser — handles both num and String values from JSON
  static double _safeDouble(dynamic value, [double fallback = 0.0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  // Filter out empty image URLs — keep all formats, let widget handle fallbacks
  static String? _sanitizePosterUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return url;
  }

  static const Map<int, String> _genreMap = {
    28: 'Action', 12: 'Adventure', 16: 'Animation', 35: 'Comedy',
    80: 'Crime', 99: 'Documentary', 18: 'Drama', 10751: 'Family',
    14: 'Fantasy', 36: 'History', 27: 'Horror', 10402: 'Music',
    9648: 'Mystery', 10749: 'Romance', 878: 'Science Fiction',
    53: 'Thriller', 10752: 'War', 37: 'Western',
    // TV genres
    10759: 'Action & Adventure', 10762: 'Kids', 10763: 'News',
    10764: 'Reality', 10765: 'Sci-Fi & Fantasy', 10766: 'Soap',
    10767: 'Talk', 10768: 'War & Politics',
  };

  static final Map<String, int> _reverseGenreMap = {
    'action': 28,
    'adventure': 12,
    'animation': 16,
    'comedy': 35,
    'crime': 80,
    'documentary': 99,
    'drama': 18,
    'family': 10751,
    'fantasy': 14,
    'history': 36,
    'horror': 27,
    'music': 10402,
    'mystery': 9648,
    'romance': 10749,
    'science fiction': 878,
    'sci-fi': 878,
    'thriller': 53,
    'war': 10752,
    'western': 37,
    'action & adventure': 10759,
    'kids': 10762,
    'news': 10763,
    'reality': 10764,
    'sci-fi & fantasy': 10765,
    'soap': 10766,
    'talk': 10767,
    'war & politics': 10768,
  };

  /// Prioritized display language for card badges according to user rules:
  /// - If Hindi only, or Hindi+English, or any other language with Hindi -> "Hindi"
  /// - If English only -> "English"
  /// - If neither Hindi nor English, but another language is present in title -> that language (e.g. "Punjabi", "Tamil", "Telugu", etc.)
  /// - If English subtitles mentioned with no other language -> "English Subtitles"
  /// - Falls back to manifest language / original language
  String get displayLanguage {
    final sourceText = '${rawTitle ?? ""} $title';
    final lower = sourceText.toLowerCase();

    // 1. Hindi priority (Hindi alone, Hindi+English, or any other language with Hindi)
    if (lower.contains('hindi')) {
      return 'Hindi';
    }

    // Known other languages to detect in title
    const otherLanguages = [
      'Punjabi', 'Tamil', 'Telugu', 'Malayalam', 'Kannada', 'Bengali', 'Marathi',
      'Gujarati', 'Urdu', 'Korean', 'Japanese', 'Chinese', 'Spanish', 'French',
      'German', 'Russian', 'Italian', 'Turkish', 'Thai', 'Indonesian', 'Vietnamese',
      'Arabic', 'Portuguese'
    ];

    String? foundOtherLang;
    for (final l in otherLanguages) {
      if (lower.contains(l.toLowerCase())) {
        foundOtherLang = l;
        break;
      }
    }

    final hasEnglish = lower.contains('english') || RegExp(r'\beng\b').hasMatch(lower);

    final isSubtitlesOnly = (lower.contains('substitle') || lower.contains('subtitle') || lower.contains('esub')) &&
        !lower.contains('dual audio') &&
        !lower.contains('multi-audio') &&
        !lower.contains('multi audio') &&
        !lower.contains('english -') &&
        !lower.contains('english audio') &&
        !RegExp(r'[:\-–]\s*english with substitle', caseSensitive: false).hasMatch(lower) &&
        !RegExp(r'\benglish\s*\+').hasMatch(lower) &&
        !RegExp(r'\+\s*english').hasMatch(lower);

    // If another language is present and English is only mentioned as subtitles
    if (foundOtherLang != null && isSubtitlesOnly) {
      return foundOtherLang;
    }

    // If English only (audio)
    if (hasEnglish) {
      return 'English';
    }

    // If another language is present
    if (foundOtherLang != null) {
      return foundOtherLang;
    }

    // If English subtitle is mentioned and no other language is written
    if (lower.contains('subtitle') || lower.contains('substitle') || lower.contains('esub') || lower.contains('sub')) {
      return 'English Subtitles';
    }

    // Fallback to item.language list
    if (language.isNotEmpty) {
      for (final l in language) {
        if (l.toLowerCase() == 'hindi') return 'Hindi';
      }
      for (final l in language) {
        if (l.toLowerCase() == 'english') return 'English';
      }
      final first = language.first;
      if (first.isNotEmpty) {
        return first[0].toUpperCase() + first.substring(1).toLowerCase();
      }
    }

    // Fallback to originalLanguage code
    if (originalLanguage != null && originalLanguage!.isNotEmpty) {
      final code = originalLanguage!.toLowerCase();
      const codeMap = {
        'hi': 'Hindi',
        'en': 'English',
        'pa': 'Punjabi',
        'ta': 'Tamil',
        'te': 'Telugu',
        'ml': 'Malayalam',
        'kn': 'Kannada',
        'bn': 'Bengali',
        'mr': 'Marathi',
        'ur': 'Urdu',
        'ko': 'Korean',
        'ja': 'Japanese',
        'zh': 'Chinese',
        'es': 'Spanish',
        'fr': 'French',
        'de': 'German',
        'ru': 'Russian',
      };
      if (codeMap.containsKey(code)) {
        return codeMap[code]!;
      }
    }

    return '';
  }

  factory ManifestItem.fromArray(List<dynamic> arr) {
    final rawId = arr.isNotEmpty ? arr[0] : null;
    int id;
    if (rawId is int) {
      id = rawId;
    } else if (rawId != null) {
      final parsed = int.tryParse(rawId.toString());
      id = parsed ?? (rawId.toString().hashCode & 0x7FFFFFFF);
    } else {
      id = 0;
    }

    final String title = arr.length > 1 ? (arr[1] ?? '').toString() : '';
    final String mediaType = arr.length > 2 ? (arr[2] ?? 'movie').toString() : 'movie';
    final String originalLanguage = arr.length > 3 ? (arr[3] ?? '').toString().trim().toLowerCase() : '';
    
    final List<String> originCountry = arr.length > 4 && arr[4] is List<dynamic>
        ? (arr[4] as List<dynamic>).map((e) => e.toString().trim().toUpperCase()).toList()
        : const [];
        
    final List<String> language = arr.length > 5 && arr[5] is List<dynamic>
        ? (arr[5] as List<dynamic>).map((e) => e.toString()).toList()
        : const [];
        
    final List<String> genres = arr.length > 6 && arr[6] is List<dynamic>
        ? (arr[6] as List<dynamic>).map((e) => e.toString()).toList()
        : const [];
        
    final List<int> genreIds = genres
        .map((g) => _reverseGenreMap[g.toLowerCase()])
        .whereType<int>()
        .toList();

    final String imdbId = arr.length > 7 ? (arr[7] ?? '').toString() : '';
    final String releaseDate = arr.length > 8 ? (arr[8] ?? '').toString() : '';
    int? releaseYear;
    if (releaseDate.length >= 4) {
      releaseYear = int.tryParse(releaseDate.substring(0, 4));
    }

    return ManifestItem(
      id: id,
      mediaType: mediaType,
      title: title,
      rawTitle: title,
      voteAverage: 0.0,
      voteCount: 0,
      releaseYear: releaseYear,
      originalLanguage: originalLanguage.isNotEmpty ? originalLanguage : null,
      originCountry: originCountry,
      genreIds: genreIds,
      genres: genres,
      imdbId: imdbId.isNotEmpty ? imdbId : null,
      language: language,
      releaseDate: releaseDate.isNotEmpty ? releaseDate : null,
      posterUrl: null,
      backdropUrl: null,
    );
  }

  factory ManifestItem.fromJson(Map<String, dynamic> json) {
    // Convert string IDs (ULIDs like "0HHVROFDOD9M80V12IHZQ345F2") to stable positive ints
    final rawId = json['id'];
    int id;
    if (rawId is int) {
      id = rawId;
    } else if (rawId != null) {
      final parsed = int.tryParse(rawId.toString());
      id = parsed ?? (rawId.toString().hashCode & 0x7FFFFFFF);
    } else {
      id = 0;
    }
    return ManifestItem(
      id: id,
      mediaType: (json['media_type'] ?? json['type'] ?? 'movie').toString(),
      title: (json['title'] ?? '').toString(),
      rawTitle: json['raw_title']?.toString(),
      posterUrl: _sanitizePosterUrl((json['poster_url'] ?? json['poster'])?.toString()),
      backdropUrl: _sanitizePosterUrl((json['backdrop_url'] ?? json['backdrop'])?.toString()),
      logoUrl: json['logo_url']?.toString(),
      hoverImageUrl: json['hover_image_url']?.toString(),
      voteAverage: _safeDouble(json['vote_average']),
      voteCount: _safeInt(json['vote_count']) ?? 0,
      releaseYear: _safeInt(json['release_year'] ?? json['year']),
      originalLanguage: json['original_language']?.toString().trim().toLowerCase(),
      originCountry: ((json['origin_country'] ?? json['country']) as List<dynamic>?)
              ?.map((e) => e.toString().trim().toUpperCase())
              .toList() ??
          [],
      genreIds: (json['genre_ids'] as List<dynamic>?)
              ?.map((e) => _safeInt(e) ?? 0)
              .toList() ??
          [],
      genres: (json['genres'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      overview: json['overview']?.toString(),
      tagline: json['tagline']?.toString(),
      runtime: _safeInt(json['runtime']),
      numberOfSeasons: _safeInt(json['number_of_seasons']),
      numberOfEpisodes: _safeInt(json['number_of_episodes']),
      status: json['status']?.toString(),
      imdbId: json['imdb_id']?.toString(),
      language: (json['language'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      result: json['result']?.toString(),
      isTrending: json['is_trending'] == true,
      isPopular: json['is_popular'] == true,
      trendingRank: _safeInt(json['trending_rank']),
      tmdbPosterPath: json['tmdb_poster_path']?.toString(),
      tmdbBackdropPath: json['tmdb_backdrop_path']?.toString(),
      releaseDate: json['release_date']?.toString(),
      postUrl: json['post_url']?.toString(),
    );
  }

  /// Create a ManifestItem from a TMDB trending API response item.
  /// These are display-only items used to fill empty Top 5/10 slots.
  factory ManifestItem.fromTmdbTrending(Map<String, dynamic> json, {int? rank}) {
    final int id = _safeInt(json['id']) ?? 0;
    final String mediaType = (json['media_type'] ?? 'movie').toString();
    final String title = (json['title'] ?? json['name'] ?? '').toString();
    final String? posterPath = json['poster_path']?.toString();
    final String? backdropPath = json['backdrop_path']?.toString();
    final String? releaseDate = (json['release_date'] ?? json['first_air_date'])?.toString();
    int? releaseYear;
    if (releaseDate != null && releaseDate.length >= 4) {
      releaseYear = int.tryParse(releaseDate.substring(0, 4));
    }
    final List<int> genreIds = (json['genre_ids'] as List<dynamic>?)
            ?.map((e) => _safeInt(e) ?? 0)
            .toList() ??
        [];
    final List<String> genres = genreIds
        .map((gid) => _genreMap[gid])
        .whereType<String>()
        .toList();

    return ManifestItem(
      id: id,
      mediaType: mediaType,
      title: title,
      rawTitle: title,
      posterUrl: posterPath != null ? 'https://image.tmdb.org/t/p/w342$posterPath' : null,
      backdropUrl: backdropPath != null ? 'https://image.tmdb.org/t/p/w780$backdropPath' : null,
      voteAverage: _safeDouble(json['vote_average']),
      voteCount: _safeInt(json['vote_count']) ?? 0,
      releaseYear: releaseYear,
      originalLanguage: json['original_language']?.toString(),
      originCountry: (json['origin_country'] as List<dynamic>?)
              ?.map((e) => e.toString().toUpperCase())
              .toList() ??
          [],
      genreIds: genreIds,
      genres: genres,
      overview: json['overview']?.toString(),
      isTrending: true,
      trendingRank: rank,
      tmdbPosterPath: posterPath,
      tmdbBackdropPath: backdropPath,
      releaseDate: releaseDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'media_type': mediaType,
      'title': title,
      'poster_url': posterUrl,
      'backdrop_url': backdropUrl,
      'logo_url': logoUrl,
      'hover_image_url': hoverImageUrl,
      'vote_average': voteAverage,
      'vote_count': voteCount,
      'release_year': releaseYear,
      'original_language': originalLanguage,
      'origin_country': originCountry,
      'genre_ids': genreIds,
      'genres': genres,
      'overview': overview,
      'tagline': tagline,
      'runtime': runtime,
      'number_of_seasons': numberOfSeasons,
      'number_of_episodes': numberOfEpisodes,
      'status': status,
      'imdb_id': imdbId,
      'language': language,
      'result': result,
      'is_trending': isTrending,
      'is_popular': isPopular,
      'trending_rank': trendingRank,
      'tmdb_poster_path': tmdbPosterPath,
      'tmdb_backdrop_path': tmdbBackdropPath,
      'release_date': releaseDate,
      if (postUrl != null) 'post_url': postUrl,
      if (rawTitle != null) 'raw_title': rawTitle,
    };
  }

  /// Effective poster URL: skip .avif (unsupported), prefer TMDB fallback
  String? get effectivePosterUrl {
    if (posterUrl != null && posterUrl!.isNotEmpty && !posterUrl!.toLowerCase().endsWith('.avif')) {
      return posterUrl;
    }
    if (tmdbPosterPath != null) {
      return 'https://image.tmdb.org/t/p/w342$tmdbPosterPath';
    }
    return null;
  }

  /// Effective backdrop URL: skip .avif, prefer TMDB fallback
  String? get effectiveBackdropUrl {
    if (backdropUrl != null && backdropUrl!.isNotEmpty && !backdropUrl!.toLowerCase().endsWith('.avif')) {
      return backdropUrl;
    }
    if (tmdbBackdropPath != null) {
      return 'https://image.tmdb.org/t/p/w780$tmdbBackdropPath';
    }
    return null;
  }

  ManifestItem copyWith({
    int? id,
    String? mediaType,
    String? title,
    String? rawTitle,
    String? posterUrl,
    String? backdropUrl,
    String? logoUrl,
    double? voteAverage,
    int? voteCount,
    int? releaseYear,
    String? originalLanguage,
    List<String>? originCountry,
    List<int>? genreIds,
    List<String>? genres,
    String? overview,
    List<String>? language,
    bool? isTrending,
    bool? isPopular,
    bool? is3rdPartyHosted,
    int? trendingRank,
    String? tmdbPosterPath,
    String? tmdbBackdropPath,
    String? releaseDate,
    String? imdbId,
    String? postUrl,
  }) {
    return ManifestItem(
      id: id ?? this.id,
      mediaType: mediaType ?? this.mediaType,
      title: title ?? this.title,
      rawTitle: rawTitle ?? this.rawTitle,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      logoUrl: logoUrl ?? this.logoUrl,
      hoverImageUrl: hoverImageUrl,
      voteAverage: voteAverage ?? this.voteAverage,
      voteCount: voteCount ?? this.voteCount,
      releaseYear: releaseYear ?? this.releaseYear,
      originalLanguage: originalLanguage ?? this.originalLanguage,
      originCountry: originCountry ?? this.originCountry,
      genreIds: genreIds ?? this.genreIds,
      genres: genres ?? this.genres,
      overview: overview ?? this.overview,
      tagline: tagline,
      runtime: runtime,
      numberOfSeasons: numberOfSeasons,
      numberOfEpisodes: numberOfEpisodes,
      status: status,
      imdbId: imdbId ?? this.imdbId,
      language: language ?? this.language,
      result: result,
      isTrending: isTrending ?? this.isTrending,
      isPopular: isPopular ?? this.isPopular,
      is3rdPartyHosted: is3rdPartyHosted ?? this.is3rdPartyHosted,
      trendingRank: trendingRank ?? this.trendingRank,
      tmdbPosterPath: tmdbPosterPath ?? this.tmdbPosterPath,
      tmdbBackdropPath: tmdbBackdropPath ?? this.tmdbBackdropPath,
      releaseDate: releaseDate ?? this.releaseDate,
      postUrl: postUrl ?? this.postUrl,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManifestItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          mediaType == other.mediaType &&
          title == other.title &&
          logoUrl == other.logoUrl &&
          postUrl == other.postUrl;

  @override
  int get hashCode => Object.hash(id, mediaType, title, logoUrl, postUrl);
}

class ParsedPostMetadata {
  final String cleanTitle;
  final int? year;
  final String mediaType;

  const ParsedPostMetadata({
    required this.cleanTitle,
    this.year,
    required this.mediaType,
  });
}

/// Full manifest envelope — supports both GitHub (posts/total/last_updated)
/// and internal cache (items/total_count/generated_at) formats.
class Manifest {
  final List<ManifestItem> items;
  final String? generatedAt;
  final String? version;
  final int? totalCount;

  Manifest({
    required this.items,
    this.generatedAt,
    this.version,
    this.totalCount,
  });

  factory Manifest.fromJson(Map<String, dynamic> json) {
    // Support both GitHub format (posts) and cache format (items)
    final rawList = (json['items'] ?? json['posts']) as List<dynamic>?;

    return Manifest(
      items: rawList
              ?.map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      generatedAt: (json['generated_at'] ?? json['last_updated'])?.toString(),
      version: json['version']?.toString(),
      totalCount: ManifestItem._safeInt(json['total_count'] ?? json['total']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'items': items.map((e) => e.toJson()).toList(),
      'generated_at': generatedAt,
      'version': version,
      'total_count': totalCount,
    };
  }
}

