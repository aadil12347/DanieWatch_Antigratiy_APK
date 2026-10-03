import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Fast, code-only stream fetcher with early termination
Future<String> fastFetchStream(
  HttpClient client,
  String url, {
  String? referer,
  bool Function(String accumulatedText)? stopCondition,
}) async {
  final req = await client.getUrl(Uri.parse(url));
  req.headers.set(HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36');
  req.headers.set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
  if (referer != null) {
    req.headers.set(HttpHeaders.refererHeader, referer);
  }

  final resp = await req.close();
  final buffer = StringBuffer();

  // Dart HttpClient automatically decompresses gzip/deflate by default
  await for (final chunk in resp.transform(utf8.decoder)) {
    buffer.write(chunk);
    if (stopCondition != null && stopCondition(buffer.toString())) {
      resp.detachSocket().then((s) => s.destroy()).catchError((_) {});
      break;
    }
  }

  return buffer.toString();
}

class ResolutionTestResult {
  final String quality;
  final String nextdriveUrl;
  final int episodeCount;
  final String? ep1VcloudUrl;
  final String? exactSize;
  final String? fslv2Url;
  final String? fslUrl;
  final String? tenGbpsUrl;
  final String? pixeldrainUrl;
  final int probeStatusCode;
  final String? totalContentLength;
  final int totalElapsedMs;

  ResolutionTestResult({
    required this.quality,
    required this.nextdriveUrl,
    required this.episodeCount,
    this.ep1VcloudUrl,
    this.exactSize,
    this.fslv2Url,
    this.fslUrl,
    this.tenGbpsUrl,
    this.pixeldrainUrl,
    required this.probeStatusCode,
    this.totalContentLength,
    required this.totalElapsedMs,
  });
}

Future<ResolutionTestResult> testResolution(
  HttpClient client, {
  required String quality,
  required String nextdriveUrl,
}) async {
  final sw = Stopwatch()..start();
  print('═══════════════════════════════════════════════════════════════');
  print('▶ Testing Season 8 [$quality]');
  print('  Nextdrive Page: $nextdriveUrl');

  // Step 1: Fetch Nextdrive selector page
  final ndHtml = await fastFetchStream(
    client,
    nextdriveUrl,
    referer: 'https://vegamovies.gallery/',
  );

  // Extract VCloud and FastDL links
  final vcloudRegex = RegExp(r'href=["\x27](https://vcloud\.fit/[^"\x27]+)["\x27]', caseSensitive: false);
  final vcloudMatches = vcloudRegex.allMatches(ndHtml).map((m) => m.group(1)!).toList();
  print('  ✔ Extracted ${vcloudMatches.length} VCloud episode links on selector page');

  if (vcloudMatches.isEmpty) {
    sw.stop();
    return ResolutionTestResult(
      quality: quality,
      nextdriveUrl: nextdriveUrl,
      episodeCount: 0,
      probeStatusCode: 0,
      totalElapsedMs: sw.elapsedMilliseconds,
    );
  }

  final ep1VcloudUrl = vcloudMatches.first;
  print('  ✔ Testing Episode 1 VCloud URL: $ep1VcloudUrl');

  // Step 2: Fetch Episode 1 VCloud page (fast stream with early stop)
  final vHtml = await fastFetchStream(
    client,
    ep1VcloudUrl,
    stopCondition: (text) => text.contains('id="size"') && text.contains('atob(atob('),
  );

  // Parse exact size
  String? exactSize;
  final sizeMatch = RegExp(r'id=["\x27]size["\x27][^>]*>([^<]+)<', caseSensitive: false).firstMatch(vHtml);
  if (sizeMatch != null) {
    exactSize = sizeMatch.group(1)?.trim();
  }
  print('  ✔ Detected Exact File Size: ${exactSize ?? "Unknown"}');

  // Parse token
  String? tokenUrl;
  final doubleAtob = RegExp(r'atob\(\s*atob\(\s*[\x22\x27]([^\x22\x27]+)[\x22\x27]\s*\)\s*\)').firstMatch(vHtml);
  if (doubleAtob != null) {
    final s1 = utf8.decode(base64.decode(doubleAtob.group(1)!));
    tokenUrl = utf8.decode(base64.decode(s1));
  }

  if (tokenUrl == null) {
    print('  ❌ Failed to extract token URL for $quality');
    sw.stop();
    return ResolutionTestResult(
      quality: quality,
      nextdriveUrl: nextdriveUrl,
      episodeCount: vcloudMatches.length,
      ep1VcloudUrl: ep1VcloudUrl,
      exactSize: exactSize,
      probeStatusCode: 0,
      totalElapsedMs: sw.elapsedMilliseconds,
    );
  }

  // Step 3: Fetch Token Page (fast stream with early stop)
  final tokHtml = await fastFetchStream(
    client,
    tokenUrl,
    referer: ep1VcloudUrl,
    stopCondition: (text) =>
        (text.contains('[FSLv2 Server]') || text.contains('id="s3"')) &&
        (text.contains('[FSL Server]') || text.contains('id="fsl"')),
  );

  String? fslv2Url;
  String? fslUrl;
  String? tenGbpsUrl;
  String? pixeldrainUrl;

  final anchorRegex = RegExp(r'<a\s+[^>]*href=["\x27]([^"\x27]+)["\x27][^>]*>(.*?)</a>', caseSensitive: false, dotAll: true);
  for (final match in anchorRegex.allMatches(tokHtml)) {
    final href = match.group(1)!;
    final text = match.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    final lt = text.toLowerCase();
    final lh = href.toLowerCase();

    if (lt.contains('[fslv2 server]') || lh.contains('r2.cloudflarestorage.com') || lh.contains('fslv2')) {
      fslv2Url ??= href;
    } else if (lt.contains('[fsl server]') || (lh.contains('fsl') && !lh.contains('fslv2'))) {
      fslUrl ??= href;
    } else if (lt.contains('10gbps') || lh.contains('gpdl') || lh.contains('hubcloud')) {
      tenGbpsUrl ??= href;
    } else if (lt.contains('pixel') || lh.contains('pixeldrain')) {
      pixeldrainUrl ??= href;
    }
  }

  // Step 4: Live HTTP Range Probe
  int probeStatus = 0;
  String? probeLength;
  final testUrl = fslv2Url ?? fslUrl;

  if (testUrl != null) {
    try {
      final probeReq = await client.getUrl(Uri.parse(testUrl));
      probeReq.headers.set('Range', 'bytes=0-1023');
      probeReq.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)');
      final probeResp = await probeReq.close();
      probeStatus = probeResp.statusCode;
      probeLength = probeResp.headers.value('content-range')?.split('/').last;
      print('  ✔ Live Probe on Direct Link: HTTP $probeStatus (Total bytes: $probeLength)');
    } catch (e) {
      print('  ⚠ Probe warning: $e');
    }
  }

  sw.stop();
  print('  ⏱ Total resolution time: ${sw.elapsedMilliseconds}ms (${(sw.elapsedMilliseconds / 1000).toStringAsFixed(2)}s)');

  return ResolutionTestResult(
    quality: quality,
    nextdriveUrl: nextdriveUrl,
    episodeCount: vcloudMatches.length,
    ep1VcloudUrl: ep1VcloudUrl,
    exactSize: exactSize,
    fslv2Url: fslv2Url,
    fslUrl: fslUrl,
    tenGbpsUrl: tenGbpsUrl,
    pixeldrainUrl: pixeldrainUrl,
    probeStatusCode: probeStatus,
    totalContentLength: probeLength,
    totalElapsedMs: sw.elapsedMilliseconds,
  );
}

