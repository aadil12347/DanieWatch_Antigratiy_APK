import '../../domain/models/manifest_item.dart';

/// Result from the fuzzy search engine with relevance score.
class FuzzySearchResult {
  final int itemId;
  final String mediaType;
  final String title;
  final double score;

  const FuzzySearchResult({
    required this.itemId,
    required this.mediaType,
    required this.title,
    required this.score,
  });
}

/// A pre-indexed entry for fast fuzzy matching.
class _IndexEntry {
  final int itemId;
  final String mediaType;
  final String title;
  final String titleLower;
  final List<String> titleTokens;
  final Set<String> titleTrigrams;
  final String? category; // Pre-computed category for fast filtering

  _IndexEntry({
    required this.itemId,
    required this.mediaType,
    required this.title,
    required this.titleLower,
    required this.titleTokens,
    required this.titleTrigrams,
    this.category,
  });
}

/// Pure-Dart fuzzy search engine with trigram similarity scoring.
///
/// Supports:
/// - Exact substring matching (highest priority)
/// - Word-prefix matching
/// - Trigram-based fuzzy matching (typo tolerance)
/// - Individual token matching (partial queries)
/// - Category-aware scoping (Anime, Korean, etc.)
class FuzzySearchEngine {
  List<_IndexEntry> _entries = [];
  bool _isBuilt = false;

  /// Minimum Dice coefficient to consider a fuzzy match.
  static const double _fuzzyThreshold = 0.25;

  /// Build the search index from manifest items.
  /// Call this once when the manifest loads, and again on refresh.
  void buildIndex(List<ManifestItem> items) {
    _entries = items.map((item) {
      final titleLower = item.title.toLowerCase().trim();
      final tokens = _tokenize(titleLower);
      final trigrams = _generateTrigrams(titleLower);
      final category = _detectCategory(item);

      return _IndexEntry(
        itemId: item.id,
        mediaType: item.mediaType,
        title: item.title,
        titleLower: titleLower,
        titleTokens: tokens,
        titleTrigrams: trigrams,
        category: category,
      );
    }).toList();
    _isBuilt = true;
  }

  bool get isBuilt => _isBuilt;

  /// Search with fuzzy matching and optional category scoping.
  ///
  /// [query] — the user's search text
  /// [categoryFilter] — if set, only items matching this category are returned.
  ///   Use `null` for Explore/genre pages (search everything).
  ///   Use `'Anime'`, `'Korean'`, `'Bollywood'`, etc. for category pages.
  /// [limit] — max results to return (default 80)
  List<FuzzySearchResult> search(
    String query, {
    String? categoryFilter,
    int limit = 80,
  }) {
    if (!_isBuilt || query.trim().isEmpty) return [];

    final queryLower = query.toLowerCase().trim();
    final queryTokens = _tokenize(queryLower);
    final queryTrigrams = _generateTrigrams(queryLower);

    // Pre-filter by category if specified
    final candidates = categoryFilter != null
        ? _entries.where((e) => _matchesCategoryFilter(e, categoryFilter))
        : _entries;

    final results = <FuzzySearchResult>[];

    for (final entry in candidates) {
      final score = _scoreMatch(
        queryLower: queryLower,
        queryTokens: queryTokens,
        queryTrigrams: queryTrigrams,
        entry: entry,
      );

      if (score >= _fuzzyThreshold) {
        results.add(FuzzySearchResult(
          itemId: entry.itemId,
          mediaType: entry.mediaType,
          title: entry.title,
          score: score,
        ));
      }
    }

    // Sort by score descending, then alphabetically for ties
    results.sort((a, b) {
      final scoreCmp = b.score.compareTo(a.score);
      if (scoreCmp != 0) return scoreCmp;
      return a.title.compareTo(b.title);
    });

    return results.take(limit).toList();
  }

