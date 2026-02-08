class AppConfig {
  static const String _envUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: '',
  );

  static String get baseUrl {
    // If BASE_URL is explicitly set, use it
    if (_envUrl.isNotEmpty) return _envUrl;

    // Auto-detect: use the same host as the browser URL, port 3000
    final host = Uri.base.host;
    return 'http://$host:3000';
  }
}
