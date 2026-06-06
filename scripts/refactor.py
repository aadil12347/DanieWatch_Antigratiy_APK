import re

with open('lib/presentation/screens/video_player/video_player_screen.dart', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Imports
code = code.replace("import '../../../services/videasy_extractor.dart';", "import '../../../services/peachify_extractor.dart';")
code = code.replace("final Map<String, ExtractedVideasyStream>? extractedStreams;", "final Map<String, PeachifyStream>? extractedStreams;")

# 2. Local State variables
code = code.replace("ExtractedVideasyStream? _extractedStream;", """
  Map<String, PeachifyStream>? _localExtractedStreams;
  Map<String, PeachifyStream>? get _activeStreams => _localExtractedStreams ?? widget.extractedStreams;
  PeachifyStream? _extractedStream;
""")

# Replace usage of widget.extractedStreams
code = code.replace("widget.extractedStreams != null", "_activeStreams != null")
code = code.replace("widget.extractedStreams!", "_activeStreams!")

# 3. Replace _tryDirectExtraction
old_try = """  void _tryDirectExtraction() {
    final s = _currentSeason ?? widget.season ?? 1;
    final e = _currentEpisode ?? widget.episode ?? 1;

    final videasyUrl = VideasyExtractorService.buildPlayerUrl(
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      season: s,
      episode: e,
    );

    debugPrint('[Engine] Starting 1px WebView extraction');
    debugPrint('[Engine]   URL: $videasyUrl');

    setState(() {
      _extraction1pxActive = true;
      _extraction1pxUrl = videasyUrl;
      _extraction1pxKey = ValueKey('extraction_1px_wv_${DateTime.now().millisecondsSinceEpoch}');
      _extraction1pxClickCount = 0;
    });

    // Absolute timeout: 60 seconds
    _extraction1pxTimeoutTimer?.cancel();
    _extraction1pxTimeoutTimer = Timer(const Duration(seconds: 60), () {
      debugPrint('[Engine] ⚠️ Extraction timeout (60s)');
      _onExtractionFailed();
    });
  }"""

new_try = """  void _tryDirectExtraction() {
    final s = _currentSeason ?? widget.season ?? 1;
    final e = _currentEpisode ?? widget.episode ?? 1;

    debugPrint('[Engine] Starting Peachify Extraction');

    setState(() {
      _isExtracting = true;
      _isLoading = true;
    });

    PeachifyExtractorService.instance.extractStreams(
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      season: s,
      episode: e,
    ).then((streams) {
      if (!mounted || _isClosing) return;
      if (streams.isEmpty) {
        _onExtractionFailed();
        return;
      }

      final Map<String, PeachifyStream> map = {};
      for (var stream in streams) {
        final key = '${stream.providerName} - ${stream.dub.toUpperCase()}';
        if (!map.containsKey(key) || (stream.quality ?? 0) > (map[key]!.quality ?? 0)) {
          map[key] = stream;
        }
      }

      _onExtractionSuccess(map);
    }).catchError((e) {
      debugPrint('[Engine] Peachify Extraction Error: $e');
      if (mounted && !_isClosing) _onExtractionFailed();
    });
  }"""
code = code.replace(old_try, new_try)

# 4. Replace _onExtractionSuccess
old_success = """  void _onExtractionSuccess(ExtractedVideasyStream stream) {
    if (!mounted || _isClosing) return;

    // Cancel timers
    _extraction1pxAutoClickTimer?.cancel();
    _extraction1pxSettleTimer?.cancel();
    _extraction1pxTimeoutTimer?.cancel();

    debugPrint('[Engine] 🎬 Playing in custom glassmorphism player: ${stream.url}');

    setState(() {
      _extractedStream = stream;
      _extractedLink = stream.url;
      _extraction1pxActive = false; // Remove 1px WebView
      _isExtracting = false;
      _discoveryComplete = true;
      _useWebViewEngine = true;
      _isLoading = false;
      _isInitialized = true;
      _selectedServer = stream.server;
    });
  }"""

new_success = """  void _onExtractionSuccess(Map<String, PeachifyStream> map) {
    if (!mounted || _isClosing) return;

    final firstKey = map.keys.first;
    final firstStream = map[firstKey]!;

    debugPrint('[Engine] 🎬 Playing in custom player: ${firstStream.url}');

    setState(() {
      _localExtractedStreams = map;
      _extractedStream = firstStream;
      _extractedLink = firstStream.url;
      _extraction1pxActive = false;
      _isExtracting = false;
      _discoveryComplete = true;
      _useWebViewEngine = true;
      _isLoading = false;
      _isInitialized = true;
      _selectedServer = firstKey;
    });
    
    // Auto-start playback
    _startPlayback(firstStream.url, extractedStream: firstStream);
  }"""
code = code.replace(old_success, new_success)

# 5. Fix _startPlayback definition
code = code.replace("void _startPlayback(String link, {bool isOffline = false, ExtractedVideasyStream? extractedStream})", "void _startPlayback(String link, {bool isOffline = false, PeachifyStream? extractedStream})")
code = code.replace("ExtractedVideasyStream? extractedStream,", "PeachifyStream? extractedStream,")

# 6. Fix _onExtractionFailed fallback link building:
old_fail = """    final videasyUrl = VideasyExtractorService.buildPlayerUrl(
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      season: s,
      episode: e,
    );"""
new_fail = "    final videasyUrl = 'https://peachify.top'; // Fallback"
code = code.replace(old_fail, new_fail)

# 7. Also remove `extractedStream.sources` access since Peachify uses direct M3U8
old_sources = """      Map<String, String>? explicitResolutions;
      if (extractedStream != null && extractedStream.sources.isNotEmpty) {
        final Map<String, String> resMap = {};
        for (var source in extractedStream.sources) {
           final label = source['label']?.toString();
           final sUrl = source['url']?.toString();
           // Only add valid explicit MP4 resolutions
           if (label != null && sUrl != null && sUrl.isNotEmpty && source['type'] == 'mp4') {
               resMap[label] = sUrl;
           }
        }
        if (resMap.isNotEmpty) {
           explicitResolutions = resMap;
           _explicitResolutions = resMap;
           if (_selectedResolution == null || !resMap.containsKey(_selectedResolution)) {
             _selectedResolution = resMap.keys.first;
           }
           debugPrint('[BetterPlayer] Added explicit resolutions: ${resMap.keys.join(", ")}');
        }
      } else {
        _explicitResolutions = null;
        _selectedResolution = null;
      }"""
new_sources = """      // Peachify returns M3U8 directly, BetterPlayer handles resolutions natively.
      _explicitResolutions = null;
      _selectedResolution = null;"""
code = code.replace(old_sources, new_sources)

# 8. Update 'hasLanguages' local variable which has a strict list count length > 1
# already changed by `_activeStreams != null`. Let's ensure no issues.

with open('lib/presentation/screens/video_player/video_player_screen.dart', 'w', encoding='utf-8') as f:
    f.write(code)
print('Done replacing.')
