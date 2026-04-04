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
  
  // Supabase
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jeotfdtmfdyywktktikz.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Implb3RmZHRtZmR5eXdrdGt0aWt6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyMDA2MzIsImV4cCI6MjA5MDc3NjYzMn0.Zpr13uqaKmwp46Qg7QZJ85A3VoyGpjPFmNSMpIkJeK0',
  );

  // GitHub Data Source
  static const githubRawBaseUrl = String.fromEnvironment(
    'GITHUB_RAW_BASE_URL',
    defaultValue: 'https://raw.githubusercontent.com/aadil12347/DanieWatch_Apk_Database/main',
  );

  // TMDB
  static const tmdbApiKey = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue: 'fc6d85b3839330e3458701b975195487', // Provide your TMDB API Key
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
  
  // Google Sign-In
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '896428292637-0vuh07psg3otfkeehjg9v5merlnngjr5.apps.googleusercontent.com', // Provide your Google Web Client ID
  );
  
  static const googleClientSecret = String.fromEnvironment(
    'GOOGLE_CLIENT_SECRET',
    defaultValue: '', // Provide your Google Client Secret
  );
}
