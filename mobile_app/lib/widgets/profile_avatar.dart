import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/firebase_profile_service.dart';

/// Avatar réutilisable à partir d'un profil public (Firestore) ou données locales.
class ProfileAvatar extends StatelessWidget {
  final String? email;
  final String? displayName;
  final String? emoji;
  final Uint8List? avatarBytes;
  final Map<String, dynamic>? profile;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const ProfileAvatar({
    super.key,
    this.email,
    this.displayName,
    this.emoji,
    this.avatarBytes,
    this.profile,
    this.radius = 24,
    this.backgroundColor,
    this.foregroundColor,
  });

  /// Charge le profil Firestore en direct si [email] est fourni.
  factory ProfileAvatar.fromEmail(
    String email, {
    Key? key,
    double radius = 24,
    Color? backgroundColor,
  }) {
    return ProfileAvatar(
      key: key,
      email: email,
      radius: radius,
      backgroundColor: backgroundColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (email != null && email!.trim().isNotEmpty && profile == null && avatarBytes == null && emoji == null) {
      return StreamBuilder<Map<String, dynamic>?>(
        stream: FirebaseProfileService().streamProfile(email!),
        builder: (context, snapshot) {
          return _buildAvatar(snapshot.data);
        },
      );
    }
    return _buildAvatar(profile);
  }

  Widget _buildAvatar(Map<String, dynamic>? remote) {
    final bytes = avatarBytes ?? FirebaseProfileService.avatarBytesOf(remote);
    final em = emoji ?? FirebaseProfileService.emojiOf(remote);
    final name = displayName ?? FirebaseProfileService.displayNameOf(remote, fallback: email?.split('@').first ?? '?');
    final bg = backgroundColor ?? const Color(0xFF152A45).withValues(alpha: 0.12);
    final fg = foregroundColor ?? const Color(0xFF152A45);

    if (bytes != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        backgroundImage: MemoryImage(bytes),
      );
    }
    if (em != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Text(em, style: TextStyle(fontSize: radius * 0.95)),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: radius * 0.75),
      ),
    );
  }
}
