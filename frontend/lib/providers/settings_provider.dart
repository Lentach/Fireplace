import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/rpg_theme.dart';


enum ConversationWallpaper { defaultBackground, glyphs }
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

  ConversationWallpaper conversationWallpaper(int userId, int conversationId) {
    final value = _conversationWallpapers['$userId:$conversationId'];
    return value == 'glyphs'
        ? ConversationWallpaper.glyphs
        : ConversationWallpaper.defaultBackground;
  }

  final Map<String, String> _conversationWallpapers = {};

  Future<void> loadConversationWallpaper(int userId, int conversationId) async {
    final key = '$userId:$conversationId';
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('conversation_wallpaper_$key');
    if (value == 'glyphs') {
      _conversationWallpapers[key] = value!;
    } else {
      _conversationWallpapers.remove(key);
    }
    notifyListeners();
  }

  Future<void> setConversationWallpaper(
    int userId,
    int conversationId,
    ConversationWallpaper wallpaper,
  ) async {
    final key = '$userId:$conversationId';
    if (wallpaper == ConversationWallpaper.glyphs) {
      _conversationWallpapers[key] = 'glyphs';
    } else {
      _conversationWallpapers.remove(key);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final preferenceKey = 'conversation_wallpaper_$key';
    if (wallpaper == ConversationWallpaper.glyphs) {
      await prefs.setString(preferenceKey, 'glyphs');
    } else {
      await prefs.remove(preferenceKey);
    }
  }
}
