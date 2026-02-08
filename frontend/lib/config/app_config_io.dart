// Mobile/Desktop fallback implementation
String getBaseUrlForPlatform() {
  // For mobile/desktop, use localhost
  // (This will be overridden by BASE_URL dart-define in production)
  return 'http://localhost:3000';
}
