/// Which build this is, from APP_ENV in .env.dev / .env.prod
/// (passed with --dart-define-from-file). Defaults to prod.
class AppEnv {
  static const String name = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'prod',
  );

  static bool get isDev => name == 'dev';
}
