class AppConfig {
  static const String _envUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: '',
  );

  // Client-side Giphy key: injected via the GIPHY_API_KEY dart-define at build
  // time (deploy-web.ps1 sources it from gitignored config/env). No hardcoded
  // fallback — a committed key leaks into the public repo. Empty => GIF search
  // is disabled rather than shipping a repo-committed key.
  static String get giphyApiKey =>
      const String.fromEnvironment('GIPHY_API_KEY', defaultValue: '');

  static String get baseUrl {
    // If BASE_URL is explicitly set, use it
    if (_envUrl.isNotEmpty) return _envUrl;

    // Auto-detect: use the same host as the browser URL, port 3000
    final host = Uri.base.host;
    return 'http://$host:3000';
  }
}
