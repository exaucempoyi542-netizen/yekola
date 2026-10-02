import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  Locale _locale = const Locale('fr');
  
  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;

  String get languageName {
    switch (_locale.languageCode) {
      case 'en': return 'Anglais';
      case 'ln': return 'Lingala';
      case 'sw': return 'Swahili';
      default: return 'Français';
    }
  }

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load Theme
    final isDarkMode = prefs.getBool('dark_mode') ?? false;
    _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    
    // Load Locale
    final langCode = prefs.getString('language_code') ?? 'fr';
    _locale = Locale(langCode);
    
    notifyListeners();
  }

  Future<void> toggleTheme(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', isDark);
    notifyListeners();
  }

  Future<void> setLanguage(String langCode) async {
    _locale = Locale(langCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', langCode);
    notifyListeners();
  }
}
