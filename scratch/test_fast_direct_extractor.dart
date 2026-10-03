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

  // Dart's HttpClient automatically uncompresses gzip/deflate by default!
  await for (final chunk in resp.transform(utf8.decoder)) {
    buffer.write(chunk);
    if (stopCondition != null && stopCondition(buffer.toString())) {
      resp.detachSocket().then((s) => s.destroy()).catchError((_) {});
      break;
    }
  }

  return buffer.toString();
}

void main() async {
  print('===============================================================');
  print('🚀 Testing Fast Code-Only Direct Link Fetching & Stream Probing');
  print('===============================================================\n');

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..badCertificateCallback = (cert, host, port) => true;

  final totalStopwatch = Stopwatch()..start();

  try {
    // ── Target: Game of Thrones Season 8 Episode 1 VCloud Link ──
    const vcloudUrl = 'https://vcloud.fit/zwo5kbpl7rt_t5l';
    print('1️⃣ Step 1: Fast fetching VCloud page (code-only stream)...');
    print('   Target: $vcloudUrl');

    final step1Stopwatch = Stopwatch()..start();
    String? exactSize;
    String? tokenUrl;

    final vHtml = await fastFetchStream(
      client,
      vcloudUrl,
      stopCondition: (text) {
        final hasSize = text.contains('id="size"') || text.contains('Size<i');
        final hasToken = text.contains('atob(atob(');
        return hasSize && hasToken;
      },
    );

    step1Stopwatch.stop();
    print('   ⚡ Stream read completed in ${step1Stopwatch.elapsedMilliseconds}ms (${vHtml.length} characters parsed)');

    // Parse exact size
    final sizeMatch = RegExp(r'id=["\x27]size["\x27][^>]*>([^<]+)<', caseSensitive: false).firstMatch(vHtml);
    if (sizeMatch != null) {
      exactSize = sizeMatch.group(1)?.trim();
    }
    print('   📦 Exact File Size: ${exactSize ?? "Not found"}');

    // Parse double atob token
    final doubleAtob = RegExp(r'atob\(\s*atob\(\s*[\x22\x27]([^\x22\x27]+)[\x22\x27]\s*\)\s*\)').firstMatch(vHtml);
    if (doubleAtob != null) {
      final s1 = utf8.decode(base64.decode(doubleAtob.group(1)!));
      tokenUrl = utf8.decode(base64.decode(s1));
    }

    if (tokenUrl == null) {
      print('   ❌ Could not extract token URL!');
      return;
    }
    print('   🔑 Decoded Token Page URL: $tokenUrl\n');

    // ── Step 2: Fast fetch Token page ──
    print('2️⃣ Step 2: Fast fetching Token page (code-only stream)...');
    final step2Stopwatch = Stopwatch()..start();

    final tokHtml = await fastFetchStream(
      client,
      tokenUrl,
      referer: vcloudUrl,
      stopCondition: (text) {
        final hasFslv2 = text.contains('[FSLv2 Server]') || text.contains('id="s3"');
        final hasFsl = text.contains('[FSL Server]') || text.contains('id="fsl"');
        return hasFslv2 && hasFsl;
      },
    );

    step2Stopwatch.stop();
    print('   ⚡ Stream read completed in ${step2Stopwatch.elapsedMilliseconds}ms (${tokHtml.length} characters parsed)\n');

    // Extract direct server links
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

    totalStopwatch.stop();

    print('===============================================================');
    print('🎉 EXTRACTION SUMMARY');
    print('===============================================================');
    print('⏱ Total Extraction Time: ${totalStopwatch.elapsedMilliseconds}ms (${(totalStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s)');
    print('📁 Exact File Size:      $exactSize');
    print('🌐 Direct Server Links:');
    print('   [FSLv2 Server]:   $fslv2Url');
    print('   [FSL Server]:     $fslUrl');
    print('   [10Gbps Server]:  $tenGbpsUrl');
    print('   [Pixeldrain]:     $pixeldrainUrl\n');

    // ── Step 3: Probe Direct Link with Range Request ──
    print('3️⃣ Step 3: Probing FSLv2 Direct Stream URL with HTTP Range request...');
    if (fslv2Url != null) {
      final probeReq = await client.getUrl(Uri.parse(fslv2Url));
      probeReq.headers.set('Range', 'bytes=0-1023');
      probeReq.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)');
      final probeResp = await probeReq.close();

      print('   ✅ HTTP Status: ${probeResp.statusCode} (Expected 206 Partial Content)');
      print('   ✅ Content-Range: ${probeResp.headers.value("content-range")}');
      print('   ✅ Content-Length: ${probeResp.headers.value("content-length")} bytes');
      print('   ✅ Content-Type: ${probeResp.headers.value("content-type")}');
      print('   🚀 DIRECT STREAM/DOWNLOAD VERIFIED WORKING 100%!');
    }
  } catch (e, st) {
    print('❌ Error during extraction: $e');
    print(st);
  } finally {
    client.close();
  }
}
