import 'package:flutter_test/flutter_test.dart';
import '../lib/services/google_sheets_catalog_service.dart';

void main() {
  test('Verify All Multi-Season Shows in Catalog (GoT, Vikings, Breaking Bad)', () async {
    final service = GoogleSheetsCatalogService.instance;

    // 1. Game of Thrones (TMDB 1399)
    final got = await service.getSeriesData(1399);
    expect(got, isNotNull);
    expect(got!.availableSeasons, equals([1, 2, 3, 4, 5, 6, 7, 8]));
    print('✅ Game of Thrones: 8 seasons, S1 Ep 1: ${got.getEpisodesForSeason(1).first.title}');

    // 2. Vikings (TMDB 44217)
    final vikings = await service.getSeriesData(44217);
    expect(vikings, isNotNull);
    expect(vikings!.availableSeasons, equals([1, 2, 3, 4, 5, 6]));
    final vS6Batches = vikings.getBatchButtonsForSeason(6);
    expect(vS6Batches.isNotEmpty, isTrue);
    print('✅ Vikings: 6 seasons, S6 Batch Zips: ${vS6Batches.length}, S1 Ep 1: ${vikings.getEpisodesForSeason(1).first.title}');

    // 3. Breaking Bad (TMDB 1396)
    final bb = await service.getSeriesData(1396);
    expect(bb, isNotNull);
    expect(bb!.availableSeasons, equals([1, 2, 3, 4, 5]));
    final bbS5Batches = bb.getBatchButtonsForSeason(5);
    expect(bbS5Batches.isNotEmpty, isTrue);
    print('✅ Breaking Bad: 5 seasons, S5 Batch Zips: ${bbS5Batches.length}, S1 Ep 1: ${bb.getEpisodesForSeason(1).first.title}');
  });
}