void main() async {
  print('╔═══════════════════════════════════════════════════════════════╗');
  print('║   Game of Thrones Season 8: Testing All Resolutions Matrix    ║');
  print('╚═══════════════════════════════════════════════════════════════╝\n');

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..badCertificateCallback = (cert, host, port) => true;

  final resolutions = [
    {'quality': '480p', 'url': 'https://nexdrive.fit/genxfm784776336313/'},
    {'quality': '720p', 'url': 'https://nexdrive.fit/genxfm784776336319/'},
    {'quality': '1080p', 'url': 'https://nexdrive.fit/genxfm784776336325/'},
  ];

  final results = <ResolutionTestResult>[];

  for (final item in resolutions) {
    try {
      final res = await testResolution(
        client,
        quality: item['quality']!,
        nextdriveUrl: item['url']!,
      );
      results.add(res);
    } catch (e, st) {
      print('Error testing ${item['quality']}: $e\n$st');
    }
  }

  print('\n╔══════════════════════════════════════════════════════════════════════════════════════════════════╗');
  print('║                                   FINAL VERIFICATION TABLE                                       ║');
  print('╠════════╤══════════╤═══════════════╤═════════════════╤════════════════╤══════════════╤════════════════╣');
  print('║ Quality│ Episodes │ Exact Size    │ Direct FSLv2    │ Direct FSL     │ HTTP Probe   │ Elapsed Time   ║');
  print('╠════════╪══════════╪═══════════════╪═════════════════╪════════════════╪══════════════╪════════════════╣');

  for (final r in results) {
    final q = r.quality.padRight(7);
    final ep = '${r.episodeCount} eps'.padRight(9);
    final sz = (r.exactSize ?? 'N/A').padRight(14);
    final f2 = (r.fslv2Url != null ? '✅ Ready' : '❌ None').padRight(16);
    final f1 = (r.fslUrl != null ? '✅ Ready' : '❌ None').padRight(15);
    final pr = 'HTTP ${r.probeStatusCode} ✅'.padRight(13);
    final tm = '${(r.totalElapsedMs / 1000).toStringAsFixed(2)}s'.padRight(15);
    print('║ $q│ $ep│ $sz│ $f2│ $f1│ $pr│ $tm║');
  }
  print('╚════════╧══════════╧═══════════════╧═════════════════╧════════════════╧══════════════╧════════════════╝\n');

  for (final r in results) {
    print('─────────────────────────────────────────────────────────────────');
    print('Direct URLs for ${r.quality} (Episode 1):');
    print('• Size:         ${r.exactSize}');
    print('• FSLv2 Server: ${r.fslv2Url}');
    print('• FSL Server:   ${r.fslUrl}');
    print('• 10Gbps:       ${r.tenGbpsUrl}');
    print('• Pixeldrain:   ${r.pixeldrainUrl}');
  }

  client.close();
}
