// lib/services/m3u8_parser.dart
// ─────────────────────────────────────────────────────────
// Fetches and parses an HLS master playlist (.m3u8)
// Extracts ALL quality variants, audio tracks, and subtitles.
// ─────────────────────────────────────────────────────────

import 'package:dio/dio.dart';

// ── Quality variant (video stream) ───────────────────────
class StreamVariant {
  final String url; // absolute URL to the variant playlist
  final int bandwidth; // bits per second
  final String? resolution; // e.g. "1280x720"
  final String? codecs;
  final String? audioGroupId; // links to AudioTrack.groupId

  StreamVariant({
    required this.url,
    required this.bandwidth,
    this.resolution,
    this.codecs,
    this.audioGroupId,
  });

  // e.g. "720p" or "1080p" or "2.8 Mbps"
  String get qualityLabel {
    if (resolution != null) {
      final parts = resolution!.split('x');
      if (parts.length == 2) return '${parts[1]}p';
    }
    final mbps = (bandwidth / 1000000).toStringAsFixed(1);
    return '$mbps Mbps';
  }

  // rough file-size estimate for a 45-min episode
  String get estimatedSize {
    final bytes = (bandwidth / 8) * 45 * 60;
    if (bytes < 1024 * 1024 * 1024) {
      return '~${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '~${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get badgeLabel {
    if (resolution == null) return '720p HD'; // Primary default if unknown
    final parts = resolution!.split('x');
    final h = int.tryParse(parts.length == 2 ? parts[1] : '0') ?? 0;
    
    // Explicit branding for 720p and 1080p
    if (h >= 2160) return '4K';
    if (h >= 1080) return '1080p HD';
    if (h >= 720) return '720p HD';
    if (h >= 480) return '480p';
    if (h >= 360) return '360p';
    
    // If it's the only one and resolution is weird, still call it 720p HD in badge
    return '720p HD';
  }

  @override
  String toString() =>
      'StreamVariant($qualityLabel, $bandwidth bps, $resolution)';
}

// ── Audio track ───────────────────────────────────────────
class AudioTrack {
  final String groupId; // links to StreamVariant.audioGroupId
  final String language; // e.g. "en", "hi", "ar"
  final String name; // e.g. "English", "Hindi 5.1"
  final String? url; // direct URI (null if embedded in video stream)
  final bool isDefault;
  final bool isForced;

  AudioTrack({
    required this.groupId,
    required this.language,
    required this.name,
    this.url,
    this.isDefault = false,
    this.isForced = false,
  });

  String get displayName {
    final flag = _languageFlag(language);
    return '$flag $name';
  }

  // Language code → emoji flag
  String _languageFlag(String lang) {
    final lower = lang.toLowerCase().split('-').first;
    const map = {
      'en': '🇬🇧',
      'hi': '🇮🇳',
      'ar': '🇸🇦',
      'fr': '🇫🇷',
      'de': '🇩🇪',
      'es': '🇪🇸',
      'pt': '🇵🇹',
      'ru': '🇷🇺',
      'zh': '🇨🇳',
      'ja': '🇯🇵',
      'ko': '🇰🇷',
      'tr': '🇹🇷',
      'it': '🇮🇹',
      'nl': '🇳🇱',
      'pl': '🇵🇱',
      'ur': '🇵🇰',
    };
    return map[lower] ?? '🔊';
  }

  @override
  String toString() => 'AudioTrack($name, $language, hasUri: ${url != null})';
}

// ── Subtitle track ────────────────────────────────────────
class SubtitleTrack {
  final String language;
  final String name;
  final String url;
  final bool isDefault;

  SubtitleTrack({
    required this.language,
    required this.name,
    required this.url,
    this.isDefault = false,
  });

  String get displayName {
    return 'Subtitle ($name)';
  }
}

// ── Parsed playlist result ────────────────────────────────
class PlaylistInfo {
  final List<StreamVariant> variants; // sorted best → worst quality
  final List<AudioTrack> audioTracks; // all available audio tracks
  final List<SubtitleTrack> subtitles; // available subtiles
  final bool isMasterPlaylist; // false = already a media playlist

  PlaylistInfo({
    required this.variants,
    required this.audioTracks,
    required this.subtitles,
    required this.isMasterPlaylist,
  });

  bool get hasMultipleQualities => variants.length > 1;
  bool get hasMultipleAudioTracks => audioTracks.length > 1;
  bool get hasSubtitles => subtitles.isNotEmpty;

  StreamVariant? get bestVariant => variants.isNotEmpty ? variants.first : null;

  /// Find variant closest to 720p for default selection
  StreamVariant? get defaultVariant {
    if (variants.isEmpty) return null;
    if (variants.length == 1) return variants.first;
    
    // Look for 720p or closest
    try {
      return variants.firstWhere((v) {
        final res = v.resolution ?? '';
        return res.contains('720') || res.contains('1280');
      });
    } catch (_) {
      return variants.first;
    }
  }

  AudioTrack? get defaultAudio {
    if (audioTracks.isEmpty) return null;
    
    // 1. Prefer Hindi if explicitly labeled
    try {
      return audioTracks.firstWhere((a) => a.language == 'hi' || a.name.toLowerCase().contains('hindi'));
    } catch (_) {}

    // 2. Fallback to DEFAULT=YES
    try {
      return audioTracks.firstWhere((a) => a.isDefault);
    } catch (_) {
      return audioTracks.first;
    }
  }
}

// ── Parser ────────────────────────────────────────────────
class M3u8Parser {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
    },
  ));

