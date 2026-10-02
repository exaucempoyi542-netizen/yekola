import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import 'lesson_player_screen.dart';

class StudentGradesScreen extends StatefulWidget {
  const StudentGradesScreen({super.key});

  @override
  State<StudentGradesScreen> createState() => _StudentGradesScreenState();
}

class _StudentGradesScreenState extends State<StudentGradesScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  
  List<Map<String, dynamic>> _downloadedCourses = [];
  bool _isLoading = true;

  static const Color _primary = Color(0xFF152A45);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    // Charger uniquement les cours téléchargés (hors-ligne)
    final downloaded = await _syncService.getDownloadedCourses();
    
    if (mounted) {
      setState(() {
        _downloadedCourses = downloaded;
        _isLoading = false;
      });
    }
  }

  // Supprime un cours téléchargé
  Future<void> _deleteDownload(int courseId) async {
    await _syncService.deleteCourseDownload(courseId);
    final downloaded = await _syncService.getDownloadedCourses();
    if (mounted) {
      setState(() {
        _downloadedCourses = downloaded;
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Téléchargement supprimé localement.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      appBar: AppBar(
        title: const Text('Cours hors ligne', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _buildDownloadedCoursesTab(),
    );
  }



  Widget _buildDownloadedCoursesTab() {
    if (_downloadedCourses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_for_offline_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text("Aucun cours téléchargé", style: TextStyle(fontWeight: FontWeight.w600)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40, vertical: 8),
              child: Text(
                "Vous pouvez télécharger vos cours inscrits pour les lire hors-ligne en touchant le bouton de téléchargement de l'écran détail.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _downloadedCourses.length,
      itemBuilder: (context, index) {
        final course = _downloadedCourses[index];
        final lessons = course['lessons'] as List? ?? [];

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ExpansionTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_download_rounded, color: _primary),
            ),
            title: Text(
              course['title'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            subtitle: Text(
              "${course['teacher_name'] ?? 'Enseignant'} • ${lessons.length} leçons",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _deleteDownload(course['id']),
            ),
            children: [
              if (lessons.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Aucune leçon téléchargée pour ce cours."),
                )
              else
                ...lessons.map((lesson) {
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.play_circle_fill, color: _primary, size: 20),
                    title: Text(
                      lesson['title'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(lesson['content_type'] ?? 'Texte'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LessonPlayerScreen(
                            lessons: List<Map<String, dynamic>>.from(lessons),
                            quizzes: const [],
                            initialIndex: lessons.indexOf(lesson),
                          ),
                        ),
                      );
                    },
                  );
                }).toList(),
            ],
          ),
        );
      },
    );
  }


}
