import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'peachify_extractor.dart'; // To reuse PeachifyStream

class VidNestExtractorService {
  static final VidNestExtractorService _instance = VidNestExtractorService._internal();
  factory VidNestExtractorService() => _instance;
  VidNestExtractorService._internal();

  static String _baseUrl = 'https://new.vidnest.fun';
  static String _customAlphabet = 'RB0fpH8ZEyVLkv7c2i6MAJ5u3IKFDxlS1NTsnGaqmXYdUrtzjwObCgQP94hoeW+/=';
  static String _standardAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';

  static List<Map<String, String>> _servers = [
    {'name': 'Delta', 'path': 'allmovies'},
    {'name': 'Lamda', 'path': 'allmovies'},
    {'name': 'Catflix', 'path': 'movies4f'},
    {'name': 'Ophim', 'path': 'klikxxi'},
    {'name': 'Prime', 'path': 'catflix'},
    {'name': 'Gama', 'path': 'flixhq'},
    {'name': 'Hexa', 'path': 'vidlink'},
    {'name': 'Beta', 'path': 'purstream'},
    {'name': 'Sigma', 'path': 'hollymoviehd'},
  ];

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final savedUrl = prefs.getString('vidnest_base_url');
      if (savedUrl != null && savedUrl.isNotEmpty) {
        _baseUrl = savedUrl;
      }

      final savedCustomAlphabet = prefs.getString('vidnest_custom_alphabet');
      if (savedCustomAlphabet != null && savedCustomAlphabet.isNotEmpty) {
        _customAlphabet = savedCustomAlphabet;
      }

      final savedStandardAlphabet = prefs.getString('vidnest_standard_alphabet');
      if (savedStandardAlphabet != null && savedStandardAlphabet.isNotEmpty) {
        _standardAlphabet = savedStandardAlphabet;
      }

