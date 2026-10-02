import 'package:flutter/material.dart';
import 'package:mobile_app/services/firebase_service.dart';
import 'package:mobile_app/services/admin_service.dart';
import 'package:mobile_app/services/sync_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;
  final AdminService _adminService = AdminService();
  Map<String, dynamic> _stats = {};
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoadingStats = true);
    final stats = await _adminService.getStats();
    setState(() {
      _stats = stats;
      _isLoadingStats = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildMainContent(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    bool isExtended = MediaQuery.of(context).size.width > 1100;
    return Container(
      width: isExtended ? 280 : 80,
      decoration: const BoxDecoration(
        color: Color(0xFF001529),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(
        children: [
          Container(
            height: 80,
            alignment: Alignment.center,
            child: isExtended 
              ? const Text('EDURDC PORTAL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 2))
              : const Icon(Icons.bolt, color: Colors.amber, size: 32),
          ),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 20),
          _buildNavItem(0, Icons.dashboard_outlined, 'Dashboard', isExtended),
          _buildNavItem(1, Icons.menu_book_outlined, 'Formations', isExtended),
          _buildNavItem(2, Icons.people_outline, 'Utilisateurs', isExtended),
          _buildNavItem(3, Icons.quiz_outlined, 'Évaluations & Quiz', isExtended),
          _buildNavItem(4, Icons.sensors_outlined, 'Directs & Lives', isExtended),
          const Spacer(),
          _buildNavItem(5, Icons.settings_outlined, 'Configuration', isExtended),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, bool isExtended) {
    bool isSelected = _selectedIndex == index;
    return ListTile(
      onTap: () => setState(() => _selectedIndex = index),
      leading: Icon(icon, color: isSelected ? Colors.amber : Colors.white60),
      title: isExtended ? Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)) : null,
      selected: isSelected,
      selectedTileColor: Colors.blue.withOpacity(0.1),
      contentPadding: EdgeInsets.symmetric(horizontal: isExtended ? 24 : 20),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.black12))),
      child: Row(
        children: [
          Icon(_getIconForSection(_selectedIndex), color: const Color(0xFF001529)),
          const SizedBox(width: 12),
          Text(_getSectionTitle(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const Spacer(),
          _buildHeaderAction(Icons.search),
          _buildHeaderAction(Icons.notifications_none),
          const VerticalDivider(indent: 20, endIndent: 20, width: 40),
          const Text('Admin Yekola', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 12),
          const CircleAvatar(backgroundColor: Color(0xFF001529), child: Icon(Icons.person, color: Colors.white, size: 20)),
        ],
      ),
    );
  }

  Widget _buildHeaderAction(IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: IconButton(onPressed: () {}, icon: Icon(icon, color: Colors.black54)),
    );
  }

  String _getSectionTitle() {
    const titles = ['Vue d\'ensemble', 'Catalogue des Formations', 'Communauté', 'Gestion des Quiz', 'Streaming & Lives', 'Paramètres'];
    return titles[_selectedIndex];
  }

  IconData _getIconForSection(int index) {
    const icons = [Icons.grid_view, Icons.book, Icons.people, Icons.quiz, Icons.live_tv, Icons.settings];
    return icons[index];
  }

  Widget _buildMainContent() {
    switch (_selectedIndex) {
      case 0: return _buildOverview();
      case 1: return const CoursesManager();
      case 2: return const UsersManager();
      case 3: return const QuizManager();
      default: return const Center(child: Text('Section en cours d\'implémentation...'));
    }
  }

  Widget _buildOverview() {
    if (_isLoadingStats) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Statistiques Globales', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildMetricCard('Utilisateurs', _stats['total_users']?.toString() ?? '0', Icons.people, Colors.blue),
              _buildMetricCard('Étudiants', _stats['total_students']?.toString() ?? '0', Icons.person_search, Colors.green),
              _buildMetricCard('Enseignants', _stats['total_teachers']?.toString() ?? '0', Icons.school, Colors.purple),
              _buildMetricCard('Formations', _stats['total_courses']?.toString() ?? '0', Icons.auto_stories, Colors.orange),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: _buildActivityFeed()),
              const SizedBox(width: 32),
              Expanded(child: _buildQuickActions()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: color.withOpacity(0.1), radius: 28, child: Icon(icon, color: color, size: 30)),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.black54, fontSize: 14)),
                Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildActivityFeed() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Activités Récentes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          for (int i = 0; i < 5; i++)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.sync, size: 16)),
              title: Text('Nouvelle inscription étudiant #$i'),
              subtitle: const Text('Il y a 10 minutes'),
              trailing: const Icon(Icons.chevron_right, size: 16),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Actions Rapides', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _actionButton('Exporter les Stats', Icons.download, Colors.blue),
          _actionButton('Nouvelle Annonce', Icons.campaign, Colors.orange),
          _actionButton('Audit Sécurité', Icons.security, Colors.red),
          _actionButton('Logs Système', Icons.terminal, Colors.grey),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ElevatedButton.icon(
        onPressed: () {},
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 45),
          backgroundColor: color.withOpacity(0.1),
          foregroundColor: color,
          elevation: 0,
        ),
      ),
    );
  }
}

// --- MODULES DE GESTION ---

class QuizManager extends StatefulWidget {
  const QuizManager({super.key});

  @override
  State<QuizManager> createState() => _QuizManagerState();
}

