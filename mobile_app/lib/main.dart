import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:mobile_app/screens/dashboard_screen.dart';
import 'package:mobile_app/screens/splash_screen.dart';
import 'package:mobile_app/screens/admin_dashboard_screen.dart';
import 'package:mobile_app/screens/login_screen.dart';
import 'package:mobile_app/providers/auth_provider.dart';
import 'package:mobile_app/providers/settings_provider.dart';
import 'package:mobile_app/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mobile_app/services/firebase_notification_service.dart';
import 'package:mobile_app/navigation/app_navigator.dart';
import 'firebase_options.dart';

// Locales not natively supported by flutter_localizations (e.g. Lingala, Swahili).
// These helpers load French as a fallback for Material/Widgets/Cupertino layers
// while AppLocalizations still serves the user's actual chosen language.
const Set<String> _nativeMaterialLocales = {
  'af','am','ar','az','be','bg','bn','bs','ca','cs','cy','da','de','el','en',
  'es','et','eu','fa','fi','fil','fr','gl','gsw','gu','he','hi','hr','hu',
  'hy','id','is','it','ja','ka','kk','km','kn','ko','lt','lv','mk','ml',
  'mn','mr','ms','my','nb','ne','nl','or','pa','pl','ps','pt','ro','ru',
  'si','sk','sl','sq','sr','sv','sw','ta','te','th','tl','tr','uk','ur',
  'uz','vi','zh','zu',
};

Locale _effectiveLocale(Locale locale) =>
    _nativeMaterialLocales.contains(locale.languageCode) ? locale : const Locale('fr');

class _FallbackMaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _FallbackMaterialDelegate();
  @override bool isSupported(Locale locale) => true;
  @override Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(_effectiveLocale(locale));
  @override bool shouldReload(_FallbackMaterialDelegate old) => false;
}

class _FallbackWidgetsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const _FallbackWidgetsDelegate();
  @override bool isSupported(Locale locale) => true;
  @override Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(_effectiveLocale(locale));
  @override bool shouldReload(_FallbackWidgetsDelegate old) => false;
}

class _FallbackCupertinoDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const _FallbackCupertinoDelegate();
  @override bool isSupported(Locale locale) => true;
  @override Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(_effectiveLocale(locale));
  @override bool shouldReload(_FallbackCupertinoDelegate old) => false;
}


void main() async {
  debugPrint("EDU_RDC_DEBUG: main() started");
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("EDU_RDC_DEBUG: Widgets initialized");
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // Initialiser les notifications sans bloquer l'interface
    FirebaseNotificationService().initialize().catchError((e) {
      debugPrint("Notification init error: $e");
    });
  } catch (e) {
    debugPrint("Firebase initialization error: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const EducApp(),
    ),
  );
}

class EducApp extends StatefulWidget {
  const EducApp({super.key});

  @override
  State<EducApp> createState() => _EducAppState();
}

class _EducAppState extends State<EducApp> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    // Splash court pour un démarrage ≤ 2 s
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _showSplash = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return MaterialApp(
      title: 'Yekola Administration',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      locale: settings.locale,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF152A45),
          secondary: const Color(0xFFFFC107),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF152A45),
          secondary: const Color(0xFFFFC107),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        _FallbackMaterialDelegate(),
        _FallbackWidgetsDelegate(),
        _FallbackCupertinoDelegate(),
      ],
      supportedLocales: const [
        Locale('fr'),
        Locale('en'),
        Locale('ln'),
        Locale('sw'),
      ],
      // Switch between Splash and Dashboard based on state
      home: _showSplash ? const SplashScreen(autoNavigate: false) : const DashboardScreen(),
      navigatorKey: appNavigatorKey,
      routes: {
        '/login': (_) => const LoginScreen(),
        '/dashboard': (_) => const DashboardScreen(),
        '/admin': (_) => const AdminDashboardScreen(),
      },
    );
  }
}
