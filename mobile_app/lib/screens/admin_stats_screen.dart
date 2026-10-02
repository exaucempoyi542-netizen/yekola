import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class AdminStatsScreen extends StatefulWidget {
  const AdminStatsScreen({super.key});

  @override
  State<AdminStatsScreen> createState() => _AdminStatsScreenState();
}

class _AdminStatsScreenState extends State<AdminStatsScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  Map<String, dynamic>? _stats;
  String? _error;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fetchStats();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchStats() async {
    try {
      final token = await AuthService().getToken();
      final response = await http.get(
        Uri.parse('http://localhost:8000/api/admin/stats/'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        setState(() {
          _stats = jsonDecode(response.body);
          _isLoading = false;
        });
        _animationController.forward();
      } else {
        setState(() {
          _error = 'Erreur: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Erreur de connexion serveur.';
        _isLoading = false;
      });
    }
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required int delay,
  }) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(delay * 0.1, delay * 0.1 + 0.3, curve: Curves.easeOut),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  color.withOpacity(0.05),
                ],
              ),
              border: Border.all(
                color: color.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 32, color: color),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActivityCard() {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: const Interval(0.3, 0.6, curve: Curves.easeOut),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.15),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  Colors.green.withOpacity(0.05),
                ],
              ),
              border: Border.all(
                color: Colors.green.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Activité Récente',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFFE0E0E0), thickness: 1),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.assignment_turned_in,
                        color: Colors.green,
                        size: 24,
                      ),
                    ),
                    title: const Text(
                      'Quiz Actifs',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    subtitle: Text(
                      'Total des évaluations actives',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _stats!['published_quizzes'].toString(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tableau de Bord',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Aperçu complet de votre plateforme',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Stats Grid
          LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount = constraints.maxWidth > 1200
                  ? 4
                  : (constraints.maxWidth > 800 ? 2 : 1);
              return GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 24,
                mainAxisSpacing: 24,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.4,
                children: [
                  _buildStatCard(
                    title: 'Total Utilisateurs',
                    value: _stats!['total_users'].toString(),
                    icon: Icons.people_outline,
                    color: Colors.blue,
                    delay: 1,
                  ),
                  _buildStatCard(
                    title: 'Enseignants',
                    value: _stats!['total_teachers'].toString(),
                    icon: Icons.school_outlined,
                    color: Colors.orange,
                    delay: 2,
                  ),
                  _buildStatCard(
                    title: 'Étudiants',
                    value: _stats!['total_students'].toString(),
                    icon: Icons.face_outlined,
                    color: Colors.green,
                    delay: 3,
                  ),
                  _buildStatCard(
                    title: 'Cours Publiés',
                    value: _stats!['total_courses'].toString(),
                    icon: Icons.library_books_outlined,
                    color: Colors.purple,
                    delay: 4,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),

          // Activity Card
          _buildActivityCard(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
