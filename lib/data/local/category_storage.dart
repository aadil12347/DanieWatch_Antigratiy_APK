import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/manifest_item.dart';

/// Handles saving and loading category-specific JSON files.
/// This matches the user's requirement to have "pages named files".
class CategoryStorage {
  CategoryStorage._();
  static final CategoryStorage instance = CategoryStorage._();

  static const String indexFile = 'index.json';
  static const String bollywoodFile = 'bollywood.json';
  static const String koreanFile = 'korean.json';
  static const String animeFile = 'anime.json';

  Future<File> _getFile(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  /// Save a list of items to a specific category file
  Future<void> saveCategory(String fileName, List<ManifestItem> items) async {
    final file = await _getFile(fileName);
    final json = jsonEncode(items.map((e) => e.toJson()).toList());
    await file.writeAsString(json);
  }

  /// Load items from a specific category file
  Future<List<ManifestItem>> loadCategory(String fileName) async {
    try {
      final file = await _getFile(fileName);
      if (!await file.exists()) return [];

      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Clear all category files
  Future<void> clearAll() async {
    final files = [
      bollywoodFile,
      koreanFile,
      animeFile,
    ];
    for (final name in files) {
      final file = await _getFile(name);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
