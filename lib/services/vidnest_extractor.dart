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
}
