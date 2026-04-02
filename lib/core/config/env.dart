/// Environment configuration injected via --dart-define at build time.
/// NEVER hardcode values here — they come from build arguments.
///
/// Build example:
///   flutter build apk --release \
///     --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ... \
///     --dart-define=TMDB_API_KEY=abc123 \
///     --dart-define=MANIFEST_BUCKET=manifests \
///     --dart-define=MANIFEST_PATH=db_manifest_v1.json
class Env {
  Env._();

  // GitHub Data Source
  static const githubRawBaseUrl = String.fromEnvironment(
    'GITHUB_RAW_BASE_URL',
    defaultValue: 'https://raw.githubusercontent.com/aadil12347/DanieWatch_Apk_Database/main',
  );

  // TMDB
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

  // Manifest storage
  static const manifestBucket = String.fromEnvironment(
    'MANIFEST_BUCKET',
    defaultValue: 'manifests',
  );
  static const manifestPath = String.fromEnvironment(
    'MANIFEST_PATH',
    defaultValue: 'db_manifest_v1.json',
  );

  // App version for cache invalidation
  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );
}
