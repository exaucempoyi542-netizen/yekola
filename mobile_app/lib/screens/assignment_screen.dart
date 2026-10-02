import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../services/sync_service.dart';
import '../providers/auth_provider.dart';
import 'package:provider/provider.dart';

class AssignmentScreen extends StatefulWidget {
  final Map<String, dynamic>? course; // null = vue globale de tous les TPs
  const AssignmentScreen({super.key, this.course});

  @override
  State<AssignmentScreen> createState() => _AssignmentScreenState();
}

class _AssignmentScreenState extends State<AssignmentScreen>
    with SingleTickerProviderStateMixin {
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _assignments = [];
  bool _isLoading = true;
  late TabController _tabController;

  static const Color _primary = Color(0xFF152A45);
  static const Color _accent = Color(0xFF4CAF50);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAssignments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAssignments() async {
    setState(() => _isLoading = true);
    final assignments = await _syncService.getAssignments(
      courseId: widget.course?['id'],
    );
    if (mounted) {
      setState(() {
        _assignments = assignments;
        _isLoading = false;
      });
    }
  }

  Future<void> _submitAssignment(Map<String, dynamic> assignment) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      withData: true,
      allowedExtensions: [
        'pdf',
        'doc', 'docx',
        'ppt', 'pptx',
        'mp4', 'avi', 'mov', 'mkv',
        'jpg', 'jpeg', 'png',
      ],
    );
    if (result == null) return;
    
    final file = result.files.single;
    
    // Protection pour Flutter Web où l'accès à file.path lance une exception
    if (kIsWeb) {
      if (file.bytes == null) return;
    } else {
      if (file.path == null) return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Envoi en cours...'),
              ],
            ),
          ),
        ),
      ),
    );

    final res = await _syncService.submitAssignment(assignment['id'], file);
    if (!mounted) return;
    Navigator.pop(context);

    if (res != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('TP soumis avec succès !'),
          backgroundColor: Colors.green,
        ),
      );
      _loadAssignments();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur lors de la soumission. Vérifiez votre connexion.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final isTeacher = auth.userRole == 'TEACHER';
    final title = widget.course != null
        ? 'TPs — ${widget.course!['title']}'
        : 'Mes Travaux Pratiques';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAssignments),
        ],
        bottom: isTeacher
            ? null
            : TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                tabs: const [
                  Tab(text: 'En Attente'),
                  Tab(text: 'Corrigés'),
                ],
              ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _assignments.isEmpty
              ? _buildEmpty()
              : isTeacher
                  ? _buildTeacherView()
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildStudentList(graded: false),
                        _buildStudentList(graded: true),
                      ],
                    ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.assignment_outlined, size: 60, color: _primary),
          ),
          const SizedBox(height: 20),
          const Text('Aucun TP disponible',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Les TPs publiés par vos enseignants\napparaîtront ici.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // Vue Étudiant : liste filtrée par état de correction
  Widget _buildStudentList({required bool graded}) {
    final filtered = _assignments.where((a) {
      final sub = a['my_submission'];
      if (graded) return sub != null && sub['is_graded'] == true;
      return sub == null || sub['is_graded'] != true;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          graded ? 'Aucun TP corrigé pour l\'instant.' : 'Aucun TP en attente.',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (_, i) => _buildAssignmentCard(filtered[i]),
    );
  }

  // Vue Enseignant : liste tous les TPs avec nombre de soumissions
  Widget _buildTeacherView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _assignments.length,
      itemBuilder: (_, i) => _buildTeacherCard(_assignments[i]),
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic> assignment) {
    final sub = assignment['my_submission'] as Map<String, dynamic>?;
    final isSubmitted = sub != null;
    final isGraded = sub?['is_graded'] == true;
    final gradeRaw = sub?['grade'];
    final double? grade = gradeRaw != null ? double.tryParse(gradeRaw.toString()) : null;
    final comment = sub?['grade_comment'];

    Color statusColor = isGraded
        ? (grade != null && grade >= 10 ? Colors.green : Colors.red)
        : isSubmitted
            ? Colors.orange
            : Colors.grey;
    IconData statusIcon = isGraded
        ? Icons.grading_rounded
        : isSubmitted
            ? Icons.hourglass_empty_rounded
            : Icons.upload_file_rounded;
    String statusLabel = isGraded
        ? 'Corrigé — $grade/20'
        : isSubmitted
            ? 'Soumis · En attente de correction'
            : 'À soumettre';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_primary.withOpacity(0.08), Colors.transparent],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.assignment_rounded, color: _primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(assignment['title'] ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(assignment['course_title'] ?? '',
                          style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              assignment['description'] ?? '',
              style: const TextStyle(fontSize: 13, color: Color(0xFF4A5568), height: 1.5),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (assignment['due_date'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.orange),
                  const SizedBox(width: 6),
                  Text(
                    'À remettre : ${_formatDate(assignment['due_date'])}',
                    style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          // Status
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 6),
                      Text(statusLabel,
                          style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ],
                  ),
                ),
                if (isGraded && comment != null && comment.toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.withOpacity(0.15)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.comment_rounded, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            comment.toString(),
                            style: const TextStyle(fontSize: 13, color: Color(0xFF2D3748)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!isSubmitted) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _submitAssignment(assignment),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Envoyer mon TP',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherCard(Map<String, dynamic> assignment) {
    final count = assignment['submissions_count'] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF152A45), Color(0xFF1E3A5F)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.assignment_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(assignment['title'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(assignment['course_title'] ?? '',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 6),
                Text('$count soumission${count > 1 ? 's' : ''}',
                    style: const TextStyle(color: _primary, fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        ],
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}
