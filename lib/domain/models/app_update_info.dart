/// Data model representing an available app update.
///
/// Parsed from the `app_update.json` file hosted on the
/// DanieWatch_Apk_Database GitHub repository.
class AppUpdateInfo {
  /// The latest version string (e.g. "2.0.0").
  /// Compared against [Env.appVersion] to detect updates.
  final String version;

  /// Direct download URL to the new APK file.
  final String downloadUrl;

  /// Title shown on the update modal (e.g. "Update Available!").
  final String title;

  /// Description shown on the update modal (what's new text).
  final String description;

  /// Optional APK file size in MB (shown to user before download).
  final double? fileSizeMb;

  const AppUpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.title,
    required this.description,
    this.fileSizeMb,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      version: json['version'] as String? ?? '',
      downloadUrl: json['download_url'] as String? ?? '',
      title: json['title'] as String? ?? 'Update Available!',
      description: json['description'] as String? ??
          'A new version is available. Please update to continue using the app.',
      fileSizeMb: (json['file_size_mb'] as num?)?.toDouble(),
    );
  }
}