  /// Multi-tier scoring system.
  double _scoreMatch({
    required String queryLower,
    required List<String> queryTokens,
    required Set<String> queryTrigrams,
    required _IndexEntry entry,
  }) {
    final titleLower = entry.titleLower;

    // === Tier 1: Exact match (case-insensitive) ===
    if (titleLower == queryLower) return 1.0;

    // === Tier 2: Title starts with query ===
    if (titleLower.startsWith(queryLower)) return 0.95;

    // === Tier 3: Exact substring match ===
    if (titleLower.contains(queryLower)) return 0.85;

    // === Tier 4: All query tokens found as word-start prefixes ===
    if (queryTokens.length > 1) {
      final allTokensMatch = queryTokens.every((qt) =>
          entry.titleTokens.any((tt) => tt.startsWith(qt)));
      if (allTokensMatch) return 0.80;
    }

    // === Tier 5: Any query token is a prefix of any title word ===
    final matchingTokenCount = queryTokens.where((qt) =>
        entry.titleTokens.any((tt) => tt.startsWith(qt))).length;

    if (matchingTokenCount > 0) {
      final tokenScore = 0.50 + (0.25 * matchingTokenCount / queryTokens.length);
      // If we have a good token match, return it
      if (tokenScore > 0.55) {
        // Cross-check with trigrams for higher confidence
        final trigramScore = _diceCoefficient(queryTrigrams, entry.titleTrigrams);
        return (tokenScore * 0.6 + trigramScore * 0.4).clamp(0.0, 0.85);
      }
    }

    // === Tier 6: Trigram fuzzy matching (handles typos) ===
    if (queryTrigrams.isNotEmpty && entry.titleTrigrams.isNotEmpty) {
      final dice = _diceCoefficient(queryTrigrams, entry.titleTrigrams);
      if (dice >= _fuzzyThreshold) {
        return dice * 0.75; // Scale down fuzzy scores below exact matches
      }

      // === Tier 7: Per-token trigram matching ===
      // For multi-word queries, check each token individually
      if (queryTokens.length > 1) {
        double bestTokenDice = 0.0;
        int matchedTokens = 0;

        for (final qt in queryTokens) {
          final qtTrigrams = _generateTrigrams(qt);
          if (qtTrigrams.isEmpty) continue;

          double bestForThisToken = 0.0;
          for (final tt in entry.titleTokens) {
            final ttTrigrams = _generateTrigrams(tt);
            final tokenDice = _diceCoefficient(qtTrigrams, ttTrigrams);
            if (tokenDice > bestForThisToken) bestForThisToken = tokenDice;
          }

          if (bestForThisToken >= 0.35) {
            matchedTokens++;
            bestTokenDice += bestForThisToken;
          }
        }

        if (matchedTokens > 0) {
          final avgDice = bestTokenDice / queryTokens.length;
          final coverage = matchedTokens / queryTokens.length;
          final combinedScore = avgDice * 0.5 + coverage * 0.3;
          if (combinedScore >= _fuzzyThreshold) return combinedScore;
        }
      }
    }

    // === Tier 8: Single short token substring in any title word ===
    // Handles cases like searching "love" matching "Lovely" etc.
    if (queryTokens.length == 1 && queryLower.length >= 3) {
      for (final tt in entry.titleTokens) {
        if (tt.contains(queryLower)) return 0.60;
      }
    }

    return 0.0; // No match
  }

  /// Generate character trigrams from a string.
  /// "demon" → {"dem", "emo", "mon"}
  static Set<String> _generateTrigrams(String s) {
    if (s.length < 3) return {s};
    final trigrams = <String>{};
    for (int i = 0; i <= s.length - 3; i++) {
      trigrams.add(s.substring(i, i + 3));
    }
    return trigrams;
  }

  /// Dice coefficient between two trigram sets.
  /// Returns 0.0 to 1.0 (1.0 = identical).
  static double _diceCoefficient(Set<String> a, Set<String> b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final intersection = a.intersection(b).length;
    return (2 * intersection) / (a.length + b.length);
  }

  /// Tokenize a string into words (split on whitespace and special chars).
  static List<String> _tokenize(String s) {
    return s
        .split(RegExp(r'[\s\-_:;,.\(\)\[\]!?/&]+'))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  /// Detect which top-level category an item belongs to.
  static String? _detectCategory(ManifestItem item) {
    // Anime: Japanese + animation genre
    if ((item.genreIds.contains(16) ||
            item.genres.any((g) => g.toLowerCase() == 'animation')) &&
        item.originalLanguage == 'ja') {
      return 'Anime';
    }
    // Korean
    if (item.originCountry.contains('KR') || item.originalLanguage == 'ko') {
      return 'Korean';
    }
    // Bollywood
    if (item.originCountry.contains('IN') || item.originalLanguage == 'hi') {
      return 'Bollywood';
    }
    // Chinese
    if (item.originCountry.contains('CN') ||
        item.originCountry.contains('HK') ||
        item.originCountry.contains('TW') ||
        item.originalLanguage == 'zh' ||
        item.originalLanguage == 'cn') {
      return 'Chinese';
    }
    // Punjabi
    if (item.originalLanguage == 'pa') {
      return 'Punjabi';
    }
    // Pakistani
    if (item.originCountry.contains('PK') || item.originalLanguage == 'ur') {
      return 'Pakistani';
    }
    // Hollywood (US/UK/en) — broad catch
    if (item.originCountry.contains('US') ||
        item.originCountry.contains('GB') ||
        item.originCountry.contains('UK') ||
        item.originalLanguage == 'en') {
      return 'Hollywood';
    }
    return null;
  }

  /// Check if an entry matches a given category filter.
  bool _matchesCategoryFilter(_IndexEntry entry, String category) {
    switch (category) {
      case 'Anime':
        return entry.category == 'Anime';
      case 'K-Drama':
      case 'Korean':
        return entry.category == 'Korean';
      case 'Bollywood':
        return entry.category == 'Bollywood';
      case 'Hollywood':
        return entry.category == 'Hollywood';
      case 'Chinese':
        return entry.category == 'Chinese';
      case 'Punjabi':
        return entry.category == 'Punjabi';
      case 'Pakistani':
        return entry.category == 'Pakistani';
      default:
        return true; // Unknown category = show everything
    }
  }
}
