import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'menu_screen.dart';
import 'catalogue_screen.dart';
import 'home_screen.dart';
import 'chat_list_screen.dart';
import 'quiz_screen.dart';

import '../services/link_service.dart';
import '../l10n/app_localizations.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  List<Map<String, dynamic>> _courses = [];
  bool _isSyncing = false;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final LinkService _linkService = LinkService();
  bool _shouldFocusCatalogueSearch = false;

  @override
  void initState() {
    super.initState();
    _syncWithBackend();
    _linkService.initDeepLinks(context);
  }

  @override
  void dispose() {
    _linkService.dispose();
    super.dispose();
  }

  Future<void> _loadLocalContent({bool forceRefresh = false}) async {
    try {
      final courses = await _syncService.getCourses(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _courses = courses;
        });
      }
    } catch (e) {
      debugPrint("Erreur chargement accueil: $e");
    }
  }

  Future<void> _syncWithBackend({bool forceRefresh = false}) async {
    // Afficher le cache immédiatement (stale-while-revalidate)
    if (_courses.isEmpty) {
      await _loadLocalContent(forceRefresh: false);
    }
    if (!mounted) return;
    setState(() => _isSyncing = true);
    try {
      // Un seul appel réseau : pullCourses met à jour le cache ; pas de 2e GET
      await _syncService.pullCourses(forceRefresh: forceRefresh);
      await _loadLocalContent(forceRefresh: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur de connexion: $e")),
        );
      }
    }
    if (mounted) setState(() => _isSyncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isAuthenticated = authProvider.isAuthenticated;
    final userEmail = authProvider.userEmail;

    Widget bodyView;
    if (_currentIndex == 1) {
      bodyView = CatalogueScreen(autofocusSearch: _shouldFocusCatalogueSearch);
      if (_shouldFocusCatalogueSearch) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _shouldFocusCatalogueSearch = false;
          });
        });
      }
    } else if (_currentIndex == 2) {
      bodyView = const MenuScreen();
    } else {
      bodyView = HomeScreen(
        courses: _courses,
        isSyncing: _isSyncing,
        onRefresh: () => _syncWithBackend(forceRefresh: true),
        onSearchTap: () {
          setState(() {
            _currentIndex = 1;
            _shouldFocusCatalogueSearch = true;
          });
        },
      );
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true, 
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF152A45), // Matched with primary theme
        elevation: 4,
        child: const Icon(Icons.forum_rounded, color: Colors.white, size: 26),
        onPressed: () {
          final role = (authProvider.userRole).toUpperCase();
          if (!isAuthenticated) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
          } else if (role != 'TEACHER' && role != 'STUDENT') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Le chat est réservé aux enseignants et étudiants.')),
            );
          } else {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatListScreen()));
          }
        },
      ),
      body: bodyView,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          selectedItemColor: const Color(0xFF152A45),
          unselectedItemColor: Colors.grey[400],
          backgroundColor: theme.cardColor,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          elevation: 0,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.home_outlined), 
              activeIcon: const Icon(Icons.home_rounded), 
              label: l10n.translate('home')
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.explore_outlined), 
              activeIcon: const Icon(Icons.explore_rounded), 
              label: l10n.translate('catalogue')
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.grid_view_rounded), 
              activeIcon: const Icon(Icons.grid_view_rounded), 
              label: l10n.translate('menu')
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildFeed(bool isAuthenticated) {
    if (_courses.isEmpty && !_isSyncing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Le contenu est vide', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    
    return ListView.builder(
      itemCount: _courses.length,
      itemBuilder: (context, index) {
        final course = _courses[index];
        return _buildPostCard(
          authorName: course['teacher_name'] ?? "Yekola",
          timeAgo: "Nouveau",
          content: course['description'] ?? "",
          imageUrl: "https://picsum.photos/seed/${course['id'] + 42}/600/350", 
          likes: 0,
          comments: 0,
          isAuthenticated: isAuthenticated,
        );
      },
    );
  }

  Widget _buildPostCard({
    required String authorName,
    required String timeAgo,
    required String content,
    required String imageUrl,
    required int likes,
    required int comments,
    required bool isAuthenticated,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF152A45).withValues(alpha: 0.1),
                  radius: 20,
                  child: const Icon(Icons.school, color: Color(0xFF152A45)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(authorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(timeAgo, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          const SizedBox(width: 4),
                          Icon(Icons.public, size: 12, color: Colors.grey[600]),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.more_horiz), onPressed: () {}),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(content, style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(height: 12),
          Image.network(
            imageUrl,
            width: double.infinity,
            height: 250,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: double.infinity,
              height: 250,
              color: Colors.grey[200],
              child: const Center(child: Icon(Icons.auto_awesome_mosaic, size: 64, color: Colors.grey)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Color(0xFF152A45), shape: BoxShape.circle),
                  child: const Icon(Icons.thumb_up, color: Colors.white, size: 12),
                ),
                const SizedBox(width: 6),
                Text('\$likes', style: TextStyle(color: Colors.grey[700])),
                const Spacer(),
                Text('\$comments commentaires', style: TextStyle(color: Colors.grey[700])),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(Icons.thumb_up_alt_outlined, 'J\'aime', isAuthenticated),
                _buildActionButton(Icons.comment_outlined, 'Commenter', isAuthenticated),
                _buildActionButton(
                  isAuthenticated ? Icons.play_circle_outline : Icons.menu_book, 
                  isAuthenticated ? 'Ouvrir' : 'S\'inscrire', 
                  isAuthenticated, 
                  isPrimary: true
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, bool isAuthenticated, {bool isPrimary = false}) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () {
          if (!isAuthenticated) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Veuillez vous identifier')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Action "\$label" exécutée avec succès.')),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isPrimary ? const Color(0xFF152A45) : Colors.grey[700], size: 20),
              const SizedBox(width: 6),
              Text(
                label, 
                style: TextStyle(
                  color: isPrimary ? const Color(0xFF152A45) : Colors.grey[700],
                  fontWeight: isPrimary ? FontWeight.bold : FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}
