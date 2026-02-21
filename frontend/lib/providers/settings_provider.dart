import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/rpg_theme.dart';

class SettingsProvider extends ChangeNotifier {
  /// 'light' | 'dark' (Wire gray) | 'blue' (red-blue accent)
  String _themePreference = 'blue';

  String get themePreference => _themePreference;

  ThemeMode get themeMode {
    if (_themePreference == 'light') return ThemeMode.light;
    return ThemeMode.dark;
  }

  ThemeData get themeData {
    switch (_themePreference) {
      case 'light':
        return RpgTheme.themeDataLight;
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

  SettingsProvider() {
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    var saved = prefs.getString('theme_preference');
    if (saved == null) {
      final legacy = prefs.getString('dark_mode_preference');
      if (legacy == 'light') saved = 'light';
      else if (legacy == 'dark' || legacy == 'system') saved = 'blue';
    }
    if (saved == 'light' || saved == 'dark' || saved == 'blue') {
      _themePreference = saved;
    } else {
      _themePreference = 'blue';
    }
    notifyListeners();
  }

  Future<void> setThemePreference(String preference) async {
    if (preference != 'light' && preference != 'dark' && preference != 'blue') {
      return;
    }
    _themePreference = preference;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_preference', preference);
  }
}
