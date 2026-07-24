/// Native no-op: bundle staleness is a web/PWA (service-worker cache) concern.
Future<bool> isServedBundleNewer() async => false;
