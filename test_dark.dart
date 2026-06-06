import 'dart:io';
import 'dart:convert';

void main() async {
  final url = 'https://uwu.eat-peach.sbs/net/m3u8/e7bc1235951162b6993f6db7e113767e.m3u8?src=https%3A%2F%2Fnet52.cc%2Fhls%2F81763251.m3u8%3Fin%3De97af6125c36fb70a3d3cc98cf1a2776%3A%3Aaf09758a358344db11572f98129285e2%3A%3A1778776263%3A%3Ags%3A%3Ap%3A%3A66f312f2266188fe130598ec24e972f3&v=p-v5';

  print('Testing Dark stream URL: $url');
  
  try {
    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true; // Bypass SSL

    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('Origin', 'https://peachify.top');
    request.headers.set('Referer', 'https://peachify.top/');
    request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36');

    final response = await request.close();
    print('Response Status Code: ${response.statusCode}');
    print('Response Headers:');
    response.headers.forEach((name, values) {
      print('  $name: $values');
    });

    final body = await response.transform(utf8.decoder).join();
    print('\nResponse Body (first 300 chars):');
    print(body.length > 300 ? body.substring(0, 300) : body);
    
    client.close();
  } catch (e) {
    print('Error: $e');
  }
}
