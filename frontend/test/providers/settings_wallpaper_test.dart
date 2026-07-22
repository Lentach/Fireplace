import 'package:fireplace/models/chat_background_preference.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('global chat background', () {
    test(
      'defaults to themeDefault and persists an explicit per-user value',
      () async {
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsProvider(initialThemePreference: 'dark');

        await settings.loadChatBackground(1);

        expect(settings.chatBackground, ChatBackgroundPreference.themeDefault);
        expect(settings.resolvedChatBackground, ChatBackgroundLayer.plain);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('chat_wallpaper_1'), 'theme_default');
      },
    );

    test(
      'explicit override round-trips per user and survives theme changes',
      () async {
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsProvider(initialThemePreference: 'dark');
        await settings.loadChatBackground(1);
        await settings.setChatBackground(1, ChatBackgroundPreference.glyphs);

        await settings.setThemePreference('cosmic');

        expect(settings.chatBackground, ChatBackgroundPreference.glyphs);
        expect(settings.resolvedChatBackground, ChatBackgroundLayer.glyphs);

        final reloaded = SettingsProvider(initialThemePreference: 'cosmic');
        await reloaded.loadChatBackground(1);
        expect(reloaded.chatBackground, ChatBackgroundPreference.glyphs);

        final otherUser = SettingsProvider(initialThemePreference: 'cosmic');
        await otherUser.loadChatBackground(2);
        expect(otherUser.chatBackground, ChatBackgroundPreference.themeDefault);
      },
    );

    test('themeDefault resolves to starfield only for Cosmic', () async {
      SharedPreferences.setMockInitialValues({
        'chat_wallpaper_1': 'theme_default',
      });
      final settings = SettingsProvider(initialThemePreference: 'cosmic');

      await settings.loadChatBackground(1);

      expect(settings.resolvedChatBackground, ChatBackgroundLayer.starfield);
      await settings.setThemePreference('blue');
      expect(settings.resolvedChatBackground, ChatBackgroundLayer.plain);
    });

    test(
      'saved Cosmic theme wins over async constructor state during migration',
      () async {
        SharedPreferences.setMockInitialValues({
          'theme_preference': 'cosmic',
          'cosmic_starfield_enabled': true,
          'chat_wallpaper_1': 'glyphs',
        });
        final settings = SettingsProvider(initialThemePreference: 'dark');

        await settings.loadChatBackground(1);

        expect(settings.chatBackground, ChatBackgroundPreference.themeDefault);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('chat_wallpaper_1'), 'theme_default');
      },
    );

    test(
      'legacy Cosmic-off migrates each account to plain without deleting source',
      () async {
        SharedPreferences.setMockInitialValues({
          'theme_preference': 'cosmic',
          'cosmic_starfield_enabled': false,
        });

        final first = SettingsProvider(initialThemePreference: 'dark');
        await first.loadChatBackground(1);
        expect(first.chatBackground, ChatBackgroundPreference.plain);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('cosmic_starfield_enabled'), isFalse);

        final second = SettingsProvider(initialThemePreference: 'dark');
        await second.loadChatBackground(2);
        expect(second.chatBackground, ChatBackgroundPreference.plain);
        expect(prefs.getString('chat_wallpaper_1'), 'plain');
        expect(prefs.getString('chat_wallpaper_2'), 'plain');
      },
    );

    test('migrates legacy per-conversation glyph keys for one user', () async {
      SharedPreferences.setMockInitialValues({
        'theme_preference': 'dark',
        'conversation_wallpaper_1:10': 'glyphs',
        'conversation_wallpaper_1:11': 'default',
        'conversation_wallpaper_2:30': 'glyphs',
      });
      final settings = SettingsProvider(initialThemePreference: 'dark');

      await settings.loadChatBackground(1);

      expect(settings.chatBackground, ChatBackgroundPreference.glyphs);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('chat_wallpaper_1'), 'hieroglyphs');
      expect(prefs.containsKey('conversation_wallpaper_1:10'), isFalse);
      expect(prefs.containsKey('conversation_wallpaper_1:11'), isFalse);
      expect(prefs.containsKey('conversation_wallpaper_2:30'), isTrue);
    });

    test(
      'explicit legacy default wins over per-conversation glyph keys',
      () async {
        SharedPreferences.setMockInitialValues({
          'theme_preference': 'dark',
          'chat_wallpaper_1': 'default',
          'conversation_wallpaper_1:10': 'glyphs',
        });
        final settings = SettingsProvider(initialThemePreference: 'dark');

        await settings.loadChatBackground(1);

        expect(settings.chatBackground, ChatBackgroundPreference.themeDefault);
      },
    );

    test(
      'legacy dark-mode preference is used when theme key is absent',
      () async {
        SharedPreferences.setMockInitialValues({
          'dark_mode_preference': 'light',
          'cosmic_starfield_enabled': false,
          'chat_wallpaper_1': 'glyphs',
        });
        final settings = SettingsProvider(initialThemePreference: 'cosmic');

        await settings.loadChatBackground(1);

        expect(settings.chatBackground, ChatBackgroundPreference.glyphs);
      },
    );
  });
}
