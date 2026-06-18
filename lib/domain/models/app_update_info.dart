/// Data model representing an available app update.
///
/// Parsed from the `app_update` config in the Supabase `app_config` table.
/// Supports per-ABI download URLs for split APK distribution.
class AppUpdateInfo {
  /// The latest version string (e.g. "2.0.0").
  /// Compared against [Env.appVersion] to detect updates.
  final String version;

  /// Per-ABI download URLs (e.g. {"arm64-v8a": "https://...", "armeabi-v7a": "https://..."}).
  final Map<String, String> downloadUrls;

  /// Title shown on the update modal (e.g. "Update Available!").
  final String title;

  /// Description shown on the update modal (what's new text).
  final String description;

  /// Optional APK file size in MB (shown to user before download).
  final double? fileSizeMb;

  const AppUpdateInfo({
    required this.version,
    required this.downloadUrls,
    required this.title,
    required this.description,
    this.fileSizeMb,
  });

  /// Get the download URL for the given device ABI.
  /// Falls back to arm64-v8a if not found, then to the first available URL.
  String getDownloadUrlForAbi(String deviceAbi) {
    return downloadUrls[deviceAbi]
        ?? downloadUrls['arm64-v8a']
        ?? downloadUrls.values.first;
  }

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    // Support both formats:
    //  - New: "download_urls": {"arm64-v8a": "...", "armeabi-v7a": "..."}
    //  - Old: "download_url": "..." (backward compatibility → treated as arm64)
    Map<String, String> urls;
    if (json['download_urls'] is Map) {
      urls = Map<String, String>.from(json['download_urls']);
    } else {
      // Backward compatibility: single URL → treat as universal/arm64
      final singleUrl = json['download_url'] as String? ?? '';
      urls = singleUrl.isNotEmpty ? {'arm64-v8a': singleUrl} : {};
    }

    return AppUpdateInfo(
      version: json['version'] as String? ?? '',
      downloadUrls: urls,
      title: json['title'] as String? ?? 'Update Available!',
      description: json['description'] as String? ??
          'A new version is available. Please update to continue using the app.',
      fileSizeMb: (json['file_size_mb'] as num?)?.toDouble(),
    );
  }
}
