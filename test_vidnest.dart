import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart' as encrypt;

// ─── VidNest configuration ───
final String _vidnestBaseUrl = 'https://new.vidnest.fun';
final String _vidnestCustomAlphabet = 'RB0fpH8ZEyVLkv7c2i6MAJ5u3IKFDxlS1NTsnGaqmXYdUrtzjwObCgQP94hoeW+/=';
final String _vidnestStandardAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';

final List<Map<String, String>> _vidnestServers = [
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

// ─── Peachify configuration ───
final String _peachifyKeyHex = 'a8f2a1b5e9c470814f6b2c3a5d8e7f9c1a2b3c4d5e3f7a8b8cad1e2d0a4d5c5b';
final List<Map<String, String>> _peachifyEndpoints = [
  {'name': 'Spider', 'base': 'https://usa.eat-peach.sbs/holly'},
  {'name': 'Multi', 'base': 'https://usa.eat-peach.sbs/multi'},
  {'name': 'Wolf', 'base': 'https://usa.eat-peach.sbs/air'},
  {'name': 'Iron', 'base': 'https://uwu.eat-peach.sbs/moviebox'},
  {'name': 'Dark', 'base': 'https://uwu.eat-peach.sbs/net'},
];

Uint8List _base64urlDecode(String payload) {
  var normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
  int padding = normalized.length % 4;
  if (padding != 0) {
    normalized += '=' * (4 - padding);
  }
  return base64Decode(normalized);
}

Map<String, dynamic> _decryptPeachifyPayload(String data, String keyHex) {
  final parts = data.split('.');
  if (parts.length != 3) {
    throw Exception('Invalid encrypted data format');
  }

  final ivBytes = _base64urlDecode(parts[0]);
  final ciphertextBytes = _base64urlDecode(parts[1]);
  final tagBytes = _base64urlDecode(parts[2]);

  final keyBytes = Uint8List.fromList(List<int>.generate(
    keyHex.length ~/ 2,
    (i) => int.parse(keyHex.substring(i * 2, i * 2 + 2), radix: 16),
  ));

  final key = encrypt.Key(keyBytes);
  final iv = encrypt.IV(ivBytes);

  final encryptedBytes = Uint8List(ciphertextBytes.length + tagBytes.length);
  encryptedBytes.setAll(0, ciphertextBytes);
  encryptedBytes.setAll(ciphertextBytes.length, tagBytes);

  final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
  final encrypted = encrypt.Encrypted(encryptedBytes);

  final decrypted = encrypter.decrypt(encrypted, iv: iv);
  return jsonDecode(decrypted);
}

String _decryptVidNestCustomBase64(String encryptedData) {
  StringBuffer standardBase64 = StringBuffer();

  for (int i = 0; i < encryptedData.length; i++) {
    String char = encryptedData[i];
    int index = _vidnestCustomAlphabet.indexOf(char);

    if (index != -1) {
      standardBase64.write(_vidnestStandardAlphabet[index]);
    } else {
      standardBase64.write(char);
    }
  }

  List<int> decodedBytes = base64.decode(standardBase64.toString());
  return utf8.decode(decodedBytes);
}

class TestStream {
  final String origin; // 'VidNest' or 'Peachify'
  final String serverName; // original server name (e.g. Iron, Delta)
  final String dub; // language
  final String type;
  final String url;
  final Map<String, String> headers;
  String displayName; // Hindi - 1, Hindi - 2, etc.

  TestStream({
    required this.origin,
    required this.serverName,
    required this.dub,
    required this.type,
    required this.url,
    required this.headers,
    this.displayName = '',
  });
}

void main() async {
  final int tmdbId = 1327819;
  final String mediaType = 'movie';

  print('--- Unified Test Fetch for TMDB ID $tmdbId ($mediaType) ---');

  final List<TestStream> allStreams = [];

  // 1. Fetch from VidNest in parallel
  final vidnestUniquePaths = <String, List<String>>{};
  for (var server in _vidnestServers) {
    final name = server['name']!;
    final path = server['path']!;
    vidnestUniquePaths.putIfAbsent(path, () => []).add(name);
  }

  final vidnestFutures = vidnestUniquePaths.entries.map((entry) async {
    final path = entry.key;
    final serverNames = entry.value;

    final urlPath = '/$path/movie/$tmdbId';
    final requestUrl = '$_vidnestBaseUrl$urlPath';

    try {
      final response = await http.get(Uri.parse(requestUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final parsedResponse = json.decode(response.body);
        Map<String, dynamic>? dataJson;

        if (parsedResponse['encrypted'] == true && parsedResponse['data'] != null) {
          final decryptedString = _decryptVidNestCustomBase64(parsedResponse['data']);
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
            final Map<String, String> headers = {};
            if (streamData['headers'] != null) {
              final headersData = streamData['headers'] as Map<String, dynamic>;
              headersData.forEach((key, value) {
                headers[key] = value.toString();
              });
            }

            for (var serverName in serverNames) {
              allStreams.add(TestStream(
                origin: 'VidNest',
                serverName: serverName,
                dub: language,
                type: type,
                url: streamUrl,
                headers: headers,
              ));
            }
          }
        }
      }
    } catch (e) {
      print('VidNest error for path $path: $e');
    }
  });

  // 2. Fetch from Peachify in parallel
  final peachifyFutures = _peachifyEndpoints.map((endpoint) async {
    final name = endpoint['name']!;
    final base = endpoint['base']!;
    final url = '$base/movie/$tmdbId';

    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Origin': 'https://peachify.top',
        'Referer': 'https://peachify.top/',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final respData = jsonDecode(response.body);
        List<dynamic> sources = [];

        if (respData['isEncrypted'] == true) {
          final decrypted = _decryptPeachifyPayload(respData['data'], _peachifyKeyHex);
          sources = decrypted['sources'] ?? [];
        } else {
          sources = respData['sources'] ?? [];
        }

        for (var s in sources) {
          String streamUrl = s['url'] ?? '';
          if (streamUrl.isEmpty) continue;

          Map<String, String> headers = {
            'Origin': 'https://peachify.top',
            'Referer': 'https://peachify.top/',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
          };

          allStreams.add(TestStream(
            origin: 'Peachify',
            serverName: name,
            dub: s['dub'] ?? 'Unknown',
            type: s['type'] ?? 'Unknown',
            url: streamUrl,
            headers: headers,
          ));
        }
      }
    } catch (e) {
      print('Peachify error for endpoint $name: $e');
    }
  });

  await Future.wait([...vidnestFutures, ...peachifyFutures]);

  print('\nCollation completed. Found ${allStreams.length} streams in total.');

  // 3. Sort streams:
  // - Hindi on top.
  // - Within Hindi:
  //   a) Peachify Iron Hindi first
  //   b) Peachify Dark Hindi second
  //   c) VidNest Hindi servers (Delta first, then others)
  //   d) All other Hindi servers
  // - Then English streams (from both)
  // - Then all others (from both)
  allStreams.sort((a, b) {
    final aProv = a.serverName.toLowerCase();
    final bProv = b.serverName.toLowerCase();
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
      final aIsIron = aProv == 'iron' && a.origin == 'Peachify';
      final bIsIron = bProv == 'iron' && b.origin == 'Peachify';
      if (aIsIron && !bIsIron) return -1;
      if (!aIsIron && bIsIron) return 1;

      // b) Dark Hindi (Peachify)
      final aIsDark = aProv == 'dark' && a.origin == 'Peachify';
      final bIsDark = bProv == 'dark' && b.origin == 'Peachify';
      if (aIsDark && !bIsDark) return -1;
      if (!aIsDark && bIsDark) return 1;

      // c) VidNest Hindi servers: Delta first, then other VidNest servers
      final vidnestPriority = ['delta', 'lamda', 'catflix', 'ophim', 'prime', 'gama', 'hexa', 'beta', 'sigma'];
      
      final aVidPriority = a.origin == 'VidNest' ? vidnestPriority.indexOf(aProv) : -1;
      final bVidPriority = b.origin == 'VidNest' ? vidnestPriority.indexOf(bProv) : -1;

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

    // English streams
    final aIsEnglish = aDub.contains('english') || aDub.contains('eng');
    final bIsEnglish = bDub.contains('english') || bDub.contains('eng');
    if (aIsEnglish && !bIsEnglish) return -1;
    if (!aIsEnglish && bIsEnglish) return 1;

    // Otherwise preserve order
    return 0;
  });

  // 4. Rename to Language - N
  final langCounts = <String, int>{};
  for (var stream in allStreams) {
    var lang = stream.dub.trim();
    if (lang.isEmpty) lang = 'Unknown';
    lang = lang[0].toUpperCase() + lang.substring(1).toLowerCase();

    final count = (langCounts[lang] ?? 0) + 1;
    langCounts[lang] = count;

    stream.displayName = '$lang - $count';
  }

  print('\n--- Extracted & Unified Streams Results ---');
  for (int i = 0; i < allStreams.length; i++) {
    final stream = allStreams[i];
    print('${i + 1}. Unified Name: ${stream.displayName}');
    print('   Origin Provider: ${stream.origin} (${stream.serverName})');
    print('   Original Dub: ${stream.dub}');
    print('   Type: ${stream.type}');
    print('   URL: ${stream.url}');
    print('   Headers: ${stream.headers}');
    print('--------------------------------------------------');
  }
}
