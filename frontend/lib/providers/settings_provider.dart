import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  String _darkModePreference = 'dark'; // 'system', 'light', 'dark'

  String get darkModePreference => _darkModePreference;

  ThemeMode get themeMode {
    switch (_darkModePreference) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  SettingsProvider() {
    _loadDarkModePreference();
  }

  Future<void> _loadDarkModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    _darkModePreference = prefs.getString('dark_mode_preference') ?? 'dark';
    notifyListeners();
  }

  Future<void> setDarkModePreference(String preference) async {
    if (preference != 'system' && preference != 'light' && preference != 'dark') {
      return;
    }

    _darkModePreference = preference;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dark_mode_preference', preference);
  }
}
