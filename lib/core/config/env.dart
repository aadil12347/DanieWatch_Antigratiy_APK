import 'package:package_info_plus/package_info_plus.dart';

/// Environment configuration injected via --dart-define at build time.
/// NEVER hardcode secrets here — they come from build arguments.
///
/// Build example:
///   flutter build apk --release \
///     --dart-define-from-file=.dart_define.env
///
/// Or individually:
///   flutter build apk --release \
///     --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ... \
///     --dart-define=TMDB_API_KEY=abc123 \
///     --dart-define=GOOGLE_WEB_CLIENT_ID=xxx.apps.googleusercontent.com
class Env {
  Env._();

  // ── Supabase ──────────────────────────────────────────────
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jeotfdtmfdyywktktikz.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Implb3RmZHRtZmR5eXdrdGt0aWt6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyMDA2MzIsImV4cCI6MjA5MDc3NjYzMn0.Zpr13uqaKmwp46Qg7QZJ85A3VoyGpjPFmNSMpIkJeK0',
  );

  // ── GitHub Data Source ────────────────────────────────────
  static const githubRawBaseUrl = String.fromEnvironment(
    'GITHUB_RAW_BASE_URL',
    defaultValue: 'https://raw.githubusercontent.com/aadil12347/DanieWatch_Apk_Database/main',
  );

  // ── Google Sheets API / Catalog ───────────────────────────
  static const googleSheetsCatalogUrl = String.fromEnvironment(
    'GOOGLE_SHEETS_CATALOG_URL',
    defaultValue: '',
  );

  // ── TMDB ──────────────────────────────────────────────────
  static const tmdbApiKey = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue: 'fc6d85b3839330e3458701b975195487',
  );
  static const tmdbBaseUrl = String.fromEnvironment(
    'TMDB_BASE_URL',
    defaultValue: 'https://api.themoviedb.org/3',
  );
  static const tmdbImageBase = String.fromEnvironment(
    'TMDB_IMAGE_BASE',
    defaultValue: 'https://image.tmdb.org/t/p',
  );

  // ── OMDb ──────────────────────────────────────────────────
  static const omdbApiKey = String.fromEnvironment(
    'OMDB_API_KEY',
    defaultValue: '12275b48',
  );

  // ── Manifest storage ─────────────────────────────────────
  static const manifestBucket = String.fromEnvironment(
    'MANIFEST_BUCKET',
    defaultValue: 'manifests',
  );
  static const manifestPath = String.fromEnvironment(
    'MANIFEST_PATH',
    defaultValue: 'db_manifest_v1.json',
  );

  // ── App version for cache invalidation ────────────────────
  static String appVersion = '1.3.5';

  static Future<void> loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = packageInfo.version;
    } catch (_) {
      appVersion = const String.fromEnvironment('APP_VERSION', defaultValue: '1.3.5');
    }
  }

  // ── Google Sign-In ────────────────────────────────────────
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '896428292637-0vuh07psg3otfkeehjg9v5merlnngjr5.apps.googleusercontent.com',
  );

  static const googleClientSecret = String.fromEnvironment(
    'GOOGLE_CLIENT_SECRET',
    defaultValue: '',
  );

  /// Validates that all required environment variables are configured.
  static void validate() {
    final missing = <String>[];
    if (supabaseUrl.isEmpty) missing.add('SUPABASE_URL');
    if (supabaseAnonKey.isEmpty) missing.add('SUPABASE_ANON_KEY');
    if (tmdbApiKey.isEmpty) missing.add('TMDB_API_KEY');
    if (omdbApiKey.isEmpty) missing.add('OMDB_API_KEY');
    if (githubRawBaseUrl.isEmpty) missing.add('GITHUB_RAW_BASE_URL');
    if (missing.isNotEmpty) {
      // ignore: avoid_print
      print(
        '⚠️  WARNING: Missing required --dart-define values: ${missing.join(', ')}.\n'
        '   Pass them at build time or use --dart-define-from-file=.dart_define.env',
      );
    }

    // Warn if APP_VERSION is still the compile-time default — means
    // .dart_define.env was missing or forgot to set APP_VERSION.
    assert(() {
      if (appVersion == '1.0.0') {
        // ignore: avoid_print
        print(
          '⚠️  WARNING: APP_VERSION is still the default "1.0.0".\n'
          '   Make sure .dart_define.env contains APP_VERSION=<your version> '
          'before building a release.',
        );
      }
      return true;
    }());
  }
}
