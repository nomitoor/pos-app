/// Supabase project used for cloud backups.
///
/// Values come from `.env.dev` / `.env.prod` in the project root (copy
/// `.env.example`), passed in at build time with e.g.:
///   flutter run --flavor dev --dart-define-from-file=.env.dev
/// VS Code's Run/F5 does this automatically (see .vscode/launch.json).
/// Use a separate Supabase project for dev so test backups never mix
/// with the shop's real ones.
/// Without it, cloud backup shows as "not set up" and the rest of the app
/// works normally.
///
/// SUPABASE_KEY is the "Publishable key" (sb_publishable_...; a legacy
/// "anon public" key also works). It is compiled into the app, which is
/// expected: backups are protected by sign-in and the storage policies in
/// supabase/setup.sql. Never use the "secret" / "service_role" key.
class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');

  static const String publishableKey = String.fromEnvironment('SUPABASE_KEY');

  /// Storage bucket holding backups (created by supabase/setup.sql).
  static const String bucket = 'backups';

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}
