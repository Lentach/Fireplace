import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/rpg_theme.dart';


enum ChatWallpaper { defaultBackground, glyphs }
class SettingsProvider extends ChangeNotifier {
  /// 'light' | 'teal' (Teal + stone, light) | 'dark' (Wire gray) | 'blue' (Telegram-style dark)
  String _themePreference = 'dark';

  /// 'pl' | 'en' — app UI language (default Polish)
  String _localeCode = 'pl';

  String get themePreference => _themePreference;

  String get localeCode => _localeCode;

  Locale get locale => Locale(_localeCode);

  ThemeMode get themeMode {
    if (_themePreference == 'light' || _themePreference == 'teal') {
      return ThemeMode.light;
    }
    return ThemeMode.dark;
  }

  /// Active [ThemeData] when [themeMode] is light (`light` or `teal`).
  ThemeData get lightTheme {
    if (_themePreference == 'teal') {
      return RpgTheme.themeDataTealStone;
    }
    return RpgTheme.themeDataLight;
  }

  ThemeData get themeData {
    switch (_themePreference) {
      case 'light':
        return RpgTheme.themeDataLight;
      case 'teal':
        return RpgTheme.themeDataTealStone;
      case 'dark':
        return RpgTheme.themeDataDarkGray;
      case 'blue':
      default:
        return RpgTheme.themeDataBlue;
    }
  }

  ThemeData get darkTheme =>
      _themePreference == 'dark'
          ? RpgTheme.themeDataDarkGray
          : RpgTheme.themeDataBlue;

  /// [initialThemePreference] sets theme synchronously (widget tests); otherwise loads from prefs.
  SettingsProvider({String? initialThemePreference}) {
    if (initialThemePreference == 'light' ||
        initialThemePreference == 'teal' ||
        initialThemePreference == 'dark' ||
        initialThemePreference == 'blue') {
      _themePreference = initialThemePreference!;
    } else {
      _loadThemePreference();
    }
    _loadLocalePreference();
  }

  Future<void> _loadLocalePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('locale_preference');
    if (saved == 'pl' || saved == 'en') {
      _localeCode = saved!;
    } else {
      _localeCode = 'pl';
    }
    notifyListeners();
  }

  Future<void> setLocalePreference(String code) async {
    if (code != 'pl' && code != 'en') return;
    _localeCode = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale_preference', code);
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    var saved = prefs.getString('theme_preference');
    if (saved == null) {
      final legacy = prefs.getString('dark_mode_preference');
      if (legacy == 'light') {
        saved = 'light';
      } else if (legacy == 'dark' || legacy == 'system') {
        saved = 'dark';
      }
    }
    if (saved == 'light' ||
        saved == 'teal' ||
        saved == 'dark' ||
        saved == 'blue') {
      _themePreference = saved!;
    } else {
      _themePreference = 'dark';
    }
    notifyListeners();
  }

  Future<void> setThemePreference(String preference) async {
    if (preference != 'light' &&
        preference != 'teal' &&
        preference != 'dark' &&
        preference != 'blue') {
      return;
    }
    _themePreference = preference;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_preference', preference);
  }

  /// Global chat wallpaper — ONE background for all conversations
  /// (owner ruling 2026-07-15; replaced the per-conversation setting).
  ChatWallpaper _chatWallpaper = ChatWallpaper.defaultBackground;

  ChatWallpaper get chatWallpaper => _chatWallpaper;

  static String _wallpaperKey(int userId) => 'chat_wallpaper_$userId';

  /// Loads the per-user global wallpaper, migrating legacy per-conversation
  /// keys once: any conversation set to glyphs turns the global setting on,
  /// then the legacy keys are deleted.
  Future<void> loadChatWallpaper(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final legacyPrefix = 'conversation_wallpaper_$userId:';
    final legacyKeys = prefs
        .getKeys()
        .where((key) => key.startsWith(legacyPrefix))
        .toList(growable: false);
    if (legacyKeys.isNotEmpty) {
      final anyGlyphs = legacyKeys.any(
        (key) => prefs.getString(key) == 'glyphs',
      );
      if (anyGlyphs && !prefs.containsKey(_wallpaperKey(userId))) {
        await prefs.setString(_wallpaperKey(userId), 'glyphs');
      }
      for (final key in legacyKeys) {
        await prefs.remove(key);
      }
    }
    final next = prefs.getString(_wallpaperKey(userId)) == 'glyphs'
        ? ChatWallpaper.glyphs
        : ChatWallpaper.defaultBackground;
    if (next == _chatWallpaper) return;
    _chatWallpaper = next;
    notifyListeners();
  }

  Future<void> setChatWallpaper(int userId, ChatWallpaper wallpaper) async {
    _chatWallpaper = wallpaper;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (wallpaper == ChatWallpaper.glyphs) {
      await prefs.setString(_wallpaperKey(userId), 'glyphs');
    } else {
      await prefs.remove(_wallpaperKey(userId));
    }
  }
}
