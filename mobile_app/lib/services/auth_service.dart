import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_app/config/api_config.dart';

class LoginResult {
  final bool success;
  final bool requiresProfileCompletion;
  final Map<String, dynamic>? user;

  const LoginResult({
    required this.success,
    this.requiresProfileCompletion = false,
    this.user,
  });
}

class AuthService {
  final String _baseUrl = ApiConfig.apiBaseUrl;

  /// Connexion JWT Django — matricule, e-mail ou nom d'utilisateur.
  Future<LoginResult> login(String usernameOrEmail, String password) async {
    try {
      final candidates = <String>[];
      final raw = usernameOrEmail.trim();
      final pwd = password.trim();
      if (raw.isNotEmpty) {
        candidates.add(raw);
        final upper = raw.toUpperCase();
        if (upper != raw) candidates.add(upper);
      }
      if (raw.contains('@')) {
        candidates.add(raw.split('@').first);
      }

      LoginResult? lastResult;
      for (final candidate in candidates) {
        lastResult = await _tryLogin(candidate, pwd);
        if (lastResult.success) {
          return lastResult;
        }
      }

      // Pont Firebase uniquement si l'identifiant ressemble à un e-mail
      if (raw.contains('@')) {
        final synced = await _firebaseSyncLogin(raw, pwd);
        if (synced.success) return synced;
      }

      return lastResult ?? const LoginResult(success: false);
    } catch (e) {
      debugPrint("Erreur réseau AuthService: $e");
      return const LoginResult(success: false);
    }
  }

