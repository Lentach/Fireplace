import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/rpg_theme.dart';
import '../models/chat_background_preference.dart';

class SettingsProvider extends ChangeNotifier {
  /// Default color theme for fresh installs / unset devices (owner ruling
  /// 2026-07-28): Hot Stone — the warm-paper + ember light theme ('light').
  /// Saved preferences always win; the legacy dark_mode_preference migration
  /// still maps old dark/system choices to 'dark'.
  static const String kDefaultThemePreference = 'light';

  static bool _isValidTheme(String? value) =>
      value == 'light' ||
      value == 'teal' ||
      value == 'dark' ||
      value == 'cosmic' ||
      value == 'blue';

  /// 'light' (Hot Stone) | 'teal' (Teal+stone, light) | 'dark' (Wire gray) |
  /// 'blue' (Telegram dark) | 'cosmic' (starfield dark)
  String _themePreference = kDefaultThemePreference;

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
      case 'teal':
        return RpgTheme.themeDataTealStone;
      case 'dark':
        return RpgTheme.themeDataDarkGray;
      case 'cosmic':
        return RpgTheme.themeDataCosmic;
      case 'blue':
        return RpgTheme.themeDataBlue;
      case 'light':
      default:
        return RpgTheme.themeDataLight;
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

  /// [initialThemePreference] sets theme synchronously; main.dart resolves the
  /// saved value via [storedThemePreference] BEFORE runApp so frame 1 paints
  /// the right theme for returning users (no light↔dark cold-start flash).
  /// Widget tests pass explicit values. Invalid/null falls back to the async
  /// prefs load.
  SettingsProvider({String? initialThemePreference}) {
    if (_isValidTheme(initialThemePreference)) {
      _themePreference = initialThemePreference!;
    } else {
      _loadThemePreference();
    }
    _loadLocalePreference();
    _loadContactsListView();
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

  /// Contacts tab presentation: `false` = honeycomb node map (default),
  /// `true` = classic tile list. Device-local, not per-account — it is a
  /// view preference, not user data.
  bool _contactsListView = false;

  bool get contactsListView => _contactsListView;

  Future<void> _loadContactsListView() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_contactsListViewKey);
    if (saved == null || saved == _contactsListView) return;
    _contactsListView = saved;
    notifyListeners();
  }

  Future<void> setContactsListView(bool useList) async {
    if (_contactsListView == useList) return;
    _contactsListView = useList;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_contactsListViewKey, useList);
  }

  static const String _contactsListViewKey = 'contacts_list_view';

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    _themePreference = _resolveStoredTheme(prefs);
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

  /// Resolves the persisted theme (including the legacy dark_mode_preference
  /// migration) without constructing a provider. main.dart awaits this BEFORE
  /// runApp and passes the result as [initialThemePreference].
  static Future<String> storedThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    return _resolveStoredTheme(prefs);
  }

  static String _resolveStoredTheme(
    SharedPreferences prefs, {
    String fallback = kDefaultThemePreference,
  }) {
    final saved = prefs.getString('theme_preference');
    if (_isValidTheme(saved)) return saved!;
    final legacy = prefs.getString('dark_mode_preference');
    if (legacy == 'light') return 'light';
    if (legacy == 'dark' || legacy == 'system') return 'dark';
    return fallback;
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
      // Fallback is the LIVE field, not the fresh-install const: a provider
      // constructed with [initialThemePreference] (prefs unwritten) must still
      // see its injected theme for this migration decision.
      final savedTheme = _resolveStoredTheme(prefs, fallback: _themePreference);
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
