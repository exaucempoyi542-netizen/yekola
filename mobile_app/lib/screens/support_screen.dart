import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Aide & Support', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.cardColor,
        foregroundColor: const Color(0xFF152A45),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        children: [
          // Header
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF152A45), Color(0xFF1E3A5F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              children: [
                Icon(Icons.support_agent_rounded, size: 48, color: Colors.white),
                SizedBox(height: 12),
                Text('Comment pouvons-nous vous aider ?',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    textAlign: TextAlign.center),
                SizedBox(height: 6),
                Text('Notre équipe est disponible du lundi au samedi de 8h à 18h.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center),
              ],
            ),
          ),

          // Quick Contact
          _buildSection(context, 'Nous contacter', [
            _buildContactTile(
              context,
              icon: Icons.email_outlined,
              iconColor: Colors.blue,
              title: 'Email',
              subtitle: 'support@edurdc.cd',
              onTap: () => _launchUrl('mailto:support@edurdc.cd'),
            ),
            _divider(),
            _buildContactTile(
              context,
              icon: Icons.phone_outlined,
              iconColor: Colors.green,
              title: 'Appel téléphonique',
              subtitle: '+243 81 234 5678',
              onTap: () => _launchUrl('tel:+243812345678'),
            ),
            _divider(),
            _buildContactTile(
              context,
              icon: Icons.chat_outlined,
              iconColor: Colors.teal,
              title: 'Chat en direct',
              subtitle: 'Réponse en moins de 5 minutes',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat en cours de chargement...')),
                );
              },
            ),
          ]),

          // FAQ
          _buildSection(context, 'Questions fréquentes', [
            _buildFaqTile(context, 'Comment m\'inscrire à un cours ?',
                'Allez dans le catalogue, trouvez le cours, appuyez sur "S\'inscrire". Vous aurez besoin d\'un compte actif.'),
            _divider(),
            _buildFaqTile(context, 'Comment récupérer mon mot de passe ?',
                'Sur l\'écran de connexion, cliquez sur "Mot de passe oublié" et entrez votre adresse email pour recevoir un lien de réinitialisation.'),
            _divider(),
            _buildFaqTile(context, 'Puis-je suivre des cours hors ligne ?',
                'Certains contenus peuvent être téléchargés via l\'option de téléchargement Wi-Fi dans les Paramètres.'),
            _divider(),
            _buildFaqTile(context, 'Comment contacter mon enseignant ?',
                'Utilisez le bouton de messagerie (icône chat) dans le tableau de bord pour ouvrir une conversation directement avec votre enseignant.'),
          ]),

          // Signalement
          _buildSection(context, 'Signalement', [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFEBEE),
                child: Icon(Icons.flag_outlined, color: Colors.red, size: 20),
              ),
              title: const Text('Signaler un problème', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text('Bogue, contenu inapproprié, etc.', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              onTap: () => _showReportDialog(context),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            ),
            _divider(),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFF3E0),
                child: Icon(Icons.star_outline_rounded, color: Colors.orange, size: 20),
              ),
              title: const Text('Évaluer l\'application', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text('Votre avis nous aide à nous améliorer', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Merci pour votre évaluation !')),
                );
              },
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(children: children),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildContactTile(BuildContext context, {required IconData icon, required Color iconColor, required String title, required String subtitle, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(backgroundColor: iconColor.withValues(alpha: 0.1), child: Icon(icon, color: iconColor, size: 20)),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: theme.textTheme.bodyMedium?.color)),
      subtitle: Text(subtitle, style: TextStyle(color: theme.textTheme.bodySmall?.color ?? Colors.grey[600], fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildFaqTile(BuildContext context, String question, String answer) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: theme.highlightColor.withValues(alpha: 0.1),
        child: const Icon(Icons.help_outline_rounded, color: Color(0xFF152A45), size: 20),
      ),
      title: Text(question, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: theme.textTheme.bodyMedium?.color)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 16),
          child: Text(answer, style: TextStyle(color: theme.textTheme.bodySmall?.color ?? Colors.grey[700], fontSize: 13, height: 1.5)),
        ),
      ],
    );
  }

  Widget _divider() => Padding(
    padding: const EdgeInsets.only(left: 72),
    child: Divider(height: 1, color: Colors.grey[100]),
  );

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _showReportDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Signaler un problème'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Décrivez le problème rencontré...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF152A45)),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Merci ! Votre signalement a été envoyé.'), backgroundColor: Colors.green),
              );
            },
            child: const Text('Envoyer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
