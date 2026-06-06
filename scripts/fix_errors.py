import re

with open('lib/presentation/screens/video_player/video_player_screen.dart', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Fix instance
code = code.replace("PeachifyExtractorService.instance.extractStreams(", "PeachifyExtractorService().extractStreams(")

# 2. Fix sources block
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
           debugPrint('[BetterPlayer] Added explicit resolutions: \\${resMap.keys.join(", ")}');
        }
      } else {
        _explicitResolutions = null;
        _selectedResolution = null;
      }"""

new_sources = """      // Peachify directly uses M3U8, BetterPlayer handles resolutions natively.
      _explicitResolutions = null;
      _selectedResolution = null;"""
code = code.replace(old_sources, new_sources)

# 3. Remove `_onExtraction1pxCreated` block
start_idx = code.find('void _onExtraction1pxCreated(InAppWebViewController controller) {')
if start_idx != -1:
    # Find the next method
    end_idx = code.find('void _onExtractionFailed() {', start_idx)
    if end_idx != -1:
        # Also include any dartdoc comments before _onExtractionFailed
        # We'll just slice it out safely
        code = code[:start_idx] + code[end_idx:]

# 4. Remove VideasyExtractorService references in InAppWebView
code = code.replace("initialSettings: VideasyExtractorService.extractionSettings,", "initialSettings: InAppWebViewSettings(javaScriptEnabled: true),")
code = code.replace("initialUserScripts: VideasyExtractorService.initialUserScripts,", "")

# 5. Fix any other remaining VideasyExtractorService calls
code = code.replace("VideasyExtractorService.fetchApiUrl(apiUrl)", "Future.value('')")

with open('lib/presentation/screens/video_player/video_player_screen.dart', 'w', encoding='utf-8') as f:
    f.write(code)
print("Fixes applied.")
