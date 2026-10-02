import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_profile_service.dart';
import '../widgets/profile_avatar.dart';
import 'chat_detail_screen.dart';
import '../services/firebase_chat_service.dart';

/// Fiche profil publique d'un utilisateur (visible par les autres).
class UserProfileScreen extends StatelessWidget {
  final String email;
  final String? initialName;
  final String? initialRole;

  const UserProfileScreen({
    super.key,
    required this.email,
    this.initialName,
    this.initialRole,
  });

  @override
  Widget build(BuildContext context) {
    final me = Provider.of<AuthProvider>(context, listen: false);
    final isMe = me.userEmail.trim().toLowerCase() == email.trim().toLowerCase();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Profil', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF152A45),
        elevation: 0.5,
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: FirebaseProfileService().streamProfile(email),
        builder: (context, snapshot) {
          final profile = snapshot.data;
          final name = FirebaseProfileService.displayNameOf(
            profile,
            fallback: initialName ?? email.split('@').first,
          );
          final role = (profile?['role'] ?? initialRole ?? '').toString().toUpperCase();
          final roleLabel = role == 'TEACHER'
              ? 'Enseignant'
              : role == 'STUDENT'
                  ? 'Étudiant'
                  : (role.isNotEmpty ? role : 'Membre Yekola');

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 12),
              Center(
                child: ProfileAvatar(
                  email: email,
                  profile: profile,
                  radius: 56,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                roleLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                email,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _infoRow(Icons.badge_outlined, 'Identifiant public', name),
                    const Divider(height: 28),
                    _infoRow(Icons.mail_outline, 'E-mail', email),
                    const Divider(height: 28),
                    _infoRow(Icons.school_outlined, 'Rôle', roleLabel),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              if (!isMe)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        final chat = FirebaseChatService();
                        final roomId = await chat.getOrCreateDirectRoom(
                          email,
                          name,
                          otherFirebaseUid: profile?['firebase_uid']?.toString(),
                        );
                        final room = await chat.getRoomById(roomId);
                        if (room != null && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ChatDetailScreen(room: room)),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Impossible d\'ouvrir le chat: $e')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Envoyer un message', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF152A45),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              if (isMe)
                Text(
                  'Ceci est votre profil public.\nLes autres utilisateurs peuvent le consulter.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], height: 1.4),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF152A45), size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
        ),
      ],
    );
  }
}
