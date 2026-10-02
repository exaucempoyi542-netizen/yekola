import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool _twoFactorEnabled = false;
  bool _biometricEnabled = false;
  bool _loginAlerts = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = Provider.of<AuthProvider>(context);
    final isAuthenticated = auth.isAuthenticated;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Sécurité', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.cardColor,
        foregroundColor: const Color(0xFF152A45),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.2 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_rounded, color: Colors.green, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Niveau de sécurité',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: theme.textTheme.bodySmall?.color ?? Colors.grey)),
                      const SizedBox(height: 4),
                      Text('Bon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: theme.textTheme.titleLarge?.color)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: 0.65,
                          backgroundColor: Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          _buildSection(context, 'Authentification', [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8EAF6),
                child: Icon(Icons.lock_reset_rounded, color: Color(0xFF152A45), size: 20),
              ),
              title: Text('Changer le mot de passe', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: theme.textTheme.bodyMedium?.color)),
              subtitle: Text(
                isAuthenticated
                    ? 'Remplacez le mot de passe par défaut du décanat'
                    : 'Connectez-vous pour modifier votre mot de passe',
                style: TextStyle(color: theme.textTheme.bodySmall?.color ?? Colors.grey[600], fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: theme.hintColor),
              onTap: () {
                if (!isAuthenticated) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                  return;
                }
                _showChangePasswordDialog(context);
              },
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            ),
            _buildDivider(),
            _buildSwitchTile(
              icon: Icons.phonelink_lock_rounded,
              iconColor: Colors.deepPurple,
              title: 'Authentification 2 facteurs',
              subtitle: 'Code de vérification par SMS',
              value: _twoFactorEnabled,
              onChanged: (v) => setState(() => _twoFactorEnabled = v),
            ),
            _buildDivider(),
            _buildSwitchTile(
              icon: Icons.fingerprint_rounded,
              iconColor: Colors.teal,
              title: 'Authentification biométrique',
              subtitle: 'Empreinte digitale ou Face ID',
              value: _biometricEnabled,
              onChanged: (v) => setState(() => _biometricEnabled = v),
            ),
          ]),

          _buildSection(context, 'Alertes & Sessions', [
            _buildSwitchTile(
              icon: Icons.notifications_active_rounded,
              iconColor: Colors.orange,
              title: 'Alertes de connexion',
              subtitle: 'Notifier lors d\'un nouvel accès',
              value: _loginAlerts,
              onChanged: (v) => setState(() => _loginAlerts = v),
            ),
            _buildDivider(),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE3F2FD),
                child: Icon(Icons.devices_rounded, color: Colors.blue, size: 20),
              ),
              title: Text('Appareils connectés', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: theme.textTheme.bodyMedium?.color)),
              subtitle: Text('Gérer vos sessions actives', style: TextStyle(color: theme.textTheme.bodySmall?.color ?? Colors.grey[600], fontSize: 12)),
              trailing: Icon(Icons.chevron_right_rounded, color: theme.hintColor),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Aucun autre appareil connecté.')),
                );
              },
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            ),
          ]),

          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Conseil : changez le mot de passe par défaut dès votre première connexion. '
                    'La modification est appliquée sur Yekola et Firebase (chat et notifications).',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.9) ?? Colors.black87, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
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
          child: Text(title.toUpperCase(),
              style: const TextStyle(color: Color(0xFF152A45), fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
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
      activeThumbColor: const Color(0xFF152A45),
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildDivider() => Padding(
    padding: const EdgeInsets.only(left: 72),
    child: Divider(height: 1, color: Colors.grey[100]),
  );

  void _showChangePasswordDialog(BuildContext context) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Changer le mot de passe', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: currentCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mot de passe actuel',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Champ requis' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: newCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nouveau mot de passe',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.length < 6) return 'Minimum 6 caractères';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirmer le mot de passe',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v != newCtrl.text) return 'Les mots de passe ne correspondent pas';
                      return null;
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF152A45)),
                onPressed: isLoading
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() => isLoading = true);

                        final authProvider = Provider.of<AuthProvider>(context, listen: false);
                        authProvider.clearLastError();
                        final ok = await authProvider.updatePassword(
                          currentCtrl.text,
                          newCtrl.text,
                        );

                        if (!context.mounted) return;
                        setDialogState(() => isLoading = false);

                        if (ok) {
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text('Mot de passe mis à jour avec succès.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                authProvider.lastError ?? 'Échec du changement de mot de passe.',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Confirmer', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }
}
