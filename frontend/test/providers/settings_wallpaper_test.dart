import 'package:fireplace/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('global chat wallpaper', () {
    test('defaults to defaultBackground with no stored value', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider(initialThemePreference: 'dark');
      await settings.loadChatWallpaper(1);
      expect(settings.chatWallpaper, ChatWallpaper.defaultBackground);
    });

    test('set + load round-trips per user', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider(initialThemePreference: 'dark');
      await settings.setChatWallpaper(1, ChatWallpaper.glyphs);
      expect(settings.chatWallpaper, ChatWallpaper.glyphs);

      final reloaded = SettingsProvider(initialThemePreference: 'dark');
      await reloaded.loadChatWallpaper(1);
      expect(reloaded.chatWallpaper, ChatWallpaper.glyphs);

      // Another user on the same device is unaffected.
      final otherUser = SettingsProvider(initialThemePreference: 'dark');
      await otherUser.loadChatWallpaper(2);
      expect(otherUser.chatWallpaper, ChatWallpaper.defaultBackground);
    });

    test(
      'migrates legacy per-conversation glyph keys to the global setting',
      () async {
        SharedPreferences.setMockInitialValues({
          'conversation_wallpaper_1:10': 'glyphs',
          'conversation_wallpaper_1:11': 'default',
          'conversation_wallpaper_2:30': 'glyphs',
        });
        final settings = SettingsProvider(initialThemePreference: 'dark');
        await settings.loadChatWallpaper(1);
        expect(settings.chatWallpaper, ChatWallpaper.glyphs);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('chat_wallpaper_1'), 'glyphs');
        // User 1 legacy keys removed; user 2 keys untouched.
        expect(prefs.containsKey('conversation_wallpaper_1:10'), isFalse);
        expect(prefs.containsKey('conversation_wallpaper_1:11'), isFalse);
        expect(prefs.containsKey('conversation_wallpaper_2:30'), isTrue);
      },
    );

    test('legacy keys with no glyphs migrate to default and are removed',
        () async {
      SharedPreferences.setMockInitialValues({
        'conversation_wallpaper_1:10': 'default',
      });
      final settings = SettingsProvider(initialThemePreference: 'dark');
      await settings.loadChatWallpaper(1);
      expect(settings.chatWallpaper, ChatWallpaper.defaultBackground);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('conversation_wallpaper_1:10'), isFalse);
      expect(prefs.containsKey('chat_wallpaper_1'), isFalse);
    });

    test('explicit global default wins over legacy glyph keys', () async {
      SharedPreferences.setMockInitialValues({
        'chat_wallpaper_1': 'default',
        'conversation_wallpaper_1:10': 'glyphs',
      });
      final settings = SettingsProvider(initialThemePreference: 'dark');
      await settings.loadChatWallpaper(1);
      expect(settings.chatWallpaper, ChatWallpaper.defaultBackground);
    });
  });
}
