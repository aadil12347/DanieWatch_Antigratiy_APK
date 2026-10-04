import 'dart:convert';
import 'dart:io';

void main() async {
  final csvFile = File('scratch/pure_vcloud_database.csv');
  final lines = await csvFile.readAsLines();

  final List<Map<String, dynamic>> allRows = [];
  final header = lines.first.split(',');

  for (int i = 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;

    // Simple CSV parser for quoted fields
    final fields = <String>[];
    bool inQuote = false;
    StringBuffer curr = StringBuffer();
    for (int c = 0; c < line.length; c++) {
      final ch = line[c];
      if (ch == '"') {
        inQuote = !inQuote;
      } else if (ch == ',' && !inQuote) {
        fields.add(curr.toString());
        curr.clear();
      } else {
        curr.write(ch);
      }
    }
    fields.add(curr.toString());

    if (fields.length >= 12) {
      allRows.add({
        'tmdb_id': int.tryParse(fields[0]) ?? 0,
        'title': fields[1],
        'type': fields[2],
        'season': int.tryParse(fields[3]) ?? 0,
        'episode': fields[4],
        'quality': fields[5],
        'size': fields[6],
        'vcloud_url': fields[7],
        'url_480p': fields[8],
        'url_720p': fields[9],
        'url_1080p': fields[10],
        'label': fields[11],
      });
    }
  }

  final buffer = StringBuffer();
  buffer.writeln('// Auto-generated embedded master catalog for DanieWatch multi-season series');
  buffer.writeln("import 'google_sheets_catalog_service.dart';");
  buffer.writeln('');
  buffer.writeln('class EmbeddedCatalog {');
  buffer.writeln('  static const Set<int> _supportedIds = {1399, 44217, 1396};');
  buffer.writeln('  static bool isAvailable(int tmdbId) => _supportedIds.contains(tmdbId);');
  buffer.writeln('');
  buffer.writeln('  static SeriesCatalogData? getCatalog(int tmdbId) {');
  buffer.writeln('    if (!isAvailable(tmdbId)) return null;');
  buffer.writeln('    final rows = _masterRows.where((r) => r[\'tmdb_id\'] == tmdbId).toList();');
  buffer.writeln('    if (rows.isEmpty) return null;');
  buffer.writeln('    final seasonEps = <int, List<CatalogEpisode>>{};');
  buffer.writeln('    final seasonBatch = <int, List<CatalogBatchZip>>{};');
  buffer.writeln('    final allBatch = <CatalogBatchZip>[];');
  buffer.writeln("    String title = rows.first['title']?.toString() ?? 'Series';");
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
  buffer.writeln('      tmdbId: tmdbId,');
  buffer.writeln('      title: title,');
  buffer.writeln('      seasonEpisodes: seasonEps,');
  buffer.writeln('      seasonBatchZips: seasonBatch,');
  buffer.writeln('      allBatchZips: allBatch,');
  buffer.writeln('    );');
  buffer.writeln('  }');
  buffer.writeln('');
  buffer.writeln('  static const List<Map<String, dynamic>> _masterRows = [');

  for (final item in allRows) {
    buffer.writeln('    ${jsonEncode(item)},');
  }

  buffer.writeln('  ];');
  buffer.writeln('}');

  await File('lib/services/embedded_catalog.dart').writeAsString(buffer.toString());
  print('Successfully generated lib/services/embedded_catalog.dart with ${allRows.length} rows!');
}
