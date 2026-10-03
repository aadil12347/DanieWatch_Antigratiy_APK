import 'dart:convert';
import 'dart:io';

/// Quick test to simulate the download flow for GOT S8E1
void main() async {
  print('=== Testing GOT S8 720p Download Flow ===\n');
  
  // Step 1: Fetch the VegaMovies page
  final postUrl = 'https://vegamovies.gallery/download-game-of-thrones-season-1-8-hindi-dubbed-org-480p-720p-1080p-bluray/';
  print('Step 1: Fetching post page...');
  
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (cert, host, port) => true;
  
  try {
    final req = await client.getUrl(Uri.parse(postUrl));
    req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36');
    final resp = await req.close();
    final html = await resp.transform(utf8.decoder).join();
    print('  Page size: ${html.length}');
    
    // Step 2: Find nexdrive links for S8 720p
    final nexdriveRegex = RegExp(r'href="(https://nexdrive\.fit/[^"]+)"[^>]*>(.*?)</a>', caseSensitive: false, dotAll: true);
    final headingRegex = RegExp(r'<(h[1-6]|strong)[^>]*>(.*?)</\1>', caseSensitive: false, dotAll: true);
    
    final headings = headingRegex.allMatches(html).toList();
    final nexdriveLinks = nexdriveRegex.allMatches(html).toList();
    
    print('\nStep 2: Found ${nexdriveLinks.length} nexdrive links');
    
    // Find S8 720p G-Direct link
    String? s8720pUrl;
    for (final link in nexdriveLinks) {
      final href = link.group(1)!;
      final pos = link.start;
      
      // Find nearest heading above
      String quality = 'unknown';
      int season = 0;
      for (final h in headings) {
        if (h.start > pos) break;
        final text = h.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').toLowerCase();
        if (text.contains('720p')) quality = '720p';
        else if (text.contains('480p')) quality = '480p';
        else if (text.contains('1080p')) quality = '1080p';
        
        final sMatch = RegExp(r'season\s*(\d+)', caseSensitive: false).firstMatch(text);
        if (sMatch != null) season = int.parse(sMatch.group(1)!);
      }
      
      if (season == 8 && quality == '720p') {
        final cleanText = link.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        if (!cleanText.toLowerCase().contains('batch') && !cleanText.toLowerCase().contains('zip')) {
          s8720pUrl = href;
          print('  S8 720p link: $href (text: ${cleanText.substring(0, cleanText.length.clamp(0, 40))})');
          break;
        }
      }
    }
    
    if (s8720pUrl == null) {
      print('ERROR: No S8 720p link found!');
      exit(1);
    }
    
    // Step 3: Fetch the nexdrive landing page
    print('\nStep 3: Fetching nexdrive landing page...');
    final landReq = await client.getUrl(Uri.parse(s8720pUrl));
    landReq.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)');
    final landResp = await landReq.close();
    final landHtml = await landResp.transform(utf8.decoder).join();
    print('  Landing page size: ${landHtml.length}');
    
    // Find vcloud links for episodes
    final vcloudRegex = RegExp(r'href="(https://vcloud\.fit/[^"]+)"', caseSensitive: false);
    final fastdlRegex = RegExp(r'href="(https://fastdl\.zip/[^"]+)"', caseSensitive: false);
    
    final vcloudLinks = vcloudRegex.allMatches(landHtml).map((m) => m.group(1)!).toList();
    final fastdlLinks = fastdlRegex.allMatches(landHtml).map((m) => m.group(1)!).toList();
    
    print('  VCloud links: ${vcloudLinks.length}');
    print('  FastDL links: ${fastdlLinks.length}');
    
    if (vcloudLinks.isEmpty) {
      print('ERROR: No vcloud links found on landing page!');
      exit(1);
    }
    
    final ep1VcloudUrl = vcloudLinks.first;
    print('\nStep 4: Testing VCloud resolution for Episode 1...');
    print('  VCloud URL: $ep1VcloudUrl');
    
    // Step 4: Fetch the vcloud page
    final vcReq = await client.getUrl(Uri.parse(ep1VcloudUrl));
    vcReq.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)');
    final vcResp = await vcReq.close();
    final vcHtml = await vcResp.transform(utf8.decoder).join();
    print('  VCloud page size: ${vcHtml.length}');
    
    // Check for double atob
    final doubleAtobMatch = RegExp(r"atob\(\s*atob\(\s*['" + r'"' + r"']([^'" + r'"' + r"']+)['" + r'"' + r"']\s*\)\s*\)").firstMatch(vcHtml);
    if (doubleAtobMatch != null) {
      final s1 = utf8.decode(base64.decode(doubleAtobMatch.group(1)!));
      final tokenUrl = utf8.decode(base64.decode(s1));
      print('  Double atob decoded tokenUrl: $tokenUrl');
      
      // Step 5: Fetch the token page
      print('\nStep 5: Fetching token page...');
      final tokReq = await client.getUrl(Uri.parse(tokenUrl));
      tokReq.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)');
      tokReq.headers.set('Referer', ep1VcloudUrl);
      final tokResp = await tokReq.close();
      final tokHtml = await tokResp.transform(utf8.decoder).join();
      print('  Token page size: ${tokHtml.length}');
      
      // Check for server links
      final fslv2Match = RegExp(r'id="s3"[^>]*href="([^"]+)"', caseSensitive: false).firstMatch(tokHtml);
      final fslMatch = RegExp(r'id="fsl"[^>]*href="([^"]+)"', caseSensitive: false).firstMatch(tokHtml);
      
      // Also check reverse order: href before id
      final fslv2Match2 = RegExp(r'href="([^"]+)"[^>]*id="s3"', caseSensitive: false).firstMatch(tokHtml);
      final fslMatch2 = RegExp(r'href="([^"]+)"[^>]*id="fsl"', caseSensitive: false).firstMatch(tokHtml);
      
      if (fslv2Match != null || fslv2Match2 != null) {
        print('  FSLv2 (id=s3): ${(fslv2Match?.group(1) ?? fslv2Match2?.group(1))?.substring(0, 80)}...');
      } else {
        print('  No FSLv2 link found');
      }
      
      if (fslMatch != null || fslMatch2 != null) {
        print('  FSL (id=fsl): ${(fslMatch?.group(1) ?? fslMatch2?.group(1))?.substring(0, 80)}...');
      } else {
        print('  No FSL link found');
      }
      
      // Check for FSL/FSLv2 text-based
      if (tokHtml.contains('[FSLv2 Server]')) print('  Contains [FSLv2 Server] text');
      if (tokHtml.contains('[FSL Server]')) print('  Contains [FSL Server] text');
      if (tokHtml.contains('10Gbps')) print('  Contains 10Gbps text');
      if (tokHtml.contains('PixelServer')) print('  Contains PixelServer text');
      
      print('\n=== RESULT: VCloud extraction chain works! ===');
    } else {
      print('  ERROR: No double atob found!');
      
      // Check single atob
      final singleAtobMatch = RegExp(r"atob\(\s*['" + r'"' + r"']([^'" + r'"' + r"']+)['" + r'"' + r"']\s*\)").firstMatch(vcHtml);
      if (singleAtobMatch != null) {
        final s1 = utf8.decode(base64.decode(singleAtobMatch.group(1)!));
        print('  Single atob decoded: $s1');
      }
    }
  } catch (e, st) {
    print('ERROR: $e');
    print(st);
  } finally {
    client.close();
  }
}
