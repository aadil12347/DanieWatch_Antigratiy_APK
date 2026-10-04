import 'dart:io';

void main() async {
  final client = HttpClient()
    ..badCertificateCallback = (cert, host, port) => true;

  final testUrls = [
    {
      'server': 'FSLv2 Server (Cloudflare R2 S3 presigned)',
      'url': 'https://556138dca7367763ed46eecaa4284eca.r2.cloudflarestorage.com/hub2/Game.Of.Thrones.S08E01.720p.x264.BluRay.Hindi.English.Esubs.Vegamovies.To.mkv?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=26b6cf8a0399b5880643f585c8c3dbe5%2F20261004%2Fauto%2Fs3%2Faws4_request&X-Amz-Date=20261004T031252Z&X-Amz-Expires=10800&X-Amz-SignedHeaders=host&response-content-disposition=Game.Of.Thrones.S08E01.720p.x264.BluRay.Hindi.English.Esubs.Vegamovies.To.mkv&X-Amz-Signature=944d9a9eaaffb352d4978c94adbb6237cb7642213a511da2d83c0e51e6f2c7a2',
    },
    {
      'server': 'FSL Server (Direct R2 dev token)',
      'url': 'https://pub-f4ba9fb2017042968ec12c06f4b42344.r2.dev/8c63ec65fb36b3f8ac27c9973f9816a7?token=1791083572',
    }
  ];

  for (final item in testUrls) {
    print('Testing ${item['server']}...');
    try {
      final req = await client.getUrl(Uri.parse(item['url']!));
      req.headers.set('Range', 'bytes=0-1024');
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)');
      final resp = await req.close();
      print('  Status: ${resp.statusCode}');
      print('  Content-Type: ${resp.headers.contentType}');
      print('  Content-Range: ${resp.headers.value('content-range')}');
      print('  Accept-Ranges: ${resp.headers.value('accept-ranges')}');
      print('  Content-Length: ${resp.headers.contentLength}');
    } catch (e) {
      print('  Error: $e');
    }
  }
}
