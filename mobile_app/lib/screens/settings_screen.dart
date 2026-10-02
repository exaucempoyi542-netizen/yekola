import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_app/providers/auth_provider.dart';
import 'package:mobile_app/providers/settings_provider.dart';
import 'package:mobile_app/l10n/app_localizations.dart';
import 'privacy_screen.dart';
import 'security_screen.dart';
import 'support_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _darkMode = false;
  bool _soundEnabled = true;
  bool _downloadOnWifi = true;
  String _selectedLanguage = 'Français';

  final List<String> _languages = ['Français', 'Anglais', 'Lingala', 'Swahili'];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // We now use SettingsProvider for dark mode and language
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
        _soundEnabled = prefs.getBool('sound_enabled') ?? true;
        _downloadOnWifi = prefs.getBool('download_on_wifi') ?? true;
      });
    }
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final l10n = AppLocalizations.of(context);
    final userName = authProvider.userName;
    final userEmail = authProvider.userEmail;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(l10n.translate('settings'), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
      ),
      body: ListView(
        children: [
          // Profile card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF152A45), Color(0xFF1E3A5F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF152A45).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white24,
                  backgroundImage: authProvider.hasCustomAvatar
                      ? MemoryImage(authProvider.avatarBytes!)
                      : null,
                  child: authProvider.hasCustomAvatar
                      ? null
                      : (authProvider.hasEmojiAvatar
                          ? Text(authProvider.profileEmoji!, style: const TextStyle(fontSize: 28))
                          : Text(
                              (userName.isNotEmpty ? userName[0] : 'U').toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                            )),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userName.isNotEmpty ? userName : 'Utilisateur',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(userEmail, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                const Icon(Icons.verified_rounded, color: Colors.amber),
              ],
            ),
          ),

          _buildSection(l10n.translate('preferences'), [
            _buildSwitchTile(
              icon: Icons.notifications_active_rounded,
              iconColor: Colors.orange,
              title: l10n.translate('notifications'),
              subtitle: l10n.translate('notifications_sub'),
              value: _notificationsEnabled,
              onChanged: (v) {
                setState(() => _notificationsEnabled = v);
                _saveSetting('notifications_enabled', v);
              },
            ),
            _buildDivider(),
            _buildSwitchTile(
              icon: Icons.dark_mode_rounded,
              iconColor: Colors.amber,
              title: l10n.translate('dark_mode'),
              subtitle: l10n.translate('dark_mode_sub'),
              value: settings.themeMode == ThemeMode.dark,
              onChanged: (v) => settings.toggleTheme(v),
            ),
            _buildDivider(),
            _buildNavigationTile(
              icon: Icons.language_rounded,
              iconColor: Colors.purple,
              title: l10n.translate('language'),
              subtitle: settings.languageName,
              onTap: () => _showLanguagePicker(settings),
            ),
          ]),

          _buildSection(l10n.translate('account'), [
            _buildNavigationTile(
              icon: Icons.lock_outline_rounded,
              iconColor: Colors.indigo,
              title: l10n.translate('privacy'),
              subtitle: 'Gérer vos données personnelles',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyScreen())),
            ),
            _buildDivider(),
            _buildNavigationTile(
              icon: Icons.security_rounded,
              iconColor: Colors.green,
              title: l10n.translate('security'),
              subtitle: 'Mot de passe & authentification',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityScreen())),
            ),
          ]),

          _buildSection(l10n.translate('support'), [
            _buildNavigationTile(
              icon: Icons.help_outline_rounded,
              iconColor: Colors.cyan,
              title: l10n.translate('help'),
              subtitle: 'FAQ, contact et signalement',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen())),
            ),
            _buildDivider(),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFF0F4FF),
                child: Icon(Icons.info_outline_rounded, color: Color(0xFF152A45)),
              ),
              title: Text(l10n.translate('version'), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Yekola v1.0.0 (build 1)'),
            ),
          ]),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 10),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF152A45),
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(children: children),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: CircleAvatar(
        backgroundColor: iconColor.withValues(alpha: 0.1),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      value: value,
      activeColor: const Color(0xFF152A45),
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildNavigationTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: iconColor.withValues(alpha: 0.1),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildDivider() => Padding(
    padding: const EdgeInsets.only(left: 72),
    child: Divider(height: 1, color: Colors.grey[100]),
  );

  void _showLanguagePicker(SettingsProvider settings) {
    final Map<String, String> langMap = {
      'Français': 'fr',
      'Anglais': 'en',
      'Lingala': 'ln',
      'Swahili': 'sw',
    };

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('Choisir une langue / Choose a language', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ..._languages.map((lang) => ListTile(
              title: Text(lang),
              leading: const Icon(Icons.language_rounded),
              trailing: settings.languageName == lang
                  ? const Icon(Icons.check_circle_rounded, color: Color(0xFF152A45))
                  : null,
              onTap: () {
                settings.setLanguage(langMap[lang]!);
                Navigator.pop(context);
              },
            )),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}
