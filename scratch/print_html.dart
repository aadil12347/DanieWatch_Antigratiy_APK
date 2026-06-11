import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final tokenUrl = 'https://gamerxyt.com/hubcloud.php?host=vcloud&id=fwpydo7j1ommkyj&token=ZE1Vd3dldkVRejNYRGhzcE1YeEp1aGZMakg=';
  final vcloudUrl = 'https://vcloud.zip/fwpydo7j1ommkyj';

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..badCertificateCallback = (cert, host, port) => true;

  final headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  try {
    final req = await client.getUrl(Uri.parse(tokenUrl));
    headers.forEach((k, v) => req.headers.set(k, v));
    req.headers.set('Referer', vcloudUrl);
    final resp = await req.close();
    print('Status Code: ${resp.statusCode}');
    final html = await resp.transform(utf8.decoder).join();
    print('HTML Content:\n$html');
  } catch (e) {
    print('Error: $e');
  }
  client.close();
}