  Future<LoginResult> _firebaseSyncLogin(String email, String password) async {
    try {
      final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
      final response = await http.post(
        Uri.parse('$_baseUrl/token/firebase-sync/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim().toLowerCase(),
          'password': password,
          if (firebaseUid != null) 'firebase_uid': firebaseUid,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _storeTokens(data);
        final user = data['user'] is Map ? Map<String, dynamic>.from(data['user']) : null;
        debugPrint('Django JWT via firebase-sync OK for $email');
        return LoginResult(
          success: true,
          requiresProfileCompletion: user?['requires_email_setup'] == true,
          user: user,
        );
      }
      debugPrint('firebase-sync failed: ${response.statusCode} ${response.body}');
      return const LoginResult(success: false);
    } catch (e) {
      debugPrint('firebase-sync exception: $e');
      return const LoginResult(success: false);
    }
  }

  Future<LoginResult> _tryLogin(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/token/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _storeTokens(data);
        final user = data['user'] is Map ? Map<String, dynamic>.from(data['user']) : null;
        debugPrint("Django JWT token stored successfully for '$username'");
        return LoginResult(
          success: true,
          requiresProfileCompletion: user?['requires_email_setup'] == true,
          user: user,
        );
      }
      debugPrint("Django JWT login failed for '$username': ${response.statusCode} ${response.body}");
      return const LoginResult(success: false);
    } catch (e) {
      debugPrint("Django JWT login exception for '$username': $e");
      return const LoginResult(success: false);
    }
  }

  /// Échange le JWT Django contre une session Firebase Auth (chat + notifications).
  Future<UserCredential?> signInFirebaseWithCustomToken() async {
    try {
      final access = await getToken();
      if (access == null || access.isEmpty) return null;

      final response = await http.post(
        Uri.parse('$_baseUrl/token/firebase-custom/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $access',
        },
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        debugPrint('firebase-custom failed: ${response.statusCode} ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final firebaseToken = (data['firebase_token'] ?? '').toString();
      if (firebaseToken.isEmpty) return null;

      final credential =
          await FirebaseAuth.instance.signInWithCustomToken(firebaseToken);
      debugPrint('Firebase custom token OK uid=${credential.user?.uid}');
      return credential;
    } catch (e) {
      debugPrint('signInFirebaseWithCustomToken error: $e');
      return null;
    }
  }

  Future<void> _storeTokens(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('django_access', data['access']);
    await prefs.setString('django_refresh', data['refresh']);
    if (data['user'] is Map) {
      final user = Map<String, dynamic>.from(data['user']);
      if (user['id'] != null) await prefs.setInt('user_id', user['id'] as int);
      if (user['role'] != null) await prefs.setString('role', user['role'].toString());
      if (user['username'] != null) await prefs.setString('username', user['username'].toString());
      if (user['email'] != null) await prefs.setString('email', user['email'].toString());
      await prefs.setBool(
        'requires_profile_completion',
        user['requires_email_setup'] == true,
      );
    }
  }

  Future<Map<String, dynamic>?> completeProfile(String email) async {
    try {
      final token = await getToken();
      if (token == null) return null;

      final response = await http.post(
        Uri.parse('$_baseUrl/users/complete-profile/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'email': email.trim().toLowerCase()}),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final profile = jsonDecode(response.body) as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('email', (profile['email'] ?? email).toString());
        await prefs.setBool('requires_profile_completion', false);
        return profile;
      }
      debugPrint('completeProfile failed: ${response.statusCode} ${response.body}');
      return null;
    } catch (e) {
      debugPrint('completeProfile exception: $e');
      return null;
    }
  }

  Future<String?> changePassword(String oldPassword, String newPassword) async {
    try {
      final token = await getToken();
      if (token == null) {
        return 'Session expirée. Reconnectez-vous.';
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/users/change-password/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'old_password': oldPassword,
          'new_password': newPassword,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return null;
      }

      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['detail'] != null) {
          return data['detail'].toString();
        }
      } catch (_) {}

      return 'Impossible de modifier le mot de passe (${response.statusCode}).';
    } catch (e) {
      debugPrint('changePassword exception: $e');
      return 'Erreur réseau lors du changement de mot de passe.';
    }
  }

  Future<bool> register(String name, String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/register/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': email.split('@').first,
          'email': email.trim().toLowerCase(),
          'password': password,
          'name': name.trim(),
        }),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 201 || response.statusCode == 200) {
        return true;
      }
      debugPrint("Erreur Inscription: ${response.statusCode} ${response.body}");
      return false;
    } catch (e) {
      debugPrint("Erreur réseau AuthService Register: $e");
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('django_access');
    await prefs.remove('django_refresh');
    await prefs.remove('requires_profile_completion');
  }

  Future<bool> get requiresProfileCompletion async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('requires_profile_completion') ?? false;
  }

  /// Retourne le token d'accès JWT stocké.
  /// Si le token est expiré, tente un rafraîchissement automatique.
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('django_access');

    if (accessToken == null) {
      debugPrint('[AuthService] Aucun token JWT trouvé - reconnexion requise.');
      return null;
    }

    // Vérifier l'expiration uniquement sur mobile (pas en Web)
    if (!kIsWeb) {
      final expired = _isTokenExpired(accessToken);
      if (expired) {
        debugPrint('[AuthService] Token expiré, tentative de rafraîchissement...');
        final refreshed = await refreshToken();
        if (refreshed) {
          return prefs.getString('django_access');
        } else {
          debugPrint('[AuthService] Rafraîchissement échoué, utilisation de l\'ancien token.');
          return accessToken;
        }
      }
    }

    return accessToken;
  }

  Future<bool> refreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshTok = prefs.getString('django_refresh');
      if (refreshTok == null) return false;

      final response = await http.post(
        Uri.parse('$_baseUrl/token/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refreshTok}),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await prefs.setString('django_access', data['access']);
        debugPrint('[AuthService] Token rafraîchi avec succès.');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[AuthService] Erreur lors du rafraîchissement: $e');
      return false;
    }
  }

  bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;

      String payload = parts[1];
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }

      final decoded = jsonDecode(utf8.decode(base64Url.decode(payload)));
      final exp = decoded['exp'] as int?;
      if (exp == null) return false;

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return now >= (exp - 30);
    } catch (e) {
      return false;
    }
  }
}
