import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;

final String _keyHex = 'a8f2a1b5e9c470814f6b2c3a5d8e7f9c1a2b3c4d5e3f7a8b8cad1e2d0a4d5c5b';

final List<Map<String, String>> _endpoints = [
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

Map<String, dynamic> _decryptPayload(String data, String keyHex) {
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

void main() async {
  final int tmdbId = 1318447;
  final String mediaType = 'movie'; // Let's check movie first
  final path = '/movie/$tmdbId';

  print('Testing TMDB ID $tmdbId ($mediaType) endpoints...');

  for (var endpoint in _endpoints) {
    final name = endpoint['name']!;
    final base = endpoint['base']!;
    final url = '$base$path';
    print('\nFetching from $name: $url');
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri, headers: {
        'Origin': 'https://peachify.top',
        'Referer': 'https://peachify.top/',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
      }).timeout(const Duration(seconds: 10));

      print('  Status Code: ${response.statusCode}');
      if (response.statusCode == 200) {
        final respData = jsonDecode(response.body);
        print('  isEncrypted: ${respData['isEncrypted']}');
        
        List<dynamic> sources = [];
        if (respData['isEncrypted'] == true) {
          try {
            final decrypted = _decryptPayload(respData['data'], _keyHex);
            sources = decrypted['sources'] ?? [];
            print('  Successfully decrypted! Sources count: ${sources.length}');
            for (var src in sources) {
              print('    - Source: ${src}');
            }
          } catch (de) {
            print('  Decryption error: $de');
          }
        } else {
          sources = respData['sources'] ?? [];
          print('  Not encrypted. Sources count: ${sources.length}');
          for (var src in sources) {
            print('    - Source: ${src}');
          }
        }
      } else {
        print('  Response: ${response.body}');
      }
    } catch(e) {
      print('  Error: $e');
    }
  }
}
