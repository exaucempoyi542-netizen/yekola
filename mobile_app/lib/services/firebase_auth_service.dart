import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_app/config/api_config.dart';

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final String _djangoBaseUrl = ApiConfig.apiBaseUrl;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Inscription Firebase ; la sync Django est non bloquante.
  Future<UserCredential?> register(
    String name,
    String email,
    String password,
  ) async {
    try {
      final UserCredential credential = await _auth
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          )
          .timeout(const Duration(seconds: 20));

      await credential.user?.updateDisplayName(name.trim());

      // Sync Django en arrière-plan (ne doit jamais faire échouer l'inscription Firebase)
      _syncDjangoRegister(
        name: name,
        email: email,
        password: password,
        firebaseUid: credential.user?.uid,
      );

      return credential;
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Register Error: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  Future<void> _syncDjangoRegister({
    required String name,
    required String email,
    required String password,
    String? firebaseUid,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_djangoBaseUrl/register/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': email.split('@').first,
              'email': email.trim().toLowerCase(),
              'password': password,
              'name': name.trim(),
              if (firebaseUid != null) 'firebase_uid': firebaseUid,
            }),
          )
          .timeout(const Duration(seconds: 25));
      debugPrint('Sync Django Register Status: ${response.statusCode}');
    } catch (e) {
      debugPrint('Attention: Échec de la sync Django lors du register: $e');
    }
  }

  Future<UserCredential?> login(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final token = await credential.user?.getIdToken();
      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('firebase_token', token);
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Login Error: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user', message: 'Non connecté à Firebase.');
    }
    await user.updatePassword(newPassword);
  }

  Future<void> logout() async {
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('firebase_token');
  }

  Future<String?> getToken() async {
    return await _auth.currentUser?.getIdToken();
  }
}
