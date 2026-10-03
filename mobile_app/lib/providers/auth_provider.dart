import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../services/firebase_auth_service.dart';
import '../services/firebase_notification_service.dart';
import '../services/firebase_profile_service.dart';
import '../services/database_helper.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final FirebaseAuthService _authService = FirebaseAuthService();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FirebaseProfileService _profileService = FirebaseProfileService();
  bool _isAuthenticated = false;
  bool _requiresProfileCompletion = false;
  String _userName = '';
  String _userEmail = '';
  String _userMatricule = '';
  String _userRole = 'STUDENT';
  int? _userId;
  String? _profileEmoji;
  String? _avatarBase64;
  String? _pendingPassword;

  bool get isAuthenticated => _isAuthenticated;
  bool get requiresProfileCompletion => _requiresProfileCompletion;
  String get userEmail => _userEmail;
  String get userMatricule => _userMatricule;
  String get userName => _userName;
  String get userRole => _userRole;
  String? get profileEmoji => _profileEmoji;
  String? get avatarBase64 => _avatarBase64;

  Uint8List? get avatarBytes {
    if (_avatarBase64 == null || _avatarBase64!.isEmpty) return null;
    try {
      return base64Decode(_avatarBase64!);
    } catch (_) {
      return null;
    }
  }

  bool get hasCustomAvatar => avatarBytes != null;
  bool get hasEmojiAvatar =>
      !hasCustomAvatar && _profileEmoji != null && _profileEmoji!.isNotEmpty;

  Map<String, dynamic>? get user => _isAuthenticated
      ? {
          'id': _userId,
          'username': _userName,
          'email': _userEmail,
        }
      : null;

  AuthProvider() {
    _initFirebaseListener();
    _loadUserFromLocal();
  }

  String _profileKey(String suffix, [String? email]) {
    final e = (email ?? _userEmail).trim().toLowerCase();
    return 'profile_${suffix}_$e';
  }

  void _initFirebaseListener() {
    _authService.authStateChanges.listen((user) async {
      if (user == null) {
        // Session Django (matricule) sans compte Firebase : ne pas déconnecter
        final token = await AuthService().getToken();
        if (token == null) {
          _isAuthenticated = false;
          notifyListeners();
        }
      } else {
        _isAuthenticated = true;
        _userEmail = user.email ?? _userEmail;
        // Ne pas écraser un nom de profil déjà enregistré localement
        await _loadProfileForEmail(_userEmail);
        if (_userName.isEmpty) {
          _userName = user.displayName ?? user.email?.split('@')[0] ?? 'Utilisateur';
        }
        notifyListeners();
        _syncWithDjangoProfile();
      }
    });
  }

  Future<void> _loadUserFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isAuth = prefs.getBool('is_authenticated') ?? false;

      if (isAuth) {
        _isAuthenticated = true;
        _userEmail = prefs.getString('email') ?? '';
        _userRole = prefs.getString('role') ?? 'STUDENT';
        _userId = prefs.getInt('user_id');
        _requiresProfileCompletion =
            prefs.getBool('requires_profile_completion') ?? false;
        await _loadProfileForEmail(_userEmail);
        if (_userName.isEmpty) {
          _userName = prefs.getString('username') ?? '';
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Erreur lors du chargement de la session: $e');
    }
  }

  Future<void> _loadProfileForEmail(String email) async {
    if (email.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString(_profileKey('display_name', email));
    final savedEmoji = prefs.getString(_profileKey('emoji', email));
    final savedAvatar = prefs.getString(_profileKey('avatar', email));

    if (savedName != null && savedName.trim().isNotEmpty) {
      _userName = savedName.trim();
    }
    _profileEmoji = savedEmoji;
    _avatarBase64 = savedAvatar;
  }

  Future<void> _persistProfileFields() async {
    if (_userEmail.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey('display_name'), _userName);
    if (_profileEmoji != null) {
      await prefs.setString(_profileKey('emoji'), _profileEmoji!);
    } else {
      await prefs.remove(_profileKey('emoji'));
    }
    if (_avatarBase64 != null && _avatarBase64!.isNotEmpty) {
      await prefs.setString(_profileKey('avatar'), _avatarBase64!);
    } else {
      await prefs.remove(_profileKey('avatar'));
    }
    // Session courante
    await prefs.setString('username', _userName);
    await prefs.setString('email', _userEmail);

    // Publier pour que les autres utilisateurs puissent voir le profil
    await _publishPublicProfile();
  }

  Future<void> _publishPublicProfile() async {
    if (!_isAuthenticated || _userEmail.trim().isEmpty) return;
    try {
      await _profileService.publishMyProfile(
        email: _userEmail,
        displayName: _userName,
        emoji: _profileEmoji,
        avatarBase64: _avatarBase64,
        role: _userRole,
      );
    } catch (e) {
      debugPrint('Publication profil public échouée: $e');
    }
  }

  Future<void> setProfileEmoji(String emoji) async {
    _profileEmoji = emoji.trim();
    _avatarBase64 = null;
    await _persistProfileFields();
    notifyListeners();
  }

  Future<void> setProfileAvatarBytes(Uint8List bytes) async {
    // Limite ~400 Ko stockés pour éviter de saturer SharedPreferences
    var data = bytes;
    if (data.lengthInBytes > 400 * 1024) {
      // On garde quand même une version encodée tronquée n'est pas viable ;
      // on refuse silencieusement les trop gros fichiers côté UI idéalement.
      debugPrint('Avatar trop volumineux (${data.lengthInBytes} bytes), compression recommandée.');
    }
    _avatarBase64 = base64Encode(data);
    _profileEmoji = null;
    await _persistProfileFields();
    notifyListeners();
  }

  Future<void> clearProfileAvatar() async {
    _avatarBase64 = null;
    _profileEmoji = null;
    await _persistProfileFields();
    notifyListeners();
  }

  Future<void> _syncWithDjangoProfile() async {
    try {
      final token = await AuthService().getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.apiBaseUrl}/users/me/'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final profile = jsonDecode(response.body);
        _userId = profile['id'];
        _userRole = profile['role'] ?? 'STUDENT';
        _userMatricule = (profile['matricule'] ?? '').toString();
        _requiresProfileCompletion = profile['requires_email_setup'] == true;

        // Préférer le nom de profil local s'il existe
        final prefs = await SharedPreferences.getInstance();
        final localName = prefs.getString(_profileKey('display_name'));
        if (localName == null || localName.trim().isEmpty) {
          final remoteName = (profile['first_name'] ?? '').toString().trim().isNotEmpty
              ? '${profile['first_name']} ${profile['last_name'] ?? ''}'.trim()
              : (profile['username'] ?? '').toString();
          if (remoteName.isNotEmpty) _userName = remoteName;
        }

        if ((profile['email'] ?? '').toString().trim().isNotEmpty) {
          _userEmail = profile['email'].toString().trim().toLowerCase();
        }

        await prefs.setInt('user_id', _userId!);
        await prefs.setString('role', _userRole);
        await prefs.setString('username', _userName);
        await prefs.setString('email', _userEmail);
        await prefs.setBool(
          'requires_profile_completion',
          _requiresProfileCompletion,
        );
        await _persistProfileFields();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Erreur sync Django: $e');
    }
  }

  Future<bool> login(String identifier, String password) async {
    _lastError = null;
    try {
      debugPrint('Tentative de connexion Django pour: $identifier');
      final result = await AuthService().login(identifier, password);

      if (!result.success) {
        _lastError = 'Identifiants incorrects. Vérifiez votre matricule et mot de passe.';
        return false;
      }

      final user = result.user ?? {};
      _isAuthenticated = true;
      _requiresProfileCompletion = result.requiresProfileCompletion;
      _userMatricule = (user['matricule'] ?? identifier).toString();
      _userRole = (user['role'] ?? 'STUDENT').toString();
      _userId = user['id'] as int?;

      final email = (user['email'] ?? '').toString().trim().toLowerCase();
      if (email.isNotEmpty) {
        _userEmail = email;
      }

      if (_userName.isEmpty) {
        _userName = (user['username'] ?? identifier).toString();
      }

      if (_requiresProfileCompletion) {
        _pendingPassword = password;
      } else {
        _pendingPassword = null;
      }

      // Session Firebase obligatoire pour chat + notifications push.
      // 1) custom token Django (fiable après login matricule)
      // 2) fallback e-mail/mot de passe si custom token indisponible
      await _ensureFirebaseSession(password);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_authenticated', true);
      await prefs.setString('username', _userName);
      await prefs.setString('email', _userEmail);
      await prefs.setBool('requires_profile_completion', _requiresProfileCompletion);
      if (_userId != null) await prefs.setInt('user_id', _userId!);
      await prefs.setString('role', _userRole);
      await _persistProfileFields();

      try {
        await _syncWithDjangoProfile();
      } catch (e) {
        // Ne pas faire échouer la connexion si le profil distant est indisponible
        debugPrint('Sync profil post-login (non bloquant): $e');
      }

      if (!_requiresProfileCompletion) {
        await FirebaseNotificationService().initialize();
        try {
          await _publishPublicProfile();
        } catch (e) {
          debugPrint('Publish profil post-login (non bloquant): $e');
        }
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Exception dans AuthProvider.login: $e');
      _lastError = 'Échec de la connexion. Réessayez.';
      return false;
    }
  }

  Future<void> _ensureFirebaseSession(String password) async {
    try {
      final custom = await AuthService().signInFirebaseWithCustomToken();
      if (custom != null) {
        final email = (custom.user?.email ?? _userEmail).trim().toLowerCase();
        if (email.isNotEmpty) {
          _userEmail = email;
          await _loadProfileForEmail(email);
        }
        if (_userName.isEmpty) {
          _userName = custom.user?.displayName ??
              (_userEmail.isNotEmpty ? _userEmail.split('@').first : _userMatricule);
        }
        await _syncFirebaseUidToDjango(custom.user?.uid, password: password);
        return;
      }
    } catch (e) {
      debugPrint('Firebase custom token: $e');
    }

    if (_userEmail.isNotEmpty) {
      await _loginFirebaseIfPossible(_userEmail, password);
    }
  }

  Future<void> _loginFirebaseIfPossible(String email, String password) async {
    try {
      final credential = await _authService.login(email, password);
      if (credential != null) {
        await _loadProfileForEmail(email);
        if (_userName.isEmpty) {
          _userName = credential.user?.displayName ?? email.split('@').first;
        }
        await _syncFirebaseUidToDjango(credential.user?.uid, password: password);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        try {
          final credential = await _authService.register(_userName, email, password);
          await _syncFirebaseUidToDjango(credential?.user?.uid, password: password);
        } catch (regErr) {
          debugPrint('Création compte Firebase à la connexion: $regErr');
        }
      } else {
        debugPrint('Firebase login optionnel échoué: ${e.code}');
      }
    } catch (e) {
      debugPrint('Firebase login optionnel échoué: $e');
    }
  }

  Future<void> _syncFirebaseUidToDjango(String? firebaseUid, {required String password}) async {
    if (firebaseUid == null || firebaseUid.isEmpty || _userEmail.isEmpty) return;
    try {
      await http.post(
        Uri.parse('${ApiConfig.apiBaseUrl}/token/firebase-sync/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _userEmail,
          'password': password,
          'firebase_uid': firebaseUid,
        }),
      );
    } catch (e) {
      debugPrint('Sync firebase_uid Django: $e');
    }
  }

  Future<void> _syncFirebasePassword(String email, String oldPassword, String newPassword) async {
    if (email.trim().isEmpty) return;

    try {
      var fbUser = _authService.currentUser;
      if (fbUser == null || fbUser.email?.toLowerCase() != email.toLowerCase()) {
        await _authService.login(email, oldPassword);
        fbUser = _authService.currentUser;
      }
      if (fbUser != null) {
        final credential = EmailAuthProvider.credential(
          email: email.trim(),
          password: oldPassword,
        );
        await fbUser.reauthenticateWithCredential(credential);
        await _authService.updatePassword(newPassword);
        return;
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        try {
          await _authService.register(_userName, email, newPassword);
          await _syncFirebaseUidToDjango(_authService.currentUser?.uid, password: newPassword);
        } on FirebaseAuthException catch (regErr) {
          if (regErr.code == 'email-already-in-use') {
            try {
              await _authService.login(email, oldPassword);
              final fbUser = _authService.currentUser;
              if (fbUser != null) {
                final credential = EmailAuthProvider.credential(
                  email: email.trim(),
                  password: oldPassword,
                );
                await fbUser.reauthenticateWithCredential(credential);
                await _authService.updatePassword(newPassword);
              }
            } catch (syncErr) {
              debugPrint('Firebase password sync (compte existant): $syncErr');
            }
          } else {
            debugPrint('Firebase password sync register: ${regErr.code}');
          }
        }
        return;
      }
      debugPrint('Firebase password sync: ${e.code}');
    }

    try {
      await _authService.login(email, newPassword);
    } catch (_) {
      try {
        await _authService.register(_userName, email, newPassword);
        await _syncFirebaseUidToDjango(_authService.currentUser?.uid, password: newPassword);
      } on FirebaseAuthException catch (regErr) {
        if (regErr.code != 'email-already-in-use') {
          debugPrint('Firebase password sync fallback: ${regErr.code}');
        }
      } catch (e) {
        debugPrint('Firebase password sync fallback: $e');
      }
    }
  }

  Future<bool> completeProfile(String email) async {
    _lastError = null;
    final normalized = email.trim().toLowerCase();
    if (!normalized.endsWith('@gmail.com')) {
      _lastError = 'Utilisez une adresse @gmail.com.';
      return false;
    }

    final profile = await AuthService().completeProfile(normalized);
    if (profile == null) {
      _lastError = 'Cette adresse Gmail est peut-être déjà utilisée ou invalide.';
      return false;
    }

    _userEmail = normalized;
    _requiresProfileCompletion = false;
    _userName = (profile['first_name'] ?? '').toString().trim().isNotEmpty
        ? '${profile['first_name']} ${profile['last_name'] ?? ''}'.trim()
        : (profile['username'] ?? _userName).toString();

    final password = _pendingPassword;
    _pendingPassword = null;

    if (password != null && password.isNotEmpty) {
      try {
        await _authService.register(_userName, normalized, password);
      } catch (e) {
        debugPrint('Création Firebase après profil: $e — tentative login');
        await _loginFirebaseIfPossible(normalized, password);
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('email', _userEmail);
    await prefs.setBool('requires_profile_completion', false);
    await _persistProfileFields();
    await _syncWithDjangoProfile();
    FirebaseNotificationService().initialize();
    await _publishPublicProfile();
    notifyListeners();
    return true;
  }

  String? _lastError;
  String? get lastError => _lastError;

  void clearLastError() => _lastError = null;

  String _mapFirebaseError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'Cet e-mail est déjà utilisé. Connectez-vous ou utilisez un autre e-mail.';
        case 'invalid-email':
          return 'Adresse e-mail invalide.';
        case 'weak-password':
          return 'Mot de passe trop faible (minimum 6 caractères).';
        case 'operation-not-allowed':
          return 'Inscription e-mail/mot de passe non activée dans Firebase.';
        case 'network-request-failed':
          return 'Erreur réseau Firebase. Vérifiez votre connexion Internet.';
        case 'too-many-requests':
          return 'Trop de tentatives. Réessayez dans quelques minutes.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Mot de passe actuel incorrect.';
        default:
          return e.message ?? 'Erreur Firebase (${e.code}).';
      }
    }
    final text = e.toString();
    if (text.contains('TimeoutException')) {
      return 'Délai dépassé. Réessayez (le serveur Django est peut-être occupé).';
    }
    return 'Échec de l\'inscription. Vérifiez vos données et votre connexion.';
  }

  Future<bool> register(String name, String email, String password) async {
    _lastError = 'L\'inscription libre est désactivée. Utilisez votre matricule.';
    return false;
  }

  Future<void> logout() async {
    await _authService.logout();
    _isAuthenticated = false;

    final prefs = await SharedPreferences.getInstance();
    // Ne pas effacer le profil (avatar/emoji/nom) — seulement la session
    await prefs.setBool('is_authenticated', false);
    await prefs.remove('django_access');
    await prefs.remove('django_refresh');
    await prefs.remove('firebase_token');
    await prefs.remove('requires_profile_completion');
    await AuthService().logout();

    // Garder email en mémoire locale pour debug, mais vider l'état runtime
    _userId = null;
    _pendingPassword = null;
    _requiresProfileCompletion = false;
    // Conservés en prefs par e-mail ; on vide juste l'affichage courant
    _profileEmoji = null;
    _avatarBase64 = null;
    _userName = '';
    _userEmail = '';
    _userRole = 'STUDENT';

    _dbHelper.clearAll().catchError((e) => debugPrint('SQLite Clear failed: $e'));

    notifyListeners();
  }

  Future<bool> updateProfile(String name, String email) async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        if (name != _userName) await user.updateDisplayName(name);
        if (email != _userEmail && email.trim().isNotEmpty) {
          await user.verifyBeforeUpdateEmail(email);
        }
      }

      _userName = name.trim();
      if (email.trim().isNotEmpty) {
        _userEmail = email.trim().toLowerCase();
      }

      await _persistProfileFields();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Erreur updateProfile: $e');
      return false;
    }
  }

  Future<bool> updatePassword(String oldPassword, String newPassword) async {
    _lastError = null;
    try {
      final djangoError = await AuthService().changePassword(oldPassword, newPassword);
      if (djangoError != null) {
        _lastError = djangoError;
        return false;
      }

      if (_userEmail.trim().isNotEmpty) {
        try {
          await _syncFirebasePassword(_userEmail, oldPassword, newPassword);
        } catch (e) {
          debugPrint('Sync Firebase mot de passe (non bloquant): $e');
        }
      }

      _pendingPassword = null;
      return true;
    } catch (e) {
      debugPrint('Erreur updatePassword: $e');
      _lastError = 'Impossible de mettre à jour le mot de passe.';
      return false;
    }
  }
}
