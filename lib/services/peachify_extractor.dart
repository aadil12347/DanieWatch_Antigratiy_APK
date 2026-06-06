import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;

class PeachifyStream {
  final String providerName;
  final String dub;
  final String type;
  final String url;
  final int? quality;
  final Map<String, String> headers;

  PeachifyStream({
    required this.providerName,
    required this.dub,
    required this.type,
    required this.url,
    this.quality,
    this.headers = const {},
  });
}

class PeachifyExtractorService {
  static final PeachifyExtractorService _instance = PeachifyExtractorService._internal();
  factory PeachifyExtractorService() => _instance;
  PeachifyExtractorService._internal();

  static const String _keyHex = 'a8f2a1b5e9c470814f6b2c3a5d8e7f9c1a2b3c4d5e3f7a8b8cad1e2d0a4d5c5b';

  static final List<Map<String, String>> _endpoints = [
    {'name': 'Spider', 'base': 'https://usa.eat-peach.sbs/holly'},
    {'name': 'Multi', 'base': 'https://usa.eat-peach.sbs/multi'},
    {'name': 'Wolf', 'base': 'https://usa.eat-peach.sbs/air'},
    {'name': 'Iron', 'base': 'https://uwu.eat-peach.sbs/moviebox'},
    {'name': 'Dark', 'base': 'https://uwu.eat-peach.sbs/net'},
  ];

  static Uint8List _base64urlDecode(String payload) {
    var normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
    int padding = normalized.length % 4;
    if (padding != 0) {
      normalized += '=' * (4 - padding);
    }
    return base64Decode(normalized);
  }

  static Map<String, dynamic> _decryptPayload(String data, String keyHex) {
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

    // In PointyCastle AES-GCM, the authentication tag is appended to the ciphertext
    final encryptedBytes = Uint8List(ciphertextBytes.length + tagBytes.length);
    encryptedBytes.setAll(0, ciphertextBytes);
    encryptedBytes.setAll(ciphertextBytes.length, tagBytes);

    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
    final encrypted = encrypt.Encrypted(encryptedBytes);

    final decrypted = encrypter.decrypt(encrypted, iv: iv);
    return jsonDecode(decrypted);
  }

  Future<List<PeachifyStream>> extractStreams({
    required int tmdbId,
    required String mediaType, // 'movie' or 'tv'
    int season = 1,
    int episode = 1,
  }) async {
    final List<PeachifyStream> allStreams = [];

    final path = mediaType == 'movie' ? '/movie/$tmdbId' : '/tv/$tmdbId/$season/$episode';

    // To prevent scraping blocks, try to run them in parallel but gracefully fail
    final futures = _endpoints.map((endpoint) async {
      final name = endpoint['name']!;
      final base = endpoint['base']!;
      final url = '$base$path';

      try {
        final uri = Uri.parse(url);
        final response = await http.get(uri, headers: {
          'Origin': 'https://peachify.top',
          'Referer': 'https://peachify.top/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
        }).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final respData = jsonDecode(response.body);
          List<dynamic> sources = [];

          if (respData['isEncrypted'] == true) {
            final decrypted = _decryptPayload(respData['data'], _keyHex);
            sources = decrypted['sources'] ?? [];
          } else {
            sources = respData['sources'] ?? [];
          }

          for (var s in sources) {
            String streamUrl = s['url'] ?? '';
            
            // These headers are needed if the URL points to Peachify's internal m3u8-proxy.
            // If it's a direct url (like lizer123.site), passing them won't hurt.
            Map<String, String> headers = {
              'Origin': 'https://peachify.top',
              'Referer': 'https://peachify.top/',
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
            };
            
            allStreams.add(PeachifyStream(
              providerName: name,
              dub: s['dub'] ?? 'Unknown',
              type: s['type'] ?? 'Unknown',
              url: streamUrl,
              quality: s['quality'],
              headers: headers,
            ));
          }
        }
      } catch (e) {
        // print('Error fetching from $name: $e');
      }
    });

    await Future.wait(futures);
    return allStreams;
  }
}
