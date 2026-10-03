import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../providers/auth_provider.dart';
import '../services/sync_service.dart';
import 'course_details_screen.dart';
import 'login_screen.dart';
import 'menu_screen.dart';
import 'notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<Map<String, dynamic>> courses;
  final bool isSyncing;
  final Future<void> Function() onRefresh;
  final VoidCallback? onSearchTap;

  const HomeScreen({
    super.key,
    required this.courses,
    required this.isSyncing,
    required this.onRefresh,
    this.onSearchTap,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SyncService _syncService = SyncService();
  List<Map<String, dynamic>> _allLessons = [];

  @override
  void initState() {
    super.initState();
    _processLessons();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.courses != oldWidget.courses) {
      _processLessons();
    }
  }

  void _processLessons() {
    List<Map<String, dynamic>> flattened = [];
    for (var course in widget.courses) {
      final lessons = course['lessons'];
      if (lessons is List && lessons.isNotEmpty) {
        for (var lesson in lessons) {
          flattened.add({
            ...lesson,
            'teacher_name': course['teacher_name'],
            'teacher': course['teacher'],
            'course_title': course['title'],
            'course_description': course['description'],
            'course_id': course['id'],
            'course_thumbnail': course['thumbnail'],
            'is_enrolled': course['is_enrolled'],
            'is_following': course['is_following'],
            'price': course['price'],
            'is_free': course['is_free'],
            'active_live': course['active_live'],
          });
        }
      } else {
        // Cours publié sans leçon encore : visible dans le fil d'accueil
        flattened.add({
          'id': 'course_${course['id']}',
          'title': course['title'],
          'content_type': 'COURSE',
          'teacher_name': course['teacher_name'],
          'teacher': course['teacher'],
          'course_title': course['title'],
          'course_description': course['description'],
          'course_id': course['id'],
          'course_thumbnail': course['thumbnail'],
          'is_enrolled': course['is_enrolled'],
          'is_following': course['is_following'],
          'price': course['price'],
          'is_free': course['is_free'],
          'active_live': course['active_live'],
        });
      }
    }

    flattened.shuffle();

    setState(() {
      _allLessons = flattened;
    });
  }

  void _handleCardTap(Map<String, dynamic> item) {
    final parentCourse = widget.courses.firstWhere(
      (c) => c['id'] == item['course_id'],
      orElse: () => {},
    );
    if (parentCourse.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CourseDetailsScreen(
            course: parentCourse,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.cardColor,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories_rounded, color: Color(0xFF152A45), size: 28),
            const SizedBox(width: 8),
            Text(
              'Yekola',
              style: TextStyle(
                color: theme.textTheme.titleLarge?.color ?? const Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
                fontSize: 22,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Color(0xFF64748B)),
            onPressed: widget.onSearchTap,
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Color(0xFF64748B)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconButton(
                  tooltip: auth.isAuthenticated ? 'Mon compte' : 'Se connecter',
                  onPressed: () {
                    if (auth.isAuthenticated) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MenuScreen()),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    }
                  },
                  icon: CircleAvatar(
                    radius: 16,
                    backgroundColor: auth.isAuthenticated
                        ? const Color(0xFF152A45)
                        : const Color(0xFFE2E8F0),
                    backgroundImage: auth.hasCustomAvatar
                        ? MemoryImage(auth.avatarBytes!)
                        : null,
                    child: auth.hasCustomAvatar
                        ? null
                        : (auth.hasEmojiAvatar
                            ? Text(auth.profileEmoji!, style: const TextStyle(fontSize: 14))
                            : Icon(
                                auth.isAuthenticated
                                    ? Icons.person
                                    : Icons.login_rounded,
                                size: 18,
                                color: auth.isAuthenticated
                                    ? Colors.white
                                    : const Color(0xFF64748B),
                              )),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _allLessons.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: widget.onRefresh,
              color: const Color(0xFF152A45),
              child: ListView.separated(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                itemCount: _allLessons.length,
                separatorBuilder: (context, index) => const SizedBox(height: 24),
                itemBuilder: (context, index) {
                  return YouTubeCard(
                    item: _allLessons[index],
                    onTap: () => _handleCardTap(_allLessons[index]),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.15),
          if (widget.isSyncing)
            const Center(child: CircularProgressIndicator())
          else ...[
            Icon(Icons.video_library_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text(
              'Le contenu est vide',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }
}

class YouTubeCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const YouTubeCard({Key? key, required this.item, required this.onTap}) : super(key: key);

  String _getTypeLabel(String? type) {
    switch (type) {
      case 'VIDEO': return 'VIDÉO';
      case 'PDF': return 'DOCUMENT PDF';
      case 'PPT': return 'PRÉSENTATION';
      case 'TEXT': return 'LECTURE';
      default: return 'LEÇON';
    }
  }

  IconData _getTypeIcon(String? type) {
    switch (type) {
      case 'VIDEO': return Icons.play_circle_fill;
      case 'PDF': return Icons.picture_as_pdf;
      case 'PPT': return Icons.slideshow;
      case 'TEXT': return Icons.article;
      default: return Icons.library_books;
    }
  }

  @override
  Widget build(BuildContext context) {
    String? thumbnailUrl = item['thumbnail'] ?? item['course_thumbnail'];
    if (thumbnailUrl != null && !thumbnailUrl.startsWith('http')) {
      thumbnailUrl = ApiConfig.resolveMediaUrl(thumbnailUrl);
    }

    final description = item['course_description'];

    return InkWell(
      onTap: onTap,
      child: Container(
        color: Theme.of(context).cardColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description != null && description.toString().trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.8),
                    height: 1.4,
                  ),
                ),
              ),
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    width: double.infinity,
                    color: Colors.grey[200],
                    child: thumbnailUrl != null
                        ? Image.network(
                            thumbnailUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.image_not_supported, color: Colors.grey)),
                          )
                        : Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Center(
                              child: Icon(_getTypeIcon(item['content_type']), size: 64, color: Colors.white24),
                            ),
                          ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getTypeIcon(item['content_type']), size: 12, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          _getTypeLabel(item['content_type']),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(0xFFEFF6FF),
                    child: Icon(
                      Icons.person,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title'] ?? 'Sans titre',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).textTheme.titleMedium?.color,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item['teacher_name']} • ${item['course_title']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 20, color: Color(0xFF94A3B8)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
