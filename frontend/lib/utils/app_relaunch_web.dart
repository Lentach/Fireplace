import 'package:web/web.dart' as web;

bool canRelaunchApp() => true;

/// Hard reload. Identical to the frozen-page replacement in
/// `page_lifecycle_web.dart`, deliberately: that path is already exercised on
/// every thaw of a backgrounded Android-Chrome PWA, so the boot it lands on is
/// the best-tested path this app has.
void relaunchApp() {
  web.window.location.reload();
}
