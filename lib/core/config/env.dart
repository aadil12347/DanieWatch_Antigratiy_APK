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
    defaultValue: '',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  // ── GitHub Data Source ────────────────────────────────────
  static const githubRawBaseUrl = String.fromEnvironment(
    'GITHUB_RAW_BASE_URL',
    defaultValue: '',
  );

  // ── TMDB ──────────────────────────────────────────────────
  static const tmdbApiKey = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue: '',
  );
  static const tmdbBaseUrl = String.fromEnvironment(
    'TMDB_BASE_URL',
    defaultValue: 'https://api.themoviedb.org/3',
  );
  static const tmdbImageBase = String.fromEnvironment(
    'TMDB_IMAGE_BASE',
    defaultValue: 'https://image.tmdb.org/t/p',
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
  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );

  // ── Google Sign-In ────────────────────────────────────────
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static const googleClientSecret = String.fromEnvironment(
    'GOOGLE_CLIENT_SECRET',
    defaultValue: '',
  );

  /// Validates that all required environment variables are configured.
  /// Call once at app startup to fail fast with a clear message.
  static void validate() {
    final missing = <String>[];
    if (supabaseUrl.isEmpty) missing.add('SUPABASE_URL');
    if (supabaseAnonKey.isEmpty) missing.add('SUPABASE_ANON_KEY');
    if (tmdbApiKey.isEmpty) missing.add('TMDB_API_KEY');
    if (githubRawBaseUrl.isEmpty) missing.add('GITHUB_RAW_BASE_URL');
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required --dart-define values: ${missing.join(', ')}.\n'
        'Pass them at build time or use --dart-define-from-file=.dart_define.env',
      );
    }
  }
}