class _QuizManagerState extends State<QuizManager> {
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _quizzes = [];

  @override
  void initState() {
    super.initState();
    _loadQuizzes();
  }

  Future<void> _loadQuizzes() async {
    final data = await _syncService.getQuizzes();
    setState(() => _quizzes = data);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Gestion des Quiz (${_quizzes.length})', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('Créer un Quiz')),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: _quizzes.length,
              itemBuilder: (context, index) {
                final quiz = _quizzes[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.quiz, color: Colors.blue),
                    title: Text(quiz['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Code: ${quiz['id_code']}'),
                    trailing: const Icon(Icons.more_vert),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Re-utiliser les managers précédents mais avec un style plus propre...
class CoursesManager extends StatelessWidget {
  const CoursesManager({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Module Courses mis à jour...'));
}

class UsersManager extends StatelessWidget {
  const UsersManager({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Module Users mis à jour...'));
}

class ExternalResourcesManager extends StatefulWidget {
  const ExternalResourcesManager({super.key});

  @override
  State<ExternalResourcesManager> createState() => _ExternalResourcesManagerState();
}

class _ExternalResourcesManagerState extends State<ExternalResourcesManager> {
  final FirebaseService _firebaseService = FirebaseService();
  List<ExternalResource> _resources = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadResources();
  }

  Future<void> _loadResources() async {
    setState(() => _isLoading = true);
    final data = await _firebaseService.getExternalResources();
    setState(() {
      _resources = data;
      _isLoading = false;
    });
  }

  void _showAddOrEditDialog({ExternalResource? resource}) {
    final titleController = TextEditingController(text: resource?.title ?? '');
    final descController = TextEditingController(text: resource?.description ?? '');
    final urlController = TextEditingController(text: resource?.url ?? '');
    final thumbnailController = TextEditingController(text: resource?.thumbnailUrl ?? '');
    String selectedCategory = resource?.category ?? 'Informatique';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(resource == null ? 'Ajouter une Ressource Externe' : 'Modifier la Ressource'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Titre de la formation', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(labelText: 'Lien externe (Youtube, Coursera, etc.)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: thumbnailController,
                      decoration: const InputDecoration(
                        labelText: 'URL de l\'image de couverture (Thumbnail)', 
                        border: OutlineInputBorder(),
                        hintText: 'https://images.unsplash.com/photo-...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      decoration: const InputDecoration(labelText: 'Catégorie', border: OutlineInputBorder()),
                      items: ['Mathématiques', 'Sciences', 'Informatique', 'Langues', 'Arts', 'Histoire']
                          .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedCategory = val);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final data = {
                      'title': titleController.text,
                      'description': descController.text,
                      'url': urlController.text,
                      'thumbnail_url': thumbnailController.text,
                      'category': selectedCategory,
                    };

                    if (resource == null) {
                      await _firebaseService.addResource(data);
                    } else {
                      await _firebaseService.updateResource(resource.id, data);
                    }

                    if (mounted) {
                      Navigator.pop(context);
                      _loadResources();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Action enregistrée avec succès !'), backgroundColor: Colors.green),
                      );
                    }
                  },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPlaceholder(String category) {
    IconData icon;
    List<Color> colors;

    switch (category) {
      case 'Mathématiques':
        icon = Icons.calculate_rounded;
        colors = [const Color(0xFF152A45), const Color(0xFF1E3A5F)];
        break;
      case 'Sciences':
        icon = Icons.biotech_rounded;
        colors = [const Color(0xFF065F46), const Color(0xFF10B981)];
        break;
      case 'Informatique':
        icon = Icons.code_rounded;
        colors = [const Color(0xFF1E293B), const Color(0xFF475569)];
        break;
      case 'Langues':
        icon = Icons.translate_rounded;
        colors = [const Color(0xFF701A75), const Color(0xFFD946EF)];
        break;
      case 'Arts':
        icon = Icons.palette_rounded;
        colors = [const Color(0xFF9A3412), const Color(0xFFF97316)];
        break;
      case 'Histoire':
        icon = Icons.public_rounded;
        colors = [const Color(0xFF78350F), const Color(0xFFF59E0B)];
        break;
      default:
        icon = Icons.auto_stories_rounded;
        colors = [const Color(0xFF152A45), const Color(0xFF152A45)];
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: 24,
          color: Colors.white.withOpacity(0.8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ressources & Formations Externes', 
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF001529)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Gérez les liens et ressources hébergées sur le cloud Firestore (${_resources.length} éléments)',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddOrEditDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une ressource'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF001529),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _resources.isEmpty
                    ? const Center(child: Text('Aucune ressource externe disponible.'))
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                          childAspectRatio: 1.4,
                        ),
                        itemCount: _resources.length,
                        itemBuilder: (context, index) {
                          final res = _resources[index];
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: res.thumbnailUrl.isNotEmpty
                                          ? Image.network(
                                              res.thumbnailUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) => _buildPlaceholder(res.category),
                                            )
                                          : _buildPlaceholder(res.category),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 6,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                res.category,
                                                style: TextStyle(color: Colors.blue.shade700, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                                                  onPressed: () => _showAddOrEditDialog(resource: res),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                                  onPressed: () async {
                                                    await _firebaseService.deleteResource(res.id);
                                                    _loadResources();
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          res.title,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          res.description,
                                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
