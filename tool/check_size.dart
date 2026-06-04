import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final client = HttpClient();
  client.userAgent = 'Mozilla/5.0 (Linux; Android 13; SM-G981B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36';
  const code = 'xl98fgcnh968';
  const base = 'https://bysebuho.com';

  // 1. Session
  final sReq = await client.getUrl(Uri.parse('$base/d/$code'));
  sReq.headers.set('Accept', 'text/html');
  final sResp = await sReq.close();
  final cookies = sResp.cookies;
  await sResp.drain();

  // 2. Downloads API
  final dlReq = await client.getUrl(Uri.parse('$base/api/videos/$code/downloads'));
  dlReq.headers.set('Accept', 'application/json');
  dlReq.headers.set('Referer', '$base/d/$code');
  dlReq.cookies.addAll(cookies);
  final dlResp = await dlReq.close();
  final dlBody = await dlResp.transform(utf8.decoder).join();

  if (dlResp.statusCode == 200) {
    final data = jsonDecode(dlBody);
    final pretty = const JsonEncoder.withIndent('  ').convert(data);
    print(pretty);
  } else {
    print('Status: ${dlResp.statusCode} - $dlBody');
  }
  client.close();
}
