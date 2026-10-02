import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Profils publics synchronisés sur Firestore (visibles par les autres utilisateurs).
class FirebaseProfileService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _collection = 'public_profiles';

  String _docId(String email) => email.trim().toLowerCase();

  /// Publie / met à jour mon profil public.
  Future<void> publishMyProfile({
    required String email,
    required String displayName,
    String? emoji,
    String? avatarBase64,
    String? role,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final id = _docId(email);
    if (id.isEmpty) return;

    try {
      await _db.collection(_collection).doc(id).set({
        'email': id,
        'display_name': displayName.trim().isEmpty ? id.split('@').first : displayName.trim(),
        'emoji': emoji,
        'avatar_base64': avatarBase64,
        'role': role,
        'firebase_uid': user.uid,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Profile] publish error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getProfile(String email) async {
    final id = _docId(email);
    if (id.isEmpty) return null;
    try {
      final doc = await _db.collection(_collection).doc(id).get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      data['id'] = doc.id;
      return data;
    } catch (e) {
      debugPrint('[Profile] getProfile error: $e');
      return null;
    }
  }

  Stream<Map<String, dynamic>?> streamProfile(String email) {
    final id = _docId(email);
    if (id.isEmpty) return Stream.value(null);
    return _db.collection(_collection).doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data()!;
      data['id'] = doc.id;
      return data;
    });
  }

  /// Charge plusieurs profils (recherche chat, liste de salles).
  Future<Map<String, Map<String, dynamic>>> getProfiles(List<String> emails) async {
    final result = <String, Map<String, dynamic>>{};
    final unique = emails.map(_docId).where((e) => e.isNotEmpty).toSet().toList();
    await Future.wait(unique.map((email) async {
      final p = await getProfile(email);
      if (p != null) result[email] = p;
    }));
    return result;
  }

  static Uint8List? avatarBytesOf(Map<String, dynamic>? profile) {
    final b64 = profile?['avatar_base64']?.toString();
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  static String displayNameOf(Map<String, dynamic>? profile, {String fallback = 'Utilisateur'}) {
    final name = profile?['display_name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    final email = profile?['email']?.toString() ?? '';
    if (email.contains('@')) return email.split('@').first;
    return fallback;
  }

  static String? emojiOf(Map<String, dynamic>? profile) {
    final e = profile?['emoji']?.toString().trim();
    return (e != null && e.isNotEmpty) ? e : null;
  }
}
