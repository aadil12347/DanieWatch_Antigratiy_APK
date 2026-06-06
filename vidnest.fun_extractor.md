# VidNest.fun Extractor Documentation

This document explains the technical details of how the `vidnest.fun` video player fetches and protects its streaming links, and how to programmatically bypass these protections to extract direct `.m3u8` stream links for use in a native Flutter/Dart application.

## Overview

VidNest provides streaming embeds for movies, TV shows, and anime. To prevent scraping, it uses a multi-server backend architecture where the frontend requests an encrypted payload from an API. The payload is obfuscated using a custom Base64 alphabet.

### 1. Server Endpoints

VidNest operates under the base API URL: `https://new.vidnest.fun`.
Depending on the server selected (`?server=...`), the API endpoint changes.

Here is the mapping for **Movies**:
*   **Delta / Lamda**: `https://new.vidnest.fun/allmovies/movie/{tmdbId}`
*   **Catflix**: `https://new.vidnest.fun/movies4f/movie/{tmdbId}`
*   **Ophim**: `https://new.vidnest.fun/klikxxi/movie/{tmdbId}`
*   **Prime**: `https://new.vidnest.fun/catflix/movie/{tmdbId}`
*   **Gama**: `https://new.vidnest.fun/flixhq/movie/{tmdbId}`
*   **Hexa**: `https://new.vidnest.fun/vidlink/movie/{tmdbId}`
*   **Beta**: `https://new.vidnest.fun/purstream/movie/{tmdbId}`
*   **Sigma**: `https://new.vidnest.fun/hollymoviehd/movie/{tmdbId}`

For **TV Shows**, the endpoints typically follow a similar pattern but include the season and episode (e.g., `.../tv/{tmdbId}/{season}/{episode}`).

### 2. The API Response

When making an HTTP GET request to one of the above endpoints, the server returns a JSON object. If successful, it looks like this:

```json
{
  "data": "lOybxZyG35gbEsXFlOymI5HnIuybEsXoEGyGIaJO...",
  "encrypted": true
}
```

If the movie/show isn't available on that server, it will return an error or an empty array.

### 3. Decryption Logic (Custom Base64)

The string inside `data` is heavily obfuscated. Rather than using complex AES or RSA encryption, VidNest utilizes a **Base64 substitution cipher**. It replaces standard Base64 characters with a shuffled alphabet.

*   **VidNest Custom Alphabet**: `RB0fpH8ZEyVLkv7c2i6MAJ5u3IKFDxlS1NTsnGaqmXYdUrtzjwObCgQP94hoeW+/=`
*   **Standard Base64 Alphabet**: `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=`

**To decrypt the data:**
1. Iterate through each character of the encrypted string.
2. Find the index of that character in the *Custom Alphabet*.
3. Replace it with the character at the exact same index in the *Standard Base64 Alphabet*.
4. Once the string is fully mapped back to Standard Base64, decode it into a standard UTF-8 string.
5. Parse the resulting string as JSON to get the direct `.m3u8` links and required headers.

---

## Implementation in Flutter / Dart

You can use the following Dart class to fetch and decrypt VidNest links natively inside your app.

### Extractor Class

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class VidNestExtractor {
  static const String _apiBase = 'https://new.vidnest.fun';
  
  static const String _customAlphabet = 'RB0fpH8ZEyVLkv7c2i6MAJ5u3IKFDxlS1NTsnGaqmXYdUrtzjwObCgQP94hoeW+/=';
  static const String _standardAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';

  /// Maps the server name to its specific API path for movies
  static String _getServerPath(String server) {
    switch (server.toLowerCase()) {
      case 'catflix': return 'movies4f';
      case 'ophim': return 'klikxxi';
      case 'prime': return 'catflix';
      case 'beta': return 'purstream';
      case 'hexa': return 'vidlink';
      case 'sigma': return 'hollymoviehd';
      case 'gama': return 'flixhq';
      case 'delta':
      case 'lamda':
      default:
        return 'allmovies';
    }
  }

  /// Decodes the custom Base64 string back into standard JSON text
  static String _decryptCustomBase64(String encryptedData) {
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

  /// Extracts the stream data for a given TMDB ID and Server
  static Future<Map<String, dynamic>?> extractMovie(String tmdbId, String server) async {
    try {
      final serverPath = _getServerPath(server);
      final url = '$_apiBase/$serverPath/movie/$tmdbId';
      
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final parsedResponse = json.decode(response.body);
        
        // Check if data is encrypted
        if (parsedResponse['encrypted'] == true && parsedResponse['data'] != null) {
          final decryptedString = _decryptCustomBase64(parsedResponse['data']);
          return json.decode(decryptedString);
        } else {
          // Sometimes it might not be encrypted depending on the server
          return parsedResponse;
        }
      } else {
        print('VidNest API request failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('VidNest Extractor Error: $e');
      return null;
    }
  }
}
```

### Example Usage

```dart
void main() async {
  String tmdbId = '1327819';
  String server = 'delta';

  print('Extracting streams for movie $tmdbId on $server...');
  
  Map<String, dynamic>? result = await VidNestExtractor.extractMovie(tmdbId, server);
  
  if (result != null && result['streams'] != null) {
    for (var stream in result['streams']) {
      print('Language: ${stream['language']}');
      print('Type: ${stream['type']}');
      print('URL: ${stream['url']}');
      print('Required Headers: ${stream['headers']}');
      print('---------------------------');
    }
  } else {
    print('Failed to extract streams or no streams available.');
  }
}
```

### Important Notes for Video Players
1. **HTTP Referer Header**: When passing the extracted `.m3u8` URL to your video player (like `video_player` or `better_player` in Flutter), you **must** attach the headers returned in the JSON. Specifically, the `Referer` header (e.g., `https://gemma416okl.com`) is mandatory. If you fail to include the `Referer` header in the player's HTTP requests, the stream will be blocked by their CDN and return a 403 Forbidden error.
2. **Server Fallbacks**: If one server (e.g., `delta`) returns no streams, you should programmatically attempt the extraction with the next available server in the list (e.g., `lamda`, `catflix`, `prime`).
