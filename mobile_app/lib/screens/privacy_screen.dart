import 'package:flutter/material.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _profileVisible = true;
  bool _showProgress = true;
  bool _allowRecommendations = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Confidentialité', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.cardColor,
        foregroundColor: const Color(0xFF152A45),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        children: [
          // Hero header
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3A5F), Color(0xFF152A45)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              children: [
                Icon(Icons.privacy_tip_rounded, size: 48, color: Colors.white),
                SizedBox(height: 12),
                Text('Votre vie privée nous tient à cœur',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    textAlign: TextAlign.center),
                SizedBox(height: 6),
                Text('Configurez qui peut voir quoi sur votre compte.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center),
              ],
            ),
          ),

          _buildSection(context, 'Visibilité', [
            _buildSwitchTile(
              icon: Icons.person_outline_rounded,
              iconColor: Colors.blue,
              title: 'Profil visible',
              subtitle: 'Visible par vos enseignants et admins',
              value: _profileVisible,
              onChanged: (v) => setState(() => _profileVisible = v),
            ),
            _buildDivider(),
            _buildSwitchTile(
              icon: Icons.bar_chart_rounded,
              iconColor: Colors.teal,
              title: 'Progression partagée',
              subtitle: 'Vos enseignants peuvent voir votre avancement',
              value: _showProgress,
              onChanged: (v) => setState(() => _showProgress = v),
            ),
            _buildDivider(),
            _buildSwitchTile(
              icon: Icons.recommend_rounded,
              iconColor: Colors.orange,
              title: 'Recommandations personnalisées',
              subtitle: 'Utiliser mes données pour suggérer des cours',
              value: _allowRecommendations,
              onChanged: (v) => setState(() => _allowRecommendations = v),
            ),
          ]),

          _buildSection(context, 'Données personnelles', [
            _buildInfoTile(
              icon: Icons.storage_rounded,
              iconColor: Colors.indigo,
              title: 'Collecte des données',
              subtitle: 'Nom, email et progression de cours uniquement',
            ),
            _buildDivider(),
            _buildInfoTile(
              icon: Icons.share_outlined,
              iconColor: Colors.purple,
              title: 'Partage des données',
              subtitle: 'Jamais partagées à des tiers commerciaux',
            ),
          ]),

          _buildSection(context, 'Actions', [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.download_rounded, color: Colors.green, size: 20),
              ),
              title: const Text('Exporter mes données', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Télécharger une copie de vos données'),
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Votre demande d\'export a été envoyée.'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
            _buildDivider(),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFEBEE),
                child: Icon(Icons.delete_forever_rounded, color: Colors.red, size: 20),
              ),
              title: const Text('Supprimer mon compte',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
              subtitle: const Text('Action irréversible'),
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              onTap: () => _confirmAccountDeletion(context),
            ),
          ]),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 10),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: theme.textTheme.titleSmall?.color ?? const Color(0xFF152A45),
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(children: children),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSwitchTile({required IconData icon, required Color iconColor, required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) {
    final theme = Theme.of(context);
    return SwitchListTile(
      secondary: CircleAvatar(backgroundColor: iconColor.withValues(alpha: 0.1), child: Icon(icon, color: iconColor, size: 20)),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: theme.textTheme.bodyMedium?.color)),
      subtitle: Text(subtitle, style: TextStyle(color: theme.textTheme.bodySmall?.color ?? Colors.grey[600], fontSize: 12)),
      value: value,
      activeColor: const Color(0xFF152A45),
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildInfoTile({required IconData icon, required Color iconColor, required String title, required String subtitle}) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(backgroundColor: iconColor.withValues(alpha: 0.1), child: Icon(icon, color: iconColor, size: 20)),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: theme.textTheme.bodyMedium?.color)),
      subtitle: Text(subtitle, style: TextStyle(color: theme.textTheme.bodySmall?.color ?? Colors.grey[600], fontSize: 12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildDivider() => Padding(
    padding: const EdgeInsets.only(left: 72),
    child: Divider(height: 1, color: Colors.grey[100]),
  );

  void _confirmAccountDeletion(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer le compte', style: TextStyle(color: Colors.red)),
        content: const Text('Cette action est irréversible. Toutes vos données seront perdues. Êtes-vous sûr?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Demande de suppression envoyée.'), backgroundColor: Colors.red),
              );
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
