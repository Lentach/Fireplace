import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fireplace/providers/settings_provider.dart';

// Autoplay videos is ON by default (Telegram parity); turning it off must
// survive a restart, which a fresh provider over the same prefs simulates.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh install defaults to autoplay ON', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider(initialThemePreference: 'light');
    expect(settings.autoplayVideos, isTrue);
    // Let the async prefs load settle; still on.
    await Future<void>.delayed(Duration.zero);
    expect(settings.autoplayVideos, isTrue);
  });

  test('setAutoplayVideos(false) persists and a fresh provider loads it', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider(initialThemePreference: 'light');
    await settings.setAutoplayVideos(false);
    expect(settings.autoplayVideos, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('autoplay_videos'), isFalse);

    final relaunched = SettingsProvider(initialThemePreference: 'light');
    await Future<void>.delayed(Duration.zero);
    expect(relaunched.autoplayVideos, isFalse);
  });

  test('stored true loads as autoplay ON', () async {
    SharedPreferences.setMockInitialValues({'autoplay_videos': true});
    final settings = SettingsProvider(initialThemePreference: 'light');
    await Future<void>.delayed(Duration.zero);
    expect(settings.autoplayVideos, isTrue);
  });
}
