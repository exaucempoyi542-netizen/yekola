import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import 'course_details_screen.dart';

class CatalogueScreen extends StatefulWidget {
  final bool autofocusSearch;

  const CatalogueScreen({super.key, this.autofocusSearch = false});

  @override
  State<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends State<CatalogueScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _allCourses = [];
  List<Map<String, dynamic>> _filteredCourses = [];
  final String apiBaseUrl = ApiConfig.apiBaseUrl;

  String _selectedCategory = 'Tous';
  bool _isLoading = false;

  final List<String> _categories = [
    'Tous',
    'Mathématiques',
    'Sciences',
    'Informatique',
    'Langues',
    'Arts',
    'Histoire'
  ];

  @override
  void initState() {
    super.initState();
    _loadCourses();
    if (widget.autofocusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCourses({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);

    try {
      // Cache TTL (5 min) sauf pull-to-refresh
      final courses = await _syncService.getCourses(forceRefresh: forceRefresh);

      setState(() {
        _allCourses = List<Map<String, dynamic>>.from(courses);
        _applyFilters();
      });
    } catch (e) {
      debugPrint("Erreur lors du chargement des cours: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Échec de connexion : $e"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredCourses = _allCourses.where((course) {
        final title = (course['title'] ?? '').toString().toLowerCase();
        final description = (course['description'] ?? '').toString().toLowerCase();
        
        final matchesSearch = title.contains(query) || description.contains(query);
        
        final matchesCategory = _selectedCategory == 'Tous' ||
            (course['category'] != null && course['category'] == _selectedCategory);
            
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildHeader(),
          _buildCategoryFilter(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCourses.isEmpty
                    ? _buildEmptyState()
                    : _buildCourseList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 10),
      color: theme.cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Catalogue',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.titleLarge?.color ?? const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: (value) => _applyFilters(),
            decoration: InputDecoration(
              hintText: 'Rechercher une formation...',
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
              suffixIcon: _searchController.text.isNotEmpty 
                ? IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey, size: 18), 
                    onPressed: () {
                      _searchController.clear();
                      _applyFilters();
                    }
                  )
                : null,
              filled: true,
              fillColor: theme.brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8F9FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: theme.dividerColor, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: theme.dividerColor, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF152A45), width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = _selectedCategory == category;
          return InkWell(
            onTap: () {
              setState(() {
                _selectedCategory = category;
                _applyFilters();
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 24),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? const Color(0xFF152A45) : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                category,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF152A45) : Colors.grey[600],
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCourseList() {
    return RefreshIndicator(
      onRefresh: () async {
        await _syncService.pullCourses(forceRefresh: true);
        await _loadCourses(forceRefresh: false);
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredCourses.length,
        itemBuilder: (context, index) {
          final course = _filteredCourses[index];
          return _buildCourseCard(course);
        },
      ),
    );
  }

  Widget _buildCourseCard(Map<String, dynamic> course) {
    final bool isLive = course['active_live'] != null;
    
    String? thumbnailUrl = course['thumbnail'];
    if (thumbnailUrl != null && !thumbnailUrl.startsWith('http')) {
      thumbnailUrl = ApiConfig.resolveMediaUrl(thumbnailUrl);
    }

    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.2 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CourseDetailsScreen(course: course),
                ),
              );
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Thumbnail (Left Side)
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildThumbnail(thumbnailUrl, course['category'] ?? 'Général'),
                      if (isLive)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                
                // 2. Info (Right Side)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course['title'] ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: theme.textTheme.titleMedium?.color ?? const Color(0xFF1A1A1A),
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${course['teacher_name'] ?? "Yekola"}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(String? thumbnailUrl, String category) {
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      return Image.network(
        thumbnailUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(category),
      );
    }
    return _buildPlaceholder(category);
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
          size: 40,
          color: Colors.white.withValues(alpha: 0.8),
        ),
      ),
    );
  }


  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Aucun cours trouvé',
            style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Essayez une autre recherche ou catégorie.',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
