import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/rpg_theme.dart';
import '../models/chat_background_preference.dart';

class SettingsProvider extends ChangeNotifier {
  /// 'light' | 'teal' (Teal+stone, light) | 'dark' (Wire gray) | 'blue'
  /// (Telegram dark) | 'cosmic' (starfield dark)
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
      case 'cosmic':
        return RpgTheme.themeDataCosmic;
      case 'blue':
      default:
        return RpgTheme.themeDataBlue;
    }
  }

  ThemeData get darkTheme {
    switch (_themePreference) {
      case 'dark':
        return RpgTheme.themeDataDarkGray;
      case 'cosmic':
        return RpgTheme.themeDataCosmic;
      default:
        return RpgTheme.themeDataBlue;
    }
  }

  /// [initialThemePreference] sets theme synchronously (widget tests); otherwise loads from prefs.
  SettingsProvider({String? initialThemePreference}) {
    if (initialThemePreference == 'light' ||
        initialThemePreference == 'teal' ||
        initialThemePreference == 'dark' ||
        initialThemePreference == 'cosmic' ||
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
        saved == 'cosmic' ||
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
        preference != 'cosmic' &&
        preference != 'blue') {
      return;
    }
    _themePreference = preference;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_preference', preference);
  }

  /// One global chat-background choice per account. `themeDefault` follows
  /// the selected color theme; explicit overrides survive theme changes.
  ChatBackgroundPreference _chatBackground =
      ChatBackgroundPreference.themeDefault;

  ChatBackgroundPreference get chatBackground => _chatBackground;

  ChatBackgroundLayer get resolvedChatBackground => resolveChatBackground(
    preference: _chatBackground,
    isCosmicTheme: _themePreference == 'cosmic',
  );

  static String _backgroundKey(int userId) => 'chat_wallpaper_$userId';
  static const String _legacyCosmicStarfieldKey = 'cosmic_starfield_enabled';

  static String _serializeBackground(ChatBackgroundPreference preference) =>
      switch (preference) {
        ChatBackgroundPreference.themeDefault => 'theme_default',
        ChatBackgroundPreference.plain => 'plain',
        ChatBackgroundPreference.glyphs => 'hieroglyphs',
      };

  static ChatBackgroundPreference? _parseBackground(String? value) =>
      switch (value) {
        'theme_default' => ChatBackgroundPreference.themeDefault,
        'plain' => ChatBackgroundPreference.plain,
        'hieroglyphs' => ChatBackgroundPreference.glyphs,
        _ => null,
      };

  String _storedThemePreference(SharedPreferences prefs) {
    final saved = prefs.getString('theme_preference');
    if (saved == 'light' ||
        saved == 'teal' ||
        saved == 'dark' ||
        saved == 'cosmic' ||
        saved == 'blue') {
      return saved!;
    }
    final legacy = prefs.getString('dark_mode_preference');
    if (legacy == 'light') return 'light';
    if (legacy == 'dark' || legacy == 'system') return 'dark';
    return _themePreference;
  }

  /// Loads the per-user background and migrates both legacy storage shapes:
  /// per-conversation wallpaper keys and the global Cosmic starfield switch.
  ///
  /// The legacy starfield key stays in preferences as migration input for
  /// other accounts that may not have logged in on this device yet. It is no
  /// longer runtime state after this account gets an explicit new value.
  Future<void> loadChatBackground(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _backgroundKey(userId);
    final stored = prefs.getString(key);
    var next = _parseBackground(stored);

    final legacyPrefix = 'conversation_wallpaper_$userId:';
    final legacyKeys = prefs
        .getKeys()
        .where((candidate) => candidate.startsWith(legacyPrefix))
        .toList(growable: false);

    if (next == null) {
      final legacyGlyphs =
          stored == 'glyphs' ||
          (stored == null &&
              legacyKeys.any(
                (candidate) => prefs.getString(candidate) == 'glyphs',
              ));
      final savedTheme = _storedThemePreference(prefs);
      if (savedTheme == 'cosmic') {
        final legacyStarfield =
            prefs.getBool(_legacyCosmicStarfieldKey) ?? true;
        next = legacyStarfield
            ? ChatBackgroundPreference.themeDefault
            : ChatBackgroundPreference.plain;
      } else {
        next = legacyGlyphs
            ? ChatBackgroundPreference.glyphs
            : ChatBackgroundPreference.themeDefault;
      }
      await prefs.setString(key, _serializeBackground(next));
    }

    for (final legacyKey in legacyKeys) {
      await prefs.remove(legacyKey);
    }

    if (next == _chatBackground) return;
    _chatBackground = next;
    notifyListeners();
  }

  Future<void> setChatBackground(
    int userId,
    ChatBackgroundPreference preference,
  ) async {
    if (preference == _chatBackground) return;
    _chatBackground = preference;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _backgroundKey(userId),
      _serializeBackground(preference),
    );
  }
}
