import 'dart:convert';
import 'dart:io';

void main() async {
  final jsonStr = await File('scratch/got_complete_catalog.json').readAsString();
  final list = jsonDecode(jsonStr) as List;

  final buffer = StringBuffer();
  buffer.writeln('// Auto-generated embedded catalog for Game of Thrones (TMDB 1399)');
  buffer.writeln("import 'google_sheets_catalog_service.dart';");
  buffer.writeln('');
  buffer.writeln('class EmbeddedGotCatalog {');
  buffer.writeln('  static bool isAvailable(int tmdbId) => tmdbId == 1399;');
  buffer.writeln('');
  buffer.writeln('  static SeriesCatalogData? getCatalog(int tmdbId) {');
  buffer.writeln('    if (tmdbId != 1399) return null;');
  buffer.writeln('    final rows = _rawGotRows;');
  buffer.writeln('    final seasonEps = <int, List<CatalogEpisode>>{};');
  buffer.writeln('    final seasonBatch = <int, List<CatalogBatchZip>>{};');
  buffer.writeln('    final allBatch = <CatalogBatchZip>[];');
  buffer.writeln('');
  buffer.writeln('    for (final row in rows) {');
  buffer.writeln("      final type = row['type']?.toString() ?? '';");
  buffer.writeln("      final sNum = int.tryParse(row['season']?.toString() ?? '') ?? 1;");
  buffer.writeln("      if (type == 'batch_zip') {");
  buffer.writeln('        final bz = CatalogBatchZip.fromJson(row);');
  buffer.writeln('        seasonBatch.putIfAbsent(sNum, () => []).add(bz);');
  buffer.writeln('        allBatch.add(bz);');
  buffer.writeln("      } else if (type == 'episode') {");
  buffer.writeln('        final ep = CatalogEpisode.fromJson(row);');
  buffer.writeln('        seasonEps.putIfAbsent(sNum, () => []).add(ep);');
  buffer.writeln('      }');
  buffer.writeln('    }');
  buffer.writeln('    return SeriesCatalogData(');
  buffer.writeln('      tmdbId: 1399,');
  buffer.writeln("      title: 'Game of Thrones',");
  buffer.writeln('      seasonEpisodes: seasonEps,');
  buffer.writeln('      seasonBatchZips: seasonBatch,');
  buffer.writeln('      allBatchZips: allBatch,');
  buffer.writeln('    );');
  buffer.writeln('  }');
  buffer.writeln('');
  buffer.writeln('  static const List<Map<String, dynamic>> _rawGotRows = [');

  for (final item in list) {
    buffer.writeln('    ${jsonEncode(item)},');
  }

  buffer.writeln('  ];');
  buffer.writeln('}');

  await File('lib/services/embedded_got_catalog.dart').writeAsString(buffer.toString());
  print('Successfully generated lib/services/embedded_got_catalog.dart');
}
