/// Core data models for the multi-source extraction system.
///
/// Ported from Cloudstream's ExtractorLink architecture and
/// CSX's quality/metadata system.

/// The type of streaming link resolved by an extractor.
enum LinkType {
  /// Direct video file (mp4, mkv, etc.)
  video,

  /// HLS manifest (.m3u8)
  m3u8,

  /// DASH manifest (.mpd)
  dash,

  /// Let the player infer from URL/content-type
  infer,
}

/// A resolved streaming link ready for playback.
///
/// Equivalent to Cloudstream's `ExtractorLink` class.
class ExtractorLink {
  /// Source provider name (e.g. "VCloud", "GDFlix", "VidNest")
  final String sourceName;

  /// Display name shown in source selector (e.g. "[VCloud] 720p WEB-DL")
  final String displayName;

  /// Direct playable URL
  final String url;

  /// Type of stream
  final LinkType type;

  /// Video quality in pixels (480, 720, 1080, 2160)
  final int quality;

  /// HTTP headers required for playback (auth, referer, cookies, etc.)
  final Map<String, String> headers;

  /// Referer URL required by the server
  final String? referer;

  /// Rich quality tags string (e.g. "WEB-DL ☁️ | HEVC ⚡ | Hindi 🇮🇳")
  final String? qualityTags;

  /// File size string (e.g. "1.2 GB")
  final String? fileSize;

  /// Whether this is a direct download (non-streaming) link
  final bool isDownload;

  const ExtractorLink({
    required this.sourceName,
    required this.displayName,
    required this.url,
    this.type = LinkType.infer,
    this.quality = 0,
    this.headers = const {},
    this.referer,
    this.qualityTags,
    this.fileSize,
    this.isDownload = false,
  });

  /// Infer LinkType from URL if type is [LinkType.infer]
  LinkType get resolvedType {
    if (type != LinkType.infer) return type;
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8') || lower.contains('mpegurl')) {
      return LinkType.m3u8;
    }
    if (lower.contains('.mpd')) return LinkType.dash;
    return LinkType.video;
  }

  /// Human-readable quality string (e.g. "720p", "1080p", "4K")
  String get qualityLabel {
    if (quality <= 0) return 'Auto';
    if (quality >= 2160) return '4K';
    if (quality >= 1440) return '2K';
    return '${quality}p';
  }

  ExtractorLink copyWith({
    String? sourceName,
    String? displayName,
    String? url,
    LinkType? type,
    int? quality,
    Map<String, String>? headers,
    String? referer,
    String? qualityTags,
    String? fileSize,
    bool? isDownload,
  }) {
    return ExtractorLink(
      sourceName: sourceName ?? this.sourceName,
      displayName: displayName ?? this.displayName,
      url: url ?? this.url,
      type: type ?? this.type,
      quality: quality ?? this.quality,
      headers: headers ?? this.headers,
      referer: referer ?? this.referer,
      qualityTags: qualityTags ?? this.qualityTags,
      fileSize: fileSize ?? this.fileSize,
      isDownload: isDownload ?? this.isDownload,
    );
  }

  @override
  String toString() =>
      'ExtractorLink($sourceName, $qualityLabel, ${url.length > 60 ? '${url.substring(0, 60)}...' : url})';
}

/// A subtitle track resolved by an extractor.
class SubtitleTrack {
  /// Language label (e.g. "English", "Hindi")
  final String language;

  /// Direct URL to subtitle file
  final String url;

  /// MIME type (e.g. "application/x-subrip", "text/vtt")
  final String? mimeType;

  const SubtitleTrack({
    required this.language,
    required this.url,
    this.mimeType,
  });

  @override
  String toString() => 'SubtitleTrack($language, $url)';
}

/// Result container from a provider extraction.
class ExtractionResult {
  final List<ExtractorLink> links;
  final List<SubtitleTrack> subtitles;
  final String? error;

  const ExtractionResult({
    this.links = const [],
    this.subtitles = const [],
    this.error,
  });

  bool get hasLinks => links.isNotEmpty;
  bool get hasError => error != null;
}