  /// Fetch and parse a master or media playlist
  Future<PlaylistInfo> parse(String m3u8Url) async {
    final content = await _fetch(m3u8Url);
    return _parseContent(content, m3u8Url);
  }

  // ── Fetch raw playlist text ────────────────────────────
  Future<String> _fetch(String url) async {
    try {
      final response = await _dio.get<String>(url,
          options: Options(responseType: ResponseType.plain));
      return response.data ?? '';
    } catch (e) {
      throw Exception('Failed to fetch playlist: $e');
    }
  }

  // ── Parse playlist content ─────────────────────────────
  PlaylistInfo _parseContent(String content, String baseUrl) {
    final lines = content.split('\n').map((l) => l.trim()).toList();

    // Check if this is a master playlist
    final isMaster = lines.any((l) => l.startsWith('#EXT-X-STREAM-INF'));

    if (!isMaster) {
      // Media playlist (single quality) — wrap it as one variant
      return PlaylistInfo(
        variants: [
          StreamVariant(
            url: baseUrl,
            bandwidth: 0,
            resolution: null,
            audioGroupId: null,
          )
        ],
        audioTracks: [],
        subtitles: [],
        isMasterPlaylist: false,
      );
    }

    final audioTracks = <AudioTrack>[];
    final variants = <StreamVariant>[];
    final subtitles = <SubtitleTrack>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // ── Parse audio tracks ───────────────────────────
      if (line.startsWith('#EXT-X-MEDIA:') && line.contains('TYPE=AUDIO')) {
        final track = _parseAudioTag(line, baseUrl);
        if (track != null) audioTracks.add(track);
      }

      // ── Parse subtitle tracks ────────────────────────
      if (line.startsWith('#EXT-X-MEDIA:') && line.contains('TYPE=SUBTITLES')) {
        final sub = _parseSubtitleTag(line, baseUrl);
        if (sub != null) subtitles.add(sub);
      }

      // ── Parse stream variants ────────────────────────
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        final nextLine = i + 1 < lines.length ? lines[i + 1] : '';
        if (nextLine.isNotEmpty && !nextLine.startsWith('#')) {
          final variant = _parseStreamInf(line, nextLine, baseUrl);
          if (variant != null) variants.add(variant);
          i++; // skip the URL line
        }
      }
    }

    // Sort variants: best quality first
    variants.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));

    // Deduplicate audio tracks by name+language
    final seenAudio = <String>{};
    final uniqueAudio = audioTracks.where((t) {
      final key = '${t.language}_${t.name}';
      return seenAudio.add(key);
    }).toList();

    // Deduplicate subtitles
    final seenSubs = <String>{};
    final uniqueSubs = subtitles.where((t) {
      final key = '${t.language}_${t.name}';
      return seenSubs.add(key);
    }).toList();

    return PlaylistInfo(
      variants: variants,
      audioTracks: uniqueAudio,
      subtitles: uniqueSubs,
      isMasterPlaylist: true,
    );
  }

  // ── Parse #EXT-X-MEDIA tag (Audio) ───────────────────────
  AudioTrack? _parseAudioTag(String line, String baseUrl) {
    try {
      final groupId = _attr(line, 'GROUP-ID') ?? 'audio';
      final uriRaw = _attr(line, 'URI');
      var language = _attr(line, 'LANGUAGE') ?? 'und';
      var name = _attr(line, 'NAME') ?? language;
      
      final isDefault = line.contains('DEFAULT=YES');
      final isForced = line.contains('FORCED=YES');

      final uri = uriRaw != null ? _resolveUrl(uriRaw, baseUrl) : null;

      // ── Robust Hindi Detection ──────────────────────────
      // Some providers mislabel Hindi as English or und but put it in the Name/URI
      final lowerName = name.toLowerCase();
      final lowerUri = uriRaw?.toLowerCase() ?? '';
      if (lowerName.contains('hindi') || lowerUri.contains('hindi') || lowerUri.contains('hin')) {
        if (language == 'und' || language == 'en') {
          language = 'hi';
          if (!name.toLowerCase().contains('hindi')) name = 'Hindi';
        }
      }

      return AudioTrack(
        groupId: groupId,
        language: language,
        name: name,
        url: uri,
        isDefault: isDefault,
        isForced: isForced,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Parse #EXT-X-MEDIA tag (Subtitles) ───────────────────
  SubtitleTrack? _parseSubtitleTag(String line, String baseUrl) {
    try {
      final uriRaw = _attr(line, 'URI');
      if (uriRaw == null) return null;

      final language = _attr(line, 'LANGUAGE') ?? 'und';
      final name = _attr(line, 'NAME') ?? language;
      final isDefault = line.contains('DEFAULT=YES');

      final uri = _resolveUrl(uriRaw, baseUrl);

      return SubtitleTrack(
        language: language,
        name: name,
        url: uri,
        isDefault: isDefault,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Parse #EXT-X-STREAM-INF + following URL line ───────
  StreamVariant? _parseStreamInf(String tag, String urlLine, String baseUrl) {
    try {
      final bandwidth = int.tryParse(_rawAttr(tag, 'BANDWIDTH') ?? '0') ?? 0;
      final resolution = _rawAttr(tag, 'RESOLUTION');
      final codecs = _attr(tag, 'CODECS');
      final audioGroup = _attr(tag, 'AUDIO');

      final url = _resolveUrl(urlLine, baseUrl);

      return StreamVariant(
        url: url,
        bandwidth: bandwidth,
        resolution: resolution,
        codecs: codecs,
        audioGroupId: audioGroup,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Attribute helpers ──────────────────────────────────

  /// Get quoted attribute value: NAME="English" → "English"
  String? _attr(String line, String key) {
    final regex = RegExp('$key="([^"]*)"', caseSensitive: false);
    return regex.firstMatch(line)?.group(1);
  }

  /// Get unquoted attribute value: BANDWIDTH=2800000 → "2800000"
  String? _rawAttr(String line, String key) {
    final regex = RegExp('$key=([^,\\s"]+)', caseSensitive: false);
    return regex.firstMatch(line)?.group(1);
  }

  /// Resolve a relative URL against the base playlist URL
  String _resolveUrl(String url, String baseUrl) {
    if (url.startsWith('http')) return url;
    final base = Uri.parse(baseUrl);
    if (url.startsWith('/')) {
      return '${base.scheme}://${base.host}$url';
    }
    // relative path
    final pathParts = base.path.split('/')..removeLast();
    return '${base.scheme}://${base.host}${pathParts.join('/')}/$url';
  }
}
