import 'manifest_item.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Paginated Catalog Models
// ═══════════════════════════════════════════════════════════════════════════════

/// Catalog metadata — tiny file (~500 bytes) with version + page counts.
/// Fetched first to decide which pages to refresh.
class CatalogMeta {
  final String version;
  final int totalItems;
  final int pageSize;
  final Map<String, int> pages; // category → page count

  const CatalogMeta({
    required this.version,
    required this.totalItems,
    required this.pageSize,
    required this.pages,
  });

  factory CatalogMeta.fromJson(Map<String, dynamic> json) {
    final pagesRaw = json['pages'] as Map<String, dynamic>? ?? {};
    return CatalogMeta(
      version: json['version']?.toString() ?? '',
      totalItems: (json['total_items'] as num?)?.toInt() ?? 0,
      pageSize: (json['page_size'] as num?)?.toInt() ?? 50,
      pages: pagesRaw.map((k, v) => MapEntry(k, (v as num).toInt())),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'total_items': totalItems,
        'page_size': pageSize,
        'pages': pages,
      };

  int pageCount(String category) => pages[category] ?? 0;
}

/// A single page of catalog items.
class CatalogPage {
  final int page;
  final int totalPages;
  final int totalItems;
  final List<ManifestItem> items;

  const CatalogPage({
    required this.page,
    required this.totalPages,
    required this.totalItems,
    required this.items,
  });

  factory CatalogPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return CatalogPage(
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 1,
      totalItems: (json['total_items'] as num?)?.toInt() ?? 0,
      items: rawItems
          .map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'page': page,
        'total_pages': totalPages,
        'total_items': totalItems,
        'items': items.map((e) => e.toJson()).toList(),
      };

  bool get hasMore => page < totalPages;
}

/// Lightweight search index entry — only fields needed for search + visibility.
class SearchIndexEntry {
  final int id;
  final String title;
  final String mediaType;
  final List<String> language;

  const SearchIndexEntry({
    required this.id,
    required this.title,
    required this.mediaType,
    this.language = const [],
  });

  factory SearchIndexEntry.fromJson(Map<String, dynamic> json) {
    final langRaw = json['l'] ?? json['language'];
    List<String> langs = [];
    if (langRaw is List) {
      langs = langRaw.map((e) => e.toString()).toList();
    } else if (langRaw is String && langRaw.isNotEmpty) {
      langs = [langRaw];
    }
    return SearchIndexEntry(
      id: (json['i'] ?? json['id'] as num?)?.toInt() ?? 0,
      title: (json['t'] ?? json['title'] ?? '').toString(),
      mediaType: (json['m'] ?? json['media_type'] ?? 'movie').toString(),
      language: langs,
    );
  }

  Map<String, dynamic> toJson() => {
        'i': id,
        't': title,
        'm': mediaType,
        'l': language,
      };
}

/// Pre-built home screen sections data — fetched in one request.
class HomeSectionsData {
  final List<ManifestItem> carousel;
  final List<HomeSection> sections;

  const HomeSectionsData({
    required this.carousel,
    required this.sections,
  });

  factory HomeSectionsData.fromJson(Map<String, dynamic> json) {
    final carouselRaw = json['carousel'] as List<dynamic>? ?? [];
    final sectionsRaw = json['sections'] as List<dynamic>? ?? [];
    return HomeSectionsData(
      carousel: carouselRaw
          .map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      sections: sectionsRaw
          .map((e) => HomeSection.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'carousel': carousel.map((e) => e.toJson()).toList(),
        'sections': sections.map((e) => e.toJson()).toList(),
      };
}

/// A single section in the home screen data.
class HomeSection {
  final String title;
  final List<ManifestItem> items;
  final bool isRanked;

  const HomeSection({
    required this.title,
    required this.items,
    this.isRanked = false,
  });

  factory HomeSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return HomeSection(
      title: json['title']?.toString() ?? '',
      items: rawItems
          .map((e) => ManifestItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      isRanked: json['is_ranked'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'items': items.map((e) => e.toJson()).toList(),
        'is_ranked': isRanked,
      };
}
