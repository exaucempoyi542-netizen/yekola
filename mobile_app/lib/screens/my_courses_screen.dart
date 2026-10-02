import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/sync_service.dart';
import 'course_details_screen.dart';
import 'lesson_player_screen.dart';
import 'login_screen.dart';

class MyCoursesScreen extends StatefulWidget {
  const MyCoursesScreen({super.key});

  @override
  State<MyCoursesScreen> createState() => _MyCoursesScreenState();
}

class _MyCoursesScreenState extends State<MyCoursesScreen> {
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _enrolledCourses = [];
  bool _isLoading = true;

  static const Color _primary = Color(0xFF152A45);

  @override
  void initState() {
    super.initState();
    _loadEnrolledCourses();
  }

  Future<void> _loadEnrolledCourses() async {
    setState(() => _isLoading = true);
    try {
      final courses = await _syncService.getCourses(forceRefresh: true);
      setState(() {
        _enrolledCourses =
            courses.where((c) => c['is_enrolled'] == true).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  /// Calcule l'index de la dernière leçon vue basé sur la progression
  int _getResumeIndex(Map<String, dynamic> course) {
    final lessons = course['lessons'] as List? ?? [];
    if (lessons.isEmpty) return 0;
    final progress = (course['progress'] ?? 0.0) as num;
    final total = lessons.length;
    final doneCount = ((progress / 100.0) * total).floor();
    return doneCount.clamp(0, total - 1);
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated =
        Provider.of<AuthProvider>(context).isAuthenticated;

    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.cardColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Mes Cours',
          style: TextStyle(
            color: theme.textTheme.titleLarge?.color ?? const Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
            onPressed: _loadEnrolledCourses,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !isAuthenticated
          ? _buildNotLoggedIn(context)
          : _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: _primary))
              : _enrolledCourses.isEmpty
                  ? _buildEmpty()
                  : _buildCourseList(),
    );
  }

  Widget _buildNotLoggedIn(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline_rounded,
                  color: _primary, size: 42),
            ),
            const SizedBox(height: 24),
            Text(
              'Connectez-vous pour voir vos cours',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: theme.textTheme.titleMedium?.color ?? const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 10),
            const Text(
              'Accédez à tous vos cours inscrits et continuez votre apprentissage.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen())),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('SE CONNECTER',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return RefreshIndicator(
      onRefresh: _loadEnrolledCourses,
      color: _primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          Center(
            child: Column(
              children: [
                Icon(Icons.school_outlined, size: 80, color: Colors.grey[300]),
                const SizedBox(height: 20),
                const Text(
                  'Vous n\'êtes inscrit à aucun cours',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Explorez le catalogue et inscrivez-vous à un cours.',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseList() {
    return RefreshIndicator(
      onRefresh: _loadEnrolledCourses,
      color: _primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _enrolledCourses.length,
        itemBuilder: (context, index) {
          return _buildCourseCard(_enrolledCourses[index]);
        },
      ),
    );
  }

  Widget _buildCourseCard(Map<String, dynamic> course) {
    final lessons = course['lessons'] as List? ?? [];
    final progress = (course['progress'] ?? 0.0) as num;
    final progressDouble = progress.toDouble();
    final resumeIndex = _getResumeIndex(course);

    final String baseUrl = 'http://localhost:8000';
    String? thumbnailUrl = course['thumbnail'];
    if (thumbnailUrl != null && !thumbnailUrl.startsWith('http')) {
      thumbnailUrl = '$baseUrl$thumbnailUrl';
    }

    // Statut progression
    String progressLabel;
    Color progressColor;
    if (progressDouble == 0) {
      progressLabel = 'Pas encore commencé';
      progressColor = Colors.grey;
    } else if (progressDouble >= 100) {
      progressLabel = 'Terminé ✓';
      progressColor = Colors.green;
    } else {
      progressLabel =
          '${progressDouble.toStringAsFixed(0)}% complété';
      progressColor = _primary;
    }

    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            Stack(
              children: [
                SizedBox(
                  height: 150,
                  width: double.infinity,
                  child: thumbnailUrl != null
                      ? Image.network(thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _buildPlaceholder())
                      : _buildPlaceholder(),
                ),
                // Overlay gradient
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.5),
                        ],
                      ),
                    ),
                  ),
                ),
                // Badge progression
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: progressDouble >= 100
                          ? Colors.green
                          : _primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      progressDouble >= 100
                          ? '✓ Terminé'
                          : '${progressDouble.toStringAsFixed(0)}%',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                // Leçons count
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Row(
                    children: [
                      const Icon(Icons.play_lesson_rounded,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${lessons.length} leçon${lessons.length > 1 ? 's' : ''}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Barre de progression
            LinearProgressIndicator(
              value: (progressDouble / 100).clamp(0.0, 1.0),
              backgroundColor: theme.brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[200],
              color: progressDouble >= 100 ? Colors.green : _primary,
              minHeight: 4,
            ),

            // Infos cours
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course['title'] ?? '',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: theme.textTheme.titleMedium?.color ?? const Color(0xFF0F172A),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          course['teacher_name'] ?? 'Enseignant Yekola',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        progressDouble >= 100
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_checked_rounded,
                        size: 14,
                        color: progressColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        progressLabel,
                        style: TextStyle(
                            color: progressColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Boutons d'action
                  Row(
                    children: [
                      // Bouton Continuer / Démarrer
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: lessons.isNotEmpty
                              ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LessonPlayerScreen(
                                      lessons: List<Map<String, dynamic>>
                                          .from(lessons),
                                      quizzes: List<Map<String, dynamic>>
                                          .from(course['quizzes'] ?? []),
                                      initialIndex: resumeIndex,
                                    ),
                                  ))
                              : null,
                          icon: Icon(
                            progressDouble == 0
                                ? Icons.play_arrow_rounded
                                : progressDouble >= 100
                                    ? Icons.replay_rounded
                                    : Icons.play_circle_outline_rounded,
                            size: 18,
                          ),
                          label: Text(
                            progressDouble == 0
                                ? 'Démarrer'
                                : progressDouble >= 100
                                    ? 'Revoir'
                                    : 'Continuer',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Bouton Détails
                      OutlinedButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                CourseDetailsScreen(course: course),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primary,
                          side: const BorderSide(color: _primary),
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Détails',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF152A45), Color(0xFF1E3A5F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.auto_stories_rounded,
            size: 48, color: Colors.white30),
      ),
    );
  }
}
