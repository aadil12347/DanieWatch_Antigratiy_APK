import 'dart:convert';
import 'dart:io';

int scoreCandidate({
  required String cleanQuery,
  required String candidateTitle,
  required String permalink,
  int? year,
}) {
  final lowQuery = cleanQuery.toLowerCase().trim();
  final lowTitle = candidateTitle.toLowerCase();
  final lowSlug = permalink.toLowerCase();

  int score = 0;

  // Direct containment of query
  if (lowTitle.contains(lowQuery) || lowSlug.contains(lowQuery.replaceAll(' ', '-'))) {
    score += 40;
  } else {
    // Check all words
    final words = lowQuery.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    int matchedWords = 0;
    for (final w in words) {
      if (lowTitle.contains(w) || lowSlug.contains(w)) matchedWords++;
    }
    if (matchedWords == words.length && words.isNotEmpty) {
      score += 30;
    } else {
      score += matchedWords * 10;
    }
  }

  // Penalize spin-offs if search query doesn't mention them
  final spinOffKeywords = ['valhalla', 'blood origin', 'better call saul', 'house of the dragon', 'the last watch', 'movie', 'el camino'];
  for (final kw in spinOffKeywords) {
    if (!lowQuery.contains(kw) && (lowTitle.contains(kw) || lowSlug.contains(kw))) {
      score -= 60; // Strong penalty for unintended spin-offs
    }
  }

  // Bonus for complete series / multi-season indicators
  if (lowTitle.contains('complete') || lowTitle.contains('season 1 -') || lowTitle.contains('season 1 –') || lowTitle.contains('series')) {
    score += 25;
  }

  // Bonus for year match
  if (year != null && (lowTitle.contains(year.toString()) || lowSlug.contains(year.toString()))) {
    score += 10;
  }

  return score;
}

void main() async {
  final client = HttpClient()..badCertificateCallback = (cert, host, port) => true;
  final testQueries = ['Vikings', 'Breaking Bad', 'Game of Thrones'];

  for (final q in testQueries) {
    final tsUrl = 'https://vegamovies.gallery/ts-search.php?q=${Uri.encodeComponent(q)}&page=1';
    final req = await client.getUrl(Uri.parse(tsUrl));
    req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)');
    final resp = await req.close();
    final json = jsonDecode(await resp.transform(utf8.decoder).join());
    final hits = json['hits'] as List? ?? [];

    print('\n======================================================');
    print('Testing query: "$q" (${hits.length} hits)');

    Map<String, dynamic>? bestDoc;
    int highestScore = -999;

    for (final hit in hits) {
      final doc = hit['document'] as Map<String, dynamic>;
      final title = doc['post_title']?.toString() ?? '';
      final permalink = doc['permalink']?.toString() ?? '';
      final s = scoreCandidate(cleanQuery: q, candidateTitle: title, permalink: permalink);
      print('  Score: ${s.toString().padLeft(3)} | Title: "$title" | Permalink: $permalink');
      if (s > highestScore) {
        highestScore = s;
        bestDoc = doc;
      }
    }

    print('👉 Selected Best: "${bestDoc?['post_title']}"');
    print('   Permalink: ${bestDoc?['permalink']}');
  }

  client.close();
}