      final savedServersStr = prefs.getString('vidnest_servers');
      if (savedServersStr != null && savedServersStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(savedServersStr);
        _servers = decoded.map((e) => Map<String, String>.from(e)).toList();
      }
    } catch (e) {
      // Fallback to default hardcoded variables
    }
  }

  /// Decodes the custom Base64 string back into standard JSON text
  static String _decryptCustomBase64(String encryptedData, String customAlpha, String standardAlpha) {
    StringBuffer standardBase64 = StringBuffer();

    for (int i = 0; i < encryptedData.length; i++) {
      String char = encryptedData[i];
      int index = customAlpha.indexOf(char);

      if (index != -1) {
        standardBase64.write(standardAlpha[index]);
      } else {
        standardBase64.write(char);
      }
    }

    // Decode standard base64 to bytes, then utf8 decode to string
    List<int> decodedBytes = base64.decode(standardBase64.toString());
    return utf8.decode(decodedBytes);
  }

  /// Extracts all streams for a given TMDB ID from all configured servers.
  /// Sorts them according to user's priorities (Delta first, then Catflix, then others).
  Future<List<PeachifyStream>> extractStreams({
    required int tmdbId,
    required String mediaType, // 'movie' or 'tv'
    int season = 1,
    int episode = 1,
  }) async {
    final List<PeachifyStream> allStreams = [];

    await _loadConfig();

    // Query each unique server path in parallel to be fast and efficient.
    // Note: Some servers share the same path (e.g., Delta and Lamda both use 'allmovies').
    // We only need to fetch each unique server path once, then associate results with the respective server names.
    final uniquePaths = <String, List<String>>{};
    for (var server in _servers) {
      final name = server['name']!;
      final path = server['path']!;
      uniquePaths.putIfAbsent(path, () => []).add(name);
    }

    final futures = uniquePaths.entries.map((entry) async {
      final path = entry.key;
      final serverNames = entry.value;

      final urlPath = mediaType == 'movie' 
          ? '/$path/movie/$tmdbId' 
          : '/$path/tv/$tmdbId/$season/$episode';

      final requestUrl = '$_baseUrl$urlPath';

      try {
        final uri = Uri.parse(requestUrl);
        final response = await http.get(uri).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final parsedResponse = json.decode(response.body);
          Map<String, dynamic>? dataJson;

          if (parsedResponse['encrypted'] == true && parsedResponse['data'] != null) {
            final decryptedString = _decryptCustomBase64(
              parsedResponse['data'], 
              _customAlphabet, 
              _standardAlphabet
            );
            dataJson = json.decode(decryptedString);
          } else {
            dataJson = parsedResponse;
          }

          if (dataJson != null && dataJson['streams'] != null) {
            final streamsList = dataJson['streams'] as List<dynamic>;
            for (var streamData in streamsList) {
              final streamUrl = streamData['url'] as String? ?? '';
              if (streamUrl.isEmpty) continue;

              final language = streamData['language'] as String? ?? 'English';
              final type = streamData['type'] as String? ?? 'm3u8';
              
              // Extract headers
              final Map<String, String> headers = {};
              if (streamData['headers'] != null) {
                final headersData = streamData['headers'] as Map<String, dynamic>;
                headersData.forEach((key, value) {
                  headers[key] = value.toString();
                });
              }

              // Since multiple server names might share this path, add a stream entry for each
              for (var serverName in serverNames) {
                allStreams.add(PeachifyStream(
                  providerName: serverName,
                  dub: language,
                  type: type,
                  url: streamUrl,
                  headers: headers,
                  tracks: dataJson['tracks'] as List<dynamic>? ?? const [],
                ));
              }
            }
          }
        }
      } catch (e) {
        // Suppress extraction errors per-server so one failure doesn't block others
      }
    });

    await Future.wait(futures);

    // Sort streams: Delta Hindi first, then other Delta, then Lamda, then Catflix, then others
    allStreams.sort((a, b) {
      final aProv = a.providerName.toLowerCase();
      final bProv = b.providerName.toLowerCase();
      final aDub = a.dub.toLowerCase();
      final bDub = b.dub.toLowerCase();

      // Absolute top priority: Delta - Hindi
      final aIsDeltaHindi = aProv == 'delta' && aDub.contains('hindi');
      final bIsDeltaHindi = bProv == 'delta' && bDub.contains('hindi');
      if (aIsDeltaHindi && !bIsDeltaHindi) return -1;
      if (!aIsDeltaHindi && bIsDeltaHindi) return 1;

      final serverPriority = [
        'delta',
        'lamda',
        'catflix',
        'ophim',
        'prime',
        'gama',
        'hexa',
        'beta',
        'sigma'
      ];

      int aPriority = serverPriority.indexOf(aProv);
      int bPriority = serverPriority.indexOf(bProv);

      if (aPriority == -1) aPriority = 999;
      if (bPriority == -1) bPriority = 999;

      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority);
      }

      // If same provider, prioritize Hindi
      final aIsHindi = aDub.contains('hindi');
      final bIsHindi = bDub.contains('hindi');
      if (aIsHindi && !bIsHindi) return -1;
      if (!aIsHindi && bIsHindi) return 1;

      return 0;
    });

    return allStreams;
  }

  /// Fetches from both VidNest and Peachify, merges the results,
  /// sorts them according to custom priority, and renames them to
  /// "Language - N" (e.g. Hindi - 1, Hindi - 2, English - 1, etc.).
  static Future<List<PeachifyStream>> fetchMergedAndSortedStreams({
    required int tmdbId,
    required String mediaType,
    int season = 1,
    int episode = 1,
  }) async {
    // 1. Fetch both in parallel
    final vidnestFuture = VidNestExtractorService().extractStreams(
      tmdbId: tmdbId,
      mediaType: mediaType,
      season: season,
      episode: episode,
    ).catchError((_) => <PeachifyStream>[]);

    final peachifyFuture = PeachifyExtractorService().extractStreams(
      tmdbId: tmdbId,
      mediaType: mediaType,
      season: season,
      episode: episode,
    ).catchError((_) => <PeachifyStream>[]);

    final results = await Future.wait([vidnestFuture, peachifyFuture]);
    final List<PeachifyStream> vidnestStreams = results[0];
    final List<PeachifyStream> peachifyStreams = results[1];

    final List<PeachifyStream> allStreams = [];
    allStreams.addAll(vidnestStreams);
    allStreams.addAll(peachifyStreams);

    if (allStreams.isEmpty) {
      return [];
    }

    // 2. Sort them based on the rules:
    // - Hindi streams on top.
    // - Within Hindi streams:
    //   a) Peachify Iron Hindi first
    //   b) Peachify Dark Hindi second
    //   c) VidNest Hindi servers next (Delta first, then others)
    //   d) All other Hindi servers next
    // - Then English streams (from both)
    // - Then all others (from both)
    allStreams.sort((a, b) {
      final aProv = a.providerName.toLowerCase();
      final bProv = b.providerName.toLowerCase();
      final aDub = a.dub.toLowerCase();
      final bDub = b.dub.toLowerCase();

      final aIsHindi = aDub.contains('hindi');
      final bIsHindi = bDub.contains('hindi');

      // 1. Prioritize Hindi at the very top
      if (aIsHindi && !bIsHindi) return -1;
      if (!aIsHindi && bIsHindi) return 1;

      if (aIsHindi && bIsHindi) {
        // Rules within Hindi:
        // a) Iron Hindi (Peachify)
        final aIsIron = aProv == 'iron';
        final bIsIron = bProv == 'iron';
        if (aIsIron && !bIsIron) return -1;
        if (!aIsIron && bIsIron) return 1;

        // b) Dark Hindi (Peachify)
        final aIsDark = aProv == 'dark';
        final bIsDark = bProv == 'dark';
        if (aIsDark && !bIsDark) return -1;
        if (!aIsDark && bIsDark) return 1;

        // c) VidNest Hindi servers: Delta first, then other VidNest servers
        final vidnestPriority = ['delta', 'lamda', 'catflix', 'ophim', 'prime', 'gama', 'hexa', 'beta', 'sigma'];
        
        final aVidPriority = vidnestPriority.indexOf(aProv);
        final bVidPriority = vidnestPriority.indexOf(bProv);

        final aIsVid = aVidPriority != -1;
        final bIsVid = bVidPriority != -1;

        if (aIsVid && !bIsVid) return -1;
        if (!aIsVid && bIsVid) return 1;
        if (aIsVid && bIsVid) {
          return aVidPriority.compareTo(bVidPriority);
        }

        // d) Remaining Hindi servers (e.g. Peachify Multi/Spider/Wolf) - preserve order
        return 0;
      }

      // 2. English streams
      final aIsEnglish = aDub.contains('english') || aDub.contains('eng');
      final bIsEnglish = bDub.contains('english') || bDub.contains('eng');
      if (aIsEnglish && !bIsEnglish) return -1;
      if (!aIsEnglish && bIsEnglish) return 1;

      // 3. Otherwise preserve order
      return 0;
    });

    // 3. Rename them to "Language - N" (e.g. Hindi - 1, Hindi - 2)
    final langCounts = <String, int>{};
    final List<PeachifyStream> renamedStreams = [];

    for (var stream in allStreams) {
      // Clean language name: strip any numbers/server names, capitalize first letter
      var lang = stream.dub.trim();
      if (lang.isEmpty) lang = 'Unknown';
      
      // Capitalize first letter (e.g. "hindi" -> "Hindi", "english" -> "English")
      lang = lang[0].toUpperCase() + lang.substring(1);

      final count = (langCounts[lang] ?? 0) + 1;
      langCounts[lang] = count;

      final newProviderName = '$lang - $count';

      renamedStreams.add(PeachifyStream(
        providerName: newProviderName,
        dub: stream.dub,
        type: stream.type,
        url: stream.url,
        quality: stream.quality,
        headers: stream.headers,
        tracks: stream.tracks,
      ));
    }

    return renamedStreams;
  }
}
