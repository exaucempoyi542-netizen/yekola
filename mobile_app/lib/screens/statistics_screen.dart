import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../services/sync_service.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _stats;
  String? _error;
  final SyncService _syncService = SyncService();

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    try {
      final stats = await _syncService.fetchStudentStats();
      if (stats != null) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
      } else {
        // Tentative de chargement local
        final localStats = await _syncService.loadLocalStats();
        if (localStats != null) {
          setState(() {
            _stats = localStats;
            _error = "Connectez-vous à Internet pour synchroniser vos derniers résultats.";
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = 'Impossible de charger vos statistiques (Hors-ligne).';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      // Tentative de chargement local sur erreur réseau
      final localStats = await _syncService.loadLocalStats();
      setState(() {
        if (localStats != null) {
          _stats = localStats;
          _error = "Affichage hors-ligne. Erreur de connexion au serveur.";
        } else {
          _error = 'Erreur de connexion et aucun cache local trouvé.';
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Mes Statistiques',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF152A45),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() { _isLoading = true; _error = null; });
                          _fetchStats();
                        },
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchStats,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mes Statistiques',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.titleLarge?.color ?? const Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Suivez votre progression',
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 32),
                        _buildStatRow(
                          icon: Icons.book_rounded,
                          color: const Color(0xFF152A45),
                          title: 'Cours inscrits',
                          value: _stats?['total_courses_enrolled']?.toString() ?? '0',
                        ),
                        _buildStatRow(
                          icon: Icons.check_circle_rounded,
                          color: Colors.green,
                          title: 'Cours terminés',
                          value: _stats?['completed_courses_count']?.toString() ?? '0',
                        ),
                        _buildStatRow(
                          icon: Icons.trending_up_rounded,
                          color: Colors.teal,
                          title: 'En cours',
                          value: _stats?['in_progress_courses_count']?.toString() ?? '0',
                        ),
                        _buildStatRow(
                          icon: Icons.quiz_rounded,
                          color: Colors.orange,
                          title: 'Quiz tentés',
                          value: _stats?['total_quizzes_attempted']?.toString() ?? '0',
                        ),
                        _buildStatRow(
                          icon: Icons.star_rounded,
                          color: Colors.amber,
                          title: 'Score moyen quiz',
                          value: (_stats?['average_quiz_score'] != null)
                              ? '${(_stats!['average_quiz_score'] as num).toStringAsFixed(1)}%'
                              : 'N/A',
                        ),
                        _buildStatRow(
                          icon: Icons.show_chart_rounded,
                          color: Colors.purple,
                          title: 'Progression moy.',
                          value: (_stats?['average_course_progress'] != null)
                              ? '${(_stats!['average_course_progress'] as num).toStringAsFixed(1)}%'
                              : '0%',
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(theme.brightness == Brightness.dark ? 0.0 : 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyMedium?.color ?? const Color(0xFF1A1A1A),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
