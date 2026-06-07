import 'dart:convert';
import 'package:http/http.dart' as http;

final String _baseUrl = 'https://new.vidnest.fun';
final String _customAlphabet = 'RB0fpH8ZEyVLkv7c2i6MAJ5u3IKFDxlS1NTsnGaqmXYdUrtzjwObCgQP94hoeW+/=';
final String _standardAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';

final List<Map<String, String>> _servers = [
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

String _decryptCustomBase64(String encryptedData) {
  StringBuffer standardBase64 = StringBuffer();

  for (int i = 0; i < encryptedData.length; i++) {
    String char = encryptedData[i];
    int index = _customAlphabet.indexOf(char);

    if (index != -1) {
      standardBase64.write(_standardAlphabet[index]);
    } else {
      standardBase64.write(char);
    }
  }

  // Decode standard base64 to bytes, then utf8 decode to string
  List<int> decodedBytes = base64.decode(standardBase64.toString());
  return utf8.decode(decodedBytes);
}

void main() async {
  final int tmdbId = 1327819;
  final String mediaType = 'movie';

  print('Testing VidNest Extractor for TMDB ID $tmdbId ($mediaType)...');

  // Query each unique server path in parallel
  final uniquePaths = <String, List<String>>{};
  for (var server in _servers) {
    final name = server['name']!;
    final path = server['path']!;
    uniquePaths.putIfAbsent(path, () => []).add(name);
  }

  final List<Map<String, dynamic>> allStreams = [];

  final futures = uniquePaths.entries.map((entry) async {
    final path = entry.key;
    final serverNames = entry.value;

    final urlPath = '/$path/movie/$tmdbId';
    final requestUrl = '$_baseUrl$urlPath';

    print('Fetching from server path "$path" -> $requestUrl');
    try {
      final response = await http.get(Uri.parse(requestUrl)).timeout(const Duration(seconds: 10));
      print('  Server path "$path" response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final parsedResponse = json.decode(response.body);
        Map<String, dynamic>? dataJson;

        if (parsedResponse['encrypted'] == true && parsedResponse['data'] != null) {
          final decryptedString = _decryptCustomBase64(parsedResponse['data']);
          dataJson = json.decode(decryptedString);
        } else {
          dataJson = parsedResponse;
        }

        if (dataJson != null && dataJson['streams'] != null) {
          final streamsList = dataJson['streams'] as List<dynamic>;
          print('  Successfully decrypted "$path". Stream count: ${streamsList.length}');
          for (var streamData in streamsList) {
            final streamUrl = streamData['url'] as String? ?? '';
            if (streamUrl.isEmpty) continue;

            final language = streamData['language'] as String? ?? 'English';
            final type = streamData['type'] as String? ?? 'm3u8';
            final Map<String, String> headers = {};
            if (streamData['headers'] != null) {
              final headersData = streamData['headers'] as Map<String, dynamic>;
              headersData.forEach((key, value) {
                headers[key] = value.toString();
              });
            }

            for (var serverName in serverNames) {
              allStreams.add({
                'server': serverName,
                'language': language,
                'type': type,
                'url': streamUrl,
                'headers': headers,
              });
            }
          }
        } else {
          print('  No streams found for server path "$path"');
        }
      } else {
        print('  Failed status code: ${response.statusCode} for "$path"');
      }
    } catch (e) {
      print('  Error fetching from server path "$path": $e');
    }
  });

  await Future.wait(futures);

  print('\nSorting streams (Delta Hindi first, then other Delta, then Lamda, then Catflix, then others)...');
  allStreams.sort((a, b) {
    final aProv = (a['server'] as String).toLowerCase();
    final bProv = (b['server'] as String).toLowerCase();
    final aDub = (a['language'] as String).toLowerCase();
    final bDub = (b['language'] as String).toLowerCase();

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

  print('\n--- Extracted Streams Results ---');
  if (allStreams.isEmpty) {
    print('No streams were extracted successfully.');
  } else {
    for (int i = 0; i < allStreams.length; i++) {
      final stream = allStreams[i];
      print('${i + 1}. Server: ${stream['server']}');
      print('   Language: ${stream['language']}');
      print('   Type: ${stream['type']}');
      print('   URL: ${stream['url']}');
      print('   Headers: ${stream['headers']}');
      print('-------------------------------------------');
    }
  }
}
