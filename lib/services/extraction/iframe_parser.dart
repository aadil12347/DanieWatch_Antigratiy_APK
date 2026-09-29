/// Iframe parser utility — extracts embed URLs from HTML iframe tags.
///
/// The manifest JSON files contain `watch` fields with embedded iframes like:
///   `<iframe src="https://bysebuho.com/e/xyz/..." ...></iframe>`
///
/// This utility extracts the src URL and normalizes it for playback extraction.

class IframeParser {
  /// Extract the embed URL from an iframe HTML string.
  ///
  /// Input:  `<iframe src="https://bysebuho.com/e/abc123/title" ...></iframe>`
  /// Output: `https://bysebuho.com/e/abc123/title`
  ///
  /// Returns null if no valid src found.
  static String? extractEmbedUrl(String? iframeHtml) {
    if (iframeHtml == null || iframeHtml.isEmpty) return null;

    // Try regex patterns for src attribute
    final patterns = [
      RegExp(r'''src\s*=\s*"([^"]+)"''', caseSensitive: false),
      RegExp(r"""src\s*=\s*'([^']+)'""", caseSensitive: false),
      RegExp(r'''src\s*=\s*([^\s>]+)''', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(iframeHtml);
      if (match != null) {
        final url = match.group(1)?.trim();
        if (url != null && url.isNotEmpty && url.startsWith('http')) {
          return url;
        }
      }
    }

    // Fallback: if the string itself is a URL (not wrapped in iframe tag)
    final trimmed = iframeHtml.trim();
    if (trimmed.startsWith('http') && !trimmed.contains('<')) {
      return trimmed;
    }

    return null;
  }

  /// Extract the embed URL for a specific movie from manifest JSON data.
  ///
  /// Expects `data['watch']` to contain an iframe HTML string.
  static String? extractMovieEmbedUrl(Map<String, dynamic> data) {
    final watch = data['watch']?.toString();
    return extractEmbedUrl(watch);
  }

  /// Extract the embed URL for a specific episode from manifest JSON data.
  ///
  /// Navigates: data['seasons'][seasonIndex]['episodes'][episodeIndex]['watch']
  ///
  /// [season] and [episode] are 1-indexed.
  static String? extractEpisodeEmbedUrl(
    Map<String, dynamic> data, {
    required int season,
    required int episode,
  }) {
    final seasons = data['seasons'];
    if (seasons == null || seasons is! List || seasons.isEmpty) return null;

    // Find the matching season
    Map<String, dynamic>? seasonData;
    for (final s in seasons) {
      if (s is! Map<String, dynamic>) continue;
      final sNum = s['season_number'];
      if (sNum == season || sNum == season.toString()) {
        seasonData = s;
        break;
      }
    }

    if (seasonData == null) {
      // Fallback: if only one season, use it
      if (seasons.length == 1 && seasons.first is Map<String, dynamic>) {
        seasonData = seasons.first as Map<String, dynamic>;
      } else {
        return null;
      }
    }

    final episodes = seasonData['episodes'];
    if (episodes == null || episodes is! List || episodes.isEmpty) return null;

    // Find the matching episode
    for (final ep in episodes) {
      if (ep is! Map<String, dynamic>) continue;
      final epNum = ep['episode_number'];
      if (epNum == episode || epNum == episode.toString()) {
        return extractEmbedUrl(ep['watch']?.toString());
      }
    }

    // Fallback: match by position (0-indexed)
    final episodeIndex = episode - 1;
    if (episodeIndex >= 0 && episodeIndex < episodes.length) {
      final ep = episodes[episodeIndex];
      if (ep is Map<String, dynamic>) {
        return extractEmbedUrl(ep['watch']?.toString());
      }
    }

    return null;
  }

  /// Checks if a watch field contains an iframe embed URL.
  static bool hasIframeEmbed(String? watchField) {
    if (watchField == null || watchField.isEmpty) return false;
    return watchField.contains('<iframe') || watchField.contains('src=');
  }

  /// Checks if a URL is a known embed host that needs WebView extraction.
  static bool isEmbedHost(String url) {
    final lower = url.toLowerCase();
    return lower.contains('bysebuho.com') ||
        lower.contains('filemoon') ||
        lower.contains('streamtape') ||
        lower.contains('doodstream') ||
        lower.contains('mixdrop') ||
        lower.contains('upstream') ||
        lower.contains('streamlare') ||
        lower.contains('uqload') ||
        lower.contains('vidoza') ||
        lower.contains('mp4upload');
  }
}
