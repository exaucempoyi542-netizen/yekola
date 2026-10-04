import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
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

class _MyCoursesScreenState extends State<MyCoursesScreen>
    with SingleTickerProviderStateMixin {
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _enrolledCourses = [];
  List<Map<String, dynamic>> _downloadedCourses = [];
  bool _isLoading = true;
  late TabController _tabs;

  static const Color _primary = Color(0xFF152A45);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _syncService.getCourses(forceRefresh: true),
        _syncService.getDownloadedCourses(),
      ]);
      final courses = results[0];
      final downloaded = results[1];
      if (!mounted) return;
      setState(() {
        _enrolledCourses =
            courses.where((c) => c['is_enrolled'] == true).toList();
        _downloadedCourses = downloaded;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _getResumeIndex(Map<String, dynamic> course) {
    final lessons = course['lessons'] as List? ?? [];
    if (lessons.isEmpty) return 0;
    final progress = (course['progress'] ?? 0.0) as num;
    final total = lessons.length;
    final doneCount = ((progress / 100.0) * total).floor();
    return doneCount.clamp(0, total - 1);
  }

  /// Charge le détail (leçons) puis ouvre le lecteur NATIF dans l'app.
  Future<void> _openInAppPlayer(
    Map<String, dynamic> course, {
    bool offline = false,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    try {
      Map<String, dynamic> full = Map<String, dynamic>.from(course);
      List lessons = full['lessons'] as List? ?? [];

      if (!offline) {
        final detail =
            await _syncService.getCourseById('${course['id']}');
        if (detail != null) {
          full = detail;
          lessons = full['lessons'] as List? ?? [];
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // ferme le loader

      if (lessons.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Aucune leçon disponible pour ce cours. Vérifiez qu’il est publié avec du contenu.',
            ),
          ),
        );
        return;
      }

      final lessonMaps = List<Map<String, dynamic>>.from(
        lessons.map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final quizzes = List<Map<String, dynamic>>.from(
        (full['quizzes'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LessonPlayerScreen(
            lessons: lessonMaps,
            quizzes: quizzes,
            initialIndex: _getResumeIndex(full),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d’ouvrir le cours : $e')),
      );
    }
  }

  Future<void> _openDetails(Map<String, dynamic> course) async {
    // Toujours le détail complet pour consulter dans l'app
    final detail = await _syncService.getCourseById('${course['id']}');
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CourseDetailsScreen(course: detail ?? course),
      ),
    );
  }

  Future<void> _deleteDownload(dynamic courseId) async {
    final id = courseId is int
        ? courseId
        : int.tryParse('$courseId') ?? 0;
    await _syncService.deleteCourseDownload(id);
    await _loadAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Téléchargement supprimé.')),
    );
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
            color:
                theme.textTheme.titleLarge?.color ?? const Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
            onPressed: _loadAll,
          ),
          const SizedBox(width: 8),
        ],
        bottom: isAuthenticated
            ? TabBar(
                controller: _tabs,
                labelColor: _primary,
                unselectedLabelColor: Colors.grey,
                indicatorColor: _primary,
                tabs: [
                  Tab(
                    text:
                        'En ligne (${_enrolledCourses.length})',
                  ),
                  Tab(
                    text:
                        'Hors ligne (${_downloadedCourses.length})',
                  ),
                ],
              )
            : null,
      ),
      body: !isAuthenticated
          ? _buildNotLoggedIn(context)
          : _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: _primary))
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _enrolledCourses.isEmpty
                        ? _buildEmpty(
                            'Aucun cours inscrit',
                            'Inscrivez-vous à un cours publié, puis ouvrez-le ici pour consulter le contenu dans l’application.',
                          )
                        : _buildOnlineList(),
                    _downloadedCourses.isEmpty
                        ? _buildEmpty(
                            'Aucun cours hors ligne',
                            'Sur la fiche d’un cours, appuyez sur Télécharger. Ensuite consultez les leçons ici, dans l’app.',
                          )
                        : _buildOfflineList(),
                  ],
                ),
    );
  }

  Widget _buildNotLoggedIn(BuildContext context) {
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
            const Text(
              'Connectez-vous pour voir vos cours',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
              style: ElevatedButton.styleFrom(backgroundColor: _primary),
              child: const Text('Se connecter'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_rounded, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineList() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: _primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _enrolledCourses.length,
        itemBuilder: (context, index) =>
            _buildCourseCard(_enrolledCourses[index], offline: false),
      ),
    );
  }

  Widget _buildOfflineList() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: _primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _downloadedCourses.length,
        itemBuilder: (context, index) =>
            _buildCourseCard(_downloadedCourses[index], offline: true),
      ),
    );
  }

  Widget _buildCourseCard(Map<String, dynamic> course, {required bool offline}) {
    final lessons = course['lessons'] as List? ?? [];
    final lessonsCount = lessons.isNotEmpty
        ? lessons.length
        : (course['lessons_count'] as num?)?.toInt() ?? 0;
    final progress = (course['progress'] ?? 0.0) as num;
    final progressDouble = progress.toDouble();

    String? thumbnailUrl = course['thumbnail']?.toString();
    if (thumbnailUrl != null &&
        thumbnailUrl.isNotEmpty &&
        !thumbnailUrl.startsWith('http')) {
      thumbnailUrl = ApiConfig.resolveMediaUrl(thumbnailUrl);
    }

    String progressLabel;
    Color progressColor;
    if (offline) {
      progressLabel = 'Disponible hors ligne';
      progressColor = Colors.green[700]!;
    } else if (progressDouble == 0) {
      progressLabel = 'Pas encore commencé';
      progressColor = Colors.grey;
    } else if (progressDouble >= 100) {
      progressLabel = 'Terminé ✓';
      progressColor = Colors.green;
    } else {
      progressLabel = '${progressDouble.toStringAsFixed(0)}% complété';
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
            Stack(
              children: [
                SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: thumbnailUrl != null && thumbnailUrl.isNotEmpty
                      ? Image.network(
                          thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildPlaceholder(),
                        )
                      : _buildPlaceholder(),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.55),
                        ],
                      ),
                    ),
                  ),
                ),
                if (offline)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.green[700],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Hors ligne',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Row(
                    children: [
                      const Icon(Icons.play_lesson_rounded,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '$lessonsCount leçon${lessonsCount > 1 ? 's' : ''}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!offline)
              LinearProgressIndicator(
                value: (progressDouble / 100).clamp(0.0, 1.0),
                backgroundColor: theme.brightness == Brightness.dark
                    ? Colors.grey[800]
                    : Colors.grey[200],
                color: progressDouble >= 100 ? Colors.green : _primary,
                minHeight: 4,
              ),
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
                      color: theme.textTheme.titleMedium?.color ??
                          const Color(0xFF0F172A),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    progressLabel,
                    style: TextStyle(
                      color: progressColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _openInAppPlayer(
                            course,
                            offline: offline,
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: Text(
                            offline ? 'Consulter' : 'Lire dans l’app',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (offline)
                        IconButton(
                          onPressed: () => _deleteDownload(course['id']),
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                        )
                      else
                        OutlinedButton(
                          onPressed: () => _openDetails(course),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _primary,
                            side: const BorderSide(color: _primary),
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Détails',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
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
