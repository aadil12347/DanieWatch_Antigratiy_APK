import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

void main() async {
  print('Testing GoT S8 Nextdrive V-Cloud Extraction...');

  // 1. Nextdrive URL for 720p S8
  final url = 'https://nexdrive.fit/genxfm784776336319/';
  final res = await http.get(Uri.parse(url), headers: {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
  });

  final doc = html_parser.parse(res.body);
  final anchors = doc.querySelectorAll('a[href]');

  print('Found ${anchors.length} anchors');
  final episodeMap = <int, Map<String, dynamic>>{};

  for (final a in anchors) {
    final href = a.attributes['href'] ?? '';
    final lh = href.toLowerCase();
    if (!lh.contains('vcloud') && !lh.contains('fastdl') && !lh.contains('hubcloud')) continue;

    // Check sibling/parent text
    var rawTitle = '';
    var aSib = a.previousElementSibling;
    while (aSib != null) {
      final st = aSib.text.trim();
      if (st.toLowerCase().contains('episode')) {
        rawTitle = st;
        break;
      }
      aSib = aSib.previousElementSibling;
    }
    if (rawTitle.isEmpty) {
      var parent = a.parent;
      while (parent != null && rawTitle.isEmpty) {
        var sib = parent.previousElementSibling;
        while (sib != null) {
          final st = sib.text.trim();
          if (st.toLowerCase().contains('episode')) {
            rawTitle = st;
            break;
          }
          sib = sib.previousElementSibling;
        }
        parent = parent.parent;
      }
    }

    final match = RegExp(r'episode[s]?\s*[:\s]*0*(\d+)', caseSensitive: false).firstMatch(rawTitle);
    final epNum = match != null ? int.parse(match.group(1)!) : 1;

    final isNewVcloud = lh.contains('vcloud') || lh.contains('hubcloud');

    if (!episodeMap.containsKey(epNum)) {
      episodeMap[epNum] = {
        'epNum': epNum,
        'title': 'Episode $epNum',
        'primaryUrl': href,
        'isVcloud': isNewVcloud,
        'alts': <String>[],
      };
    } else {
      final ep = episodeMap[epNum]!;
      if (isNewVcloud && !(ep['isVcloud'] as bool)) {
        ep['alts'].add(ep['primaryUrl']);
        ep['primaryUrl'] = href;
        ep['isVcloud'] = true;
      } else {
        ep['alts'].add(href);
      }
    }
  }

  for (final ep in episodeMap.values) {
    print('EP ${ep['epNum']}: Primary = ${ep['primaryUrl']} (isVcloud=${ep['isVcloud']}), Alts = ${ep['alts']}');
  }
}
