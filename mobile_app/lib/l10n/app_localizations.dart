import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ?? AppLocalizations(const Locale('fr'));
  }

  static const Map<String, Map<String, String>> _localizedValues = {
    'fr': {
      'settings': 'Paramètres',
      'dark_mode': 'Mode Sombre',
      'dark_mode_sub': 'Activer l\'interface sombre',
      'language': 'Langue',
      'notifications': 'Notifications Push',
      'notifications_sub': 'Alertes sur les nouveaux cours',
      'account': 'Compte & Sécurité',
      'privacy': 'Confidentialité',
      'security': 'Sécurité',
      'support': 'Support',
      'help': 'Aide & Support',
      'version': 'Version de l\'application',
      'welcome': 'Bienvenue',
      'discuss': 'Discussion',
      'home': 'Accueil',
      'catalogue': 'Catalogue',
      'menu': 'Menu',
      'no_content': 'Le contenu est vide',
      'refresh': 'RAFRAÎCHIR',
      'preferences': 'Préférences',
    },
    'en': {
      'settings': 'Settings',
      'dark_mode': 'Dark Mode',
      'dark_mode_sub': 'Turn on dark interface',
      'language': 'Language',
      'notifications': 'Push Notifications',
      'notifications_sub': 'Alerts for new courses',
      'account': 'Account & Security',
      'privacy': 'Privacy',
      'security': 'Security',
      'support': 'Support',
      'help': 'Help & Support',
      'version': 'App Version',
      'welcome': 'Welcome',
      'discuss': 'Discussion',
      'home': 'Home',
      'catalogue': 'Catalogue',
      'menu': 'Menu',
      'no_content': 'No content available at the moment.',
      'refresh': 'REFRESH',
      'preferences': 'Preferences',
    },
    'ln': {
      'settings': 'Ebongiseli',
      'dark_mode': 'Mode ya Molili',
      'dark_mode_sub': 'Pelisa molili',
      'language': 'Lokota',
      'notifications': 'Basango',
      'notifications_sub': 'Basango ya kelasi ya sika',
      'account': 'Lisolo & Kimya',
      'privacy': 'Sekele',
      'security': 'Batela',
      'support': 'Lisungi',
      'help': 'Lisungi & Boyokani',
      'version': 'Lolenge ya app',
      'welcome': 'Boyeyi bolamu',
      'discuss': 'Lisolo',
      'home': 'Yambo',
      'catalogue': 'Zando',
      'menu': 'Menu',
      'no_content': 'Eloko moko te pona sikoyo.',
      'refresh': 'BONGISA',
      'preferences': 'Malongi',
    },
    'sw': {
      'settings': 'Mipangilio',
      'dark_mode': 'Hali ya Giza',
      'dark_mode_sub': 'Washa hali ya giza',
      'language': 'Lugha',
      'notifications': 'Arifa',
      'notifications_sub': 'Arifa za kozi mpya',
      'account': 'Akaunti na Usalama',
      'privacy': 'Faragha',
      'security': 'Usalama',
      'support': 'Msaada',
      'help': 'Msaada na Mawasiliano',
      'version': 'Toleo la App',
      'welcome': 'Karibu',
      'discuss': 'Mazungumzo',
      'home': 'Nyumbani',
      'catalogue': 'Katalogi',
      'menu': 'Menyu',
      'no_content': 'Hakuna maudhui kwa sasa.',
      'refresh': 'SASISHA',
      'preferences': 'Mapendekezo',
    },
  };

  String translate(String key) {
    return _localizedValues[locale.languageCode]?[key] ?? key;
  }
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['fr', 'en', 'ln', 'sw'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
