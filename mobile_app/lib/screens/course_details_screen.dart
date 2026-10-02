import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import 'lesson_player_screen.dart';
import 'chat_detail_screen.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_chat_service.dart';
import 'quiz_screen.dart';
import 'assignment_screen.dart';

class CourseDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> course;
  final String? initialLessonId;
  const CourseDetailsScreen({
    super.key,
    required this.course,
    this.initialLessonId,
  });

  @override
  State<CourseDetailsScreen> createState() => _CourseDetailsScreenState();
}

class _CourseDetailsScreenState extends State<CourseDetailsScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final FirebaseChatService _chatService = FirebaseChatService();
  List<Map<String, dynamic>> _lessons = [];
  List<Map<String, dynamic>> _quizzes = [];
  List<Map<String, dynamic>> _unifiedContent = [];
  bool _isLoading = true;
  bool _isEnrolled = false;
  bool _isDownloading = false;
  bool _isDownloaded = false;
  Map<String, dynamic>? _activeLive;
  late TabController _tabController;

  static const Color _primary = Color(0xFF152A45);
  static const Color _dark = Color(0xFF0A0F1E);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _isEnrolled = widget.course['is_enrolled'] ?? false;
    _loadLessons();
    _refreshCourseData();
    _checkDownloadStatus();
  }

  bool get _isLocked => widget.course['is_locked'] == true || widget.course['is_locked'] == 1;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshCourseData() async {
    final courses = await _syncService.getCourses(forceRefresh: true);
    final updated = courses.firstWhere(
        (c) => c['id'] == widget.course['id'],
        orElse: () => {});
    if (updated.isNotEmpty && mounted) {
      setState(() {
        if (updated['lessons'] != null)
          _lessons = List<Map<String, dynamic>>.from(updated['lessons']);
        if (updated['quizzes'] != null)
          _quizzes = List<Map<String, dynamic>>.from(updated['quizzes']);
        _buildUnifiedContent();
      });
    }
  }

  Future<void> _checkDownloadStatus() async {
    try {
      final db = _dbHelper;
      final downloaded = await db.isCourseDownloaded(widget.course['id']);
      if (mounted) setState(() => _isDownloaded = downloaded);
    } catch (_) {}
  }

  Future<void> _downloadCourse() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    
    // Fusionner les données du cours avec le contenu unifié mis à jour (Leçons + Quiz)
    final courseDataForOffline = Map<String, dynamic>.from(widget.course);
    courseDataForOffline['lessons'] = _unifiedContent;

    final ok = await _syncService.downloadCourse(courseDataForOffline);
    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      _isDownloaded = ok;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Cours téléchargé ! Accessible dans "Mes Notes".'
            : 'Échec du téléchargement. Vérifiez votre connexion.'),
        backgroundColor: ok ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _toggleEnroll() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connectez-vous pour suivre cette formation.')));
      Navigator.pushNamed(context, '/login');
      return;
    }
    final orig = _isEnrolled;
    setState(() => _isEnrolled = !_isEnrolled);

    final result = await _syncService.toggleEnrollWithDetails(widget.course['id']);
    
    if (result == null && mounted) {
      // Annuler le changement optimiste
      setState(() => _isEnrolled = orig);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur réseau. Vérifiez votre connexion internet.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    if (result != null && mounted) {
      final statusCode = result['statusCode'] as int;
      final body = result['body'] as Map<String, dynamic>? ?? {};

      if (statusCode == 200 || statusCode == 201) {
        // Succès : on s'assure que l'état est cohérent avec la réponse serveur
        final isNowEnrolled = statusCode == 201 || body['status'] == 'followed';
        setState(() => _isEnrolled = isNowEnrolled);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isNowEnrolled
                ? '✅ Inscription confirmée !'
                : 'Désabonnement effectué.'),
            backgroundColor: isNowEnrolled ? Colors.green : Colors.grey[700],
          ),
        );
      } else {
        // Erreur serveur : remettre l'état original et afficher le vrai message
        setState(() => _isEnrolled = orig);
        final errorMsg = body['error'] ?? body['detail'] ?? 'Erreur $statusCode';
        debugPrint('[Enrollment] Server error $statusCode: $body');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $errorMsg'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _loadLessons() async {
    try {
      if (widget.course['lessons'] != null) {
        setState(() {
          _lessons = List<Map<String, dynamic>>.from(widget.course['lessons']);
          _quizzes = List<Map<String, dynamic>>.from(widget.course['quizzes'] ?? []);
          _buildUnifiedContent();
          _isLoading = false;
        });
        _openInitialLessonIfNeeded();
        return;
      }
      final db = await _dbHelper.database;
      final results = await db.query('lessons',
          where: 'course_id = ?',
          whereArgs: [widget.course['id']],
          orderBy: '"order" ASC');
      setState(() {
        _lessons = results;
        _isLoading = false;
        _buildUnifiedContent();
      });
      _openInitialLessonIfNeeded();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _openInitialLessonIfNeeded() {
    final targetId = widget.initialLessonId;
    if (targetId == null || targetId.isEmpty || !mounted) return;
    final index = _unifiedContent.indexWhere((item) => '${item['id']}' == targetId);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LessonPlayerScreen(
            lessons: _unifiedContent,
            quizzes: _quizzes,
            initialIndex: index,
          ),
        ),
      );
    });
  }

  void _buildUnifiedContent() {
    final List<Map<String, dynamic>> unified = [];
    
    for (var l in _lessons) {
      unified.add({...l, 'is_quiz': false});
    }
    for (var q in _quizzes) {
      unified.add({...q, 'is_quiz': true, 'content_type': 'QUIZ'});
    }

    // Trier par ordre, puis par ID en cas d'égalité
    unified.sort((a, b) {
      int cmp = (a['order'] ?? 1).compareTo(b['order'] ?? 1);
      if (cmp == 0) {
        return (a['id'] ?? 0).compareTo(b['id'] ?? 0);
      }
      return cmp;
    });

    setState(() {
      _unifiedContent = unified;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _buildSliverAppBar(),
              SliverToBoxAdapter(child: _buildBody()),
            ],
          ),
          _buildFloatingBackButton(),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildFloatingBackButton() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    final thumbnail = widget.course['thumbnail'];
    final category = widget.course['category'] ?? '';

    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      automaticallyImplyLeading: false,
      backgroundColor: _primary,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Hero image or gradient placeholder
            (thumbnail != null && thumbnail.toString().isNotEmpty)
                ? Image.network(thumbnail.toString(), fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildHeroGradient(category))
                : _buildHeroGradient(category),
            // Dark overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            // Category badge bottom-left
            Positioned(
              bottom: 16,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  category.isNotEmpty ? category : 'Formation',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroGradient(String category) {
    final gradients = {
      'Mathématiques': [const Color(0xFF152A45), const Color(0xFF1E3A5F)],
      'Sciences': [const Color(0xFF065F46), const Color(0xFF10B981)],
      'Informatique': [const Color(0xFF1E293B), const Color(0xFF475569)],
      'Langues': [const Color(0xFF701A75), const Color(0xFFD946EF)],
      'Arts': [const Color(0xFF9A3412), const Color(0xFFF97316)],
      'Histoire': [const Color(0xFF78350F), const Color(0xFFF59E0B)],
    };
    final icons = {
      'Mathématiques': Icons.calculate_rounded,
      'Sciences': Icons.biotech_rounded,
      'Informatique': Icons.code_rounded,
      'Langues': Icons.translate_rounded,
      'Arts': Icons.palette_rounded,
      'Histoire': Icons.public_rounded,
    };
    final colors = gradients[category] ?? [const Color(0xFF152A45), const Color(0xFF1E3A5F)];
    final icon = icons[category] ?? Icons.auto_stories_rounded;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(icon, size: 80, color: Colors.white.withOpacity(0.25)),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Course info card
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.course['title'] ?? '',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0A0F1E),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF152A45), Color(0xFF1E3A5F)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.course['teacher_name'] ?? 'Enseignant Yekola',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const Text('Formateur certifié',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  _buildContactButton(),
                ],
              ),
              const SizedBox(height: 20),
              // Stats row
              Row(
                children: [
                  _buildStat(Icons.play_lesson_rounded, '${_lessons.length}', 'Leçons'),
                  const SizedBox(width: 16),
                  _buildStat(Icons.quiz_rounded, '${_quizzes.length}', 'Quiz'),
                  const SizedBox(width: 16),
                  _buildStat(Icons.signal_cellular_alt_rounded, 'Tous', 'Niveaux'),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        // Tab bar
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: _primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _primary,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Description'),
              Tab(text: 'Contenu'),
              Tab(text: 'Quiz'),
              Tab(text: 'TPs'),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 520,
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDescriptionTab(),
              _buildContentTab(),
              _buildQuizTab(),
              AssignmentScreen(course: widget.course),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildStat(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: _primary, size: 20),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _dark)),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  bool _isContactLoading = false;

  Widget _buildContactButton() {
    return GestureDetector(
      onTap: _isContactLoading ? null : () async {
        // Vérification authentification
        final auth = Provider.of<AuthProvider>(context, listen: false);
        if (!auth.isAuthenticated) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connectez-vous pour contacter l\'enseignant.'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pushNamed(context, '/login');
          return;
        }

        // Vérification que l'ID enseignant existe
        final teacherId = widget.course['teacher'];
        if (teacherId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Impossible d\'identifier l\'enseignant.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        // Démarrage du chargement
        setState(() => _isContactLoading = true);

        try {
          final teacherIdStr = teacherId.toString();
          final teacherName = widget.course['teacher_name'] ?? 'Enseignant';
          final roomId = await _chatService.getOrCreateDirectRoom(teacherIdStr, teacherName);
          final roomData = await _chatService.getRoomById(roomId);

          if (!mounted) return;
          setState(() => _isContactLoading = false);

          if (roomData != null) {
            // Navigation directe vers la discussion
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatDetailScreen(room: roomData)),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Impossible d\'ouvrir : La salle est introuvable dans Firestore.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            setState(() => _isContactLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur technique : $e'), backgroundColor: Colors.red),
            );
          }
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _isContactLoading ? _primary : Colors.transparent,
          border: Border.all(color: _primary),
          borderRadius: BorderRadius.circular(20),
        ),
        child: _isContactLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline, color: _primary, size: 14),
                  SizedBox(width: 6),
                  Text('Contacter',
                      style: TextStyle(color: _primary, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
      ),
    );
  }

  Widget _buildDescriptionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('À propos de cette formation',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _dark)),
          const SizedBox(height: 12),
          Text(
            widget.course['description'] ?? 'Aucune description disponible.',
            style: const TextStyle(color: Color(0xFF4A5568), fontSize: 14, height: 1.7),
          ),
          const SizedBox(height: 24),
          const Text('Ce que vous apprendrez',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _dark)),
          const SizedBox(height: 12),
          ...[
            'Maîtriser les fondamentaux du cours',
            'Appliquer vos connaissances en pratique',
            'Réussir les évaluations et quiz',
          ].map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle),
                      child: const Icon(Icons.check, color: Colors.white, size: 10),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item, style: const TextStyle(fontSize: 14, color: Color(0xFF4A5568)))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildQuizCard(Map<String, dynamic> quiz, int index) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LessonPlayerScreen(
        lessons: _unifiedContent,
        quizzes: _quizzes,
        initialIndex: _unifiedContent.indexWhere((item) => item['is_quiz'] == true && item['id'] == quiz['id'])
      ))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8EEFF)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF152A45), Color(0xFF1E3A5F)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.quiz_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Évaluation',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(quiz['title'] ?? 'Quiz',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _dark)),
                  const SizedBox(height: 2),
                  const Text('Questions à choix multiples',
                      style: TextStyle(fontSize: 12, color: _primary)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.play_arrow_rounded, color: _primary, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentTab() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (!_isEnrolled) return _buildEnrollmentRequired();
    if (_unifiedContent.isEmpty) return _buildNoLessons();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _unifiedContent.length,
      itemBuilder: (context, index) {
        final item = _unifiedContent[index];
        if (item['is_quiz'] == true) {
          // Affichage d'un quiz
          return _buildQuizCard(item, index);
        }
        return _buildLessonCard(item, index);
      },
    );
  }

  Widget _buildLessonCard(Map<String, dynamic> lesson, int index) {
    final typeData = _getTypeData(lesson['content_type']);
    final bool isLessonLocked = lesson['is_locked'] == true || lesson['is_locked'] == 1;

    return GestureDetector(
      onTap: isLessonLocked 
        ? () => _showLockedDialog(context)
        : () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => LessonPlayerScreen(
            lessons: _unifiedContent, 
            quizzes: _quizzes,
            initialIndex: _unifiedContent.indexWhere((item) => !item['is_quiz'] && item['id'] == lesson['id'])
          ))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isLessonLocked ? Colors.grey[50] : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isLessonLocked ? Colors.grey[200] : typeData['color'].withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isLessonLocked ? Icons.lock_rounded : typeData['icon'], 
                color: isLessonLocked ? Colors.grey : typeData['color'], 
                size: 20
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Leçon ${index + 1}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(lesson['title'] ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.w700, 
                        fontSize: 14, 
                        color: isLessonLocked ? Colors.grey : _dark
                      )),
                  if (!isLessonLocked) ...[
                    const SizedBox(height: 2),
                    Text(typeData['label'],
                        style: TextStyle(fontSize: 12, color: typeData['color'])),
                  ],
                ],
              ),
            ),
            if (!isLessonLocked)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.play_arrow_rounded, color: _primary, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _getTypeData(String? type) {
    switch (type) {
      case 'VIDEO': return {'icon': Icons.play_circle_fill_rounded, 'color': Colors.red, 'label': 'Vidéo'};
      case 'PDF': return {'icon': Icons.picture_as_pdf_rounded, 'color': Colors.orange, 'label': 'Document PDF'};
      case 'PPT': return {'icon': Icons.slideshow_rounded, 'color': Colors.purple, 'label': 'Présentation'};
      default: return {'icon': Icons.article_rounded, 'color': Colors.blue, 'label': 'Texte'};
    }
  }

  Widget _buildQuizTab() {
    if (_quizzes.isEmpty) {
      return const Center(child: Text('Aucun quiz disponible.', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _quizzes.length,
      itemBuilder: (context, index) {
        final quiz = _quizzes[index];
        return GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LessonPlayerScreen(
          lessons: _unifiedContent,
          quizzes: _quizzes,
          initialIndex: _unifiedContent.indexWhere((item) => item['is_quiz'] && item['id'] == quiz['id'])
        ))),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8EEFF)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
            ),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF152A45), Color(0xFF1E3A5F)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.quiz_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(quiz['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('${quiz['questions']?.length ?? 0} questions • ${quiz['time_limit']} min',
                          style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: _primary),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEnrollmentRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: _isLocked ? [Colors.red[800]!, Colors.red[600]!] : [const Color(0xFF152A45), const Color(0xFF1E3A5F)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(_isLocked ? Icons.lock_clock_rounded : Icons.lock_outline_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            Text(_isLocked ? 'Accès Bloqué (Prérequis)' : 'Contenu Verrouillé',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _dark)),
            const SizedBox(height: 10),
            Text(
              _isLocked 
                ? 'Vous devez réussir le quiz du module précédent avec au moins 50% de réussite pour débloquer ce cours.' 
                : 'Inscrivez-vous pour accéder aux leçons et ressources de ce cours.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.5)
            ),
            const SizedBox(height: 24),
            if (!_isLocked)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _toggleEnroll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('SUIVRE CE COURS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoLessons() {
    return const Center(child: Text('Aucune leçon publiée pour ce cours.', style: TextStyle(color: Colors.grey)));
  }


  void _showLockedDialog(BuildContext context) {
    // Trouver le quiz bloquant (le premier quiz d'évaluation non réussi)
    final blockingQuiz = _quizzes.firstWhere(
      (q) =>
          q['quiz_type'] == 'EVALUATION' &&
          (q['my_score'] == null || q['my_score'] < 50),
      orElse: () => {},
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text('Contenu verrouillé'),
          ],
        ),
        content: const Text(
          'Cette leçon est verrouillée. Vous devez réussir le quiz de validation avec au moins 50% de réussite pour y accéder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Compris'),
          ),
          if (blockingQuiz.isNotEmpty)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuizScreen(quiz: blockingQuiz),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Faire le quiz'),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    if (!_isEnrolled) {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, -4))],
        ),
        child: ElevatedButton(
          onPressed: _isLocked ? null : _toggleEnroll,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isLocked ? Colors.grey : _primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: Text(
            _isLocked ? 'PRÉREQUIS NON VALIDÉ' : 'S\'INSCRIRE GRATUITEMENT', 
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          // Bouton Téléchargement Premium
          IconButton(
            padding: const EdgeInsets.all(12),
            style: IconButton.styleFrom(
              backgroundColor: _isDownloaded ? Colors.green[50] : Colors.blue[50],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: _isDownloading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _primary),
                  )
                : Icon(
                    _isDownloaded ? Icons.download_done_rounded : Icons.download_rounded,
                    color: _isDownloaded ? Colors.green[700] : _primary,
                  ),
            onPressed: _isDownloading ? null : _downloadCourse,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _unifiedContent.isNotEmpty
                  ? () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => LessonPlayerScreen(
                        lessons: _unifiedContent, 
                        quizzes: _quizzes,
                        initialIndex: 0
                      )))
                  : null,
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              label: const Text('DÉMARRER L\'APPRENTISSAGE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
