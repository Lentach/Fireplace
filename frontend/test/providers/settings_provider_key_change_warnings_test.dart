import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fireplace/providers/settings_provider.dart';

// Amendment (lxxix): key-change warnings are DEMOTED (off) by default; opting
// back in must survive a restart, which a fresh provider over the same prefs
// simulates.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh install defaults to warnings OFF', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider(initialThemePreference: 'light');
    expect(settings.keyChangeWarnings, isFalse);
    // Let the async prefs load settle; still off.
    await Future<void>.delayed(Duration.zero);
    expect(settings.keyChangeWarnings, isFalse);
  });

  test('setKeyChangeWarnings(true) persists and a fresh provider loads it',
      () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider(initialThemePreference: 'light');
    await settings.setKeyChangeWarnings(true);
    expect(settings.keyChangeWarnings, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('key_change_warnings'), isTrue);

    final relaunched = SettingsProvider(initialThemePreference: 'light');
    await Future<void>.delayed(Duration.zero);
    expect(relaunched.keyChangeWarnings, isTrue);
  });

  test('stored false loads as warnings OFF', () async {
    SharedPreferences.setMockInitialValues({'key_change_warnings': false});
    final settings = SettingsProvider(initialThemePreference: 'light');
    await Future<void>.delayed(Duration.zero);
    expect(settings.keyChangeWarnings, isFalse);
  });
}
