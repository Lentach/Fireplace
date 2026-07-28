import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fireplace/providers/settings_provider.dart';

// Owner ruling 2026-07-28: Hot Stone ('light', warm paper + ember) is the
// default theme for fresh installs. Saved choices always win — the flip must
// never stomp an existing preference, and the legacy dark_mode_preference
// migration keeps mapping old dark/system picks to 'dark'.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh install defaults to Hot Stone (light)', () async {
    SharedPreferences.setMockInitialValues({});
    expect(SettingsProvider.kDefaultThemePreference, 'light');
    expect(await SettingsProvider.storedThemePreference(), 'light');

    final settings = SettingsProvider();
    // Constructor field default paints frame 1 before the async load lands.
    // (No themeData assertion: building ThemeData pulls GoogleFonts, which
    // fetches over the network under the test binding.)
    expect(settings.themePreference, 'light');
    expect(settings.themeMode, ThemeMode.light);
    // Let the async prefs load settle; still light.
    await Future<void>.delayed(Duration.zero);
    expect(settings.themePreference, 'light');
  });

  test('saved preference survives the default flip', () async {
    SharedPreferences.setMockInitialValues({'theme_preference': 'dark'});
    expect(await SettingsProvider.storedThemePreference(), 'dark');
  });

  test('legacy dark_mode_preference still migrates to dark', () async {
    SharedPreferences.setMockInitialValues({
      'dark_mode_preference': 'system',
    });
    expect(await SettingsProvider.storedThemePreference(), 'dark');
  });

  test('invalid stored value falls back to the Hot Stone default', () async {
    SharedPreferences.setMockInitialValues({'theme_preference': 'neon'});
    expect(await SettingsProvider.storedThemePreference(), 'light');
  });
}
