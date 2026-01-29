class AppConfig {
  static const String _envUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static String get baseUrl =>
      _envUrl.isEmpty ? Uri.base.origin : _envUrl;
}
