import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../screens/quiz_screen.dart';
import '../screens/login_screen.dart';

class LinkService {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  final SyncService _syncService = SyncService();

  void initDeepLinks(BuildContext context) {
    _appLinks = AppLinks();

    // Handle links when app is already open
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleLink(context, uri);
    });

    // Handle link when app is launched from terminated state
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleLink(context, uri);
      }
    });
  }

  void dispose() {
    _linkSubscription?.cancel();
  }

  Future<void> _handleLink(BuildContext context, Uri uri) async {
    debugPrint('Handling deep link: $uri');
    
    // Check if it's a quiz link: edurdc://quiz/<uuid>
    if (uri.scheme == 'edurdc' && uri.host == 'quiz') {
      final code = uri.pathSegments.isNotEmpty ? uri.pathSegments[0] : null;
      if (code != null) {
        _processQuizLink(context, code);
      }
    }
  }

  Future<void> _processQuizLink(BuildContext context, String code) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.isAuthenticated) {
      // Not authenticated, redirect to login
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez vous connecter pour accéder au quiz.'))
      );
      Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }

    // Authenticated, fetch quiz and start
    _fetchAndStartQuiz(context, code);
  }

  Future<void> _fetchAndStartQuiz(BuildContext context, String code) async {
    // Show loader
    showDialog(context: context, builder: (_) => const Center(child: CircularProgressIndicator()));
    
    try {
      final token = await AuthService().getToken();
      final response = await http.get(
        Uri.parse('${_syncService.apiBaseUrl}/quizzes/?id_code=$code'),
        headers: {'Authorization': 'Bearer $token'},
      );
      
      if (context.mounted) Navigator.pop(context); // Close loader

      if (response.statusCode == 200) {
        final List<dynamic> results = jsonDecode(response.body);
        if (results.isNotEmpty) {
          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => QuizScreen(quiz: results[0])),
            );
          }
        } else {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quiz non trouvé ou non publié.')));
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur de connexion.')));
      }
    }
  }
}
