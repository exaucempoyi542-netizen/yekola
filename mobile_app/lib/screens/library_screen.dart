import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/free_books_catalog.dart';
import '../services/sync_service.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  final SyncService _syncService = SyncService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _visibleItems = [];
  bool _isLoading = true;
  String _selectedSubject = 'Tous';

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  static const Color _ink = Color(0xFF0B1F2A);
  static const Color _teal = Color(0xFF0F766E);
  static const Color _sand = Color(0xFFF3EFE6);
  static const Color _paper = Color(0xFFF9F7F2);
  static const Color _muted = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _loadResources();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadResources() async {
    setState(() => _isLoading = true);
    try {
      if (!mounted) return;
      setState(() {
        _applyFilter();
        _isLoading = false;
      });
      _fadeCtrl.forward(from: 0);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _applyFilter();
      });
      _fadeCtrl.forward(from: 0);
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(FreeBooksCatalog.books);
    if (_selectedSubject != 'Tous') {
      items = items.where((b) => b['subject'] == _selectedSubject).toList();
    }

    if (query.isNotEmpty) {
      items = items.where((r) {
        final blob = [
          r['title'],
          r['description'],
          r['author'],
          r['subject'],
          r['category'],
        ].join(' ').toLowerCase();
        return blob.contains(query);
      }).toList();
    }
    _visibleItems = items;
  }

  Future<void> _launchURL(String? urlString) async {
    if (urlString == null || urlString.isEmpty) return;
    final url = Uri.parse(urlString);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d\'ouvrir : $e')),
        );
      }
    }
  }

  String _imageUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('/media/')) {
      return '${_syncService.apiBaseUrl.replaceAll('/api', '')}$url';
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildHero(),
          SliverToBoxAdapter(child: _buildSearch()),
          SliverToBoxAdapter(child: _buildSubjects()),
          if (_searchController.text.isEmpty)
            SliverToBoxAdapter(child: _buildFeaturedShelf()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text(
                'Catalogue',
                style: GoogleFonts.fraunces(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: _teal)),
            )
          else if (_visibleItems.isEmpty)
            SliverFillRemaining(child: _empty())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.04),
                          end: Offset.zero,
                        ).animate(_fadeAnim),
                        child: _bookRow(_visibleItems[index], index),
                      ),
                    );
                  },
                  childCount: _visibleItems.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return SliverAppBar(
      expandedHeight: 210,
      pinned: true,
      backgroundColor: _ink,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B1F2A), Color(0xFF134E4A), Color(0xFF0F766E)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -40,
                bottom: -30,
                child: Icon(
                  Icons.auto_stories_rounded,
                  size: 200,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 28,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BIBLIOTHÈQUE',
                      style: GoogleFonts.sourceSans3(
                        color: const Color(0xFF99F6E4),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 2.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Lire librement.',
                      style: GoogleFonts.fraunces(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Manuels ouverts et classiques du domaine public,\nofferts aux étudiants Yekola.',
                      style: GoogleFonts.sourceSans3(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(_applyFilter),
        style: GoogleFonts.sourceSans3(color: _ink, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Titre, auteur, matière…',
          hintStyle: GoogleFonts.sourceSans3(color: _muted),
          prefixIcon: const Icon(Icons.search, color: _teal),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18, color: _muted),
                  onPressed: () {
                    _searchController.clear();
                    setState(_applyFilter);
                  },
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: _ink.withValues(alpha: 0.12)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: _ink.withValues(alpha: 0.12)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            borderSide: BorderSide(color: _teal, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _buildSubjects() {
    final subjects = FreeBooksCatalog.subjects;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
        itemCount: subjects.length,
        separatorBuilder: (_, __) => const SizedBox(width: 18),
        itemBuilder: (context, index) {
          final subject = subjects[index];
          final active = _selectedSubject == subject;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedSubject = subject;
                _applyFilter();
              });
              _fadeCtrl.forward(from: 0);
            },
            child: Text(
              subject,
              style: GoogleFonts.sourceSans3(
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? _teal : _muted,
                decoration: active ? TextDecoration.underline : TextDecoration.none,
                decorationColor: _teal,
                decorationThickness: 2,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeaturedShelf() {
    final featured = FreeBooksCatalog.books.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: Text(
            'À découvrir',
            style: GoogleFonts.fraunces(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
        ),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: featured.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final book = featured[index];
              return _featuredCover(book);
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _featuredCover(Map<String, dynamic> book) {
    final image = _imageUrl(book['thumbnail_url']?.toString());
    return GestureDetector(
      onTap: () => _launchURL(book['url']?.toString()),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _sand,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: _ink.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(4, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: image.isEmpty
                    ? _coverFallback(book['title']?.toString() ?? '')
                    : Image.network(
                        image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _coverFallback(book['title']?.toString() ?? ''),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              book['title']?.toString() ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.sourceSans3(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _ink,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bookRow(Map<String, dynamic> item, int index) {
    final isBook = item['is_free'] == true || item['category'] == 'Livres gratuits';
    final image = _imageUrl(item['thumbnail_url']?.toString());

    return InkWell(
      onTap: () => _launchURL(item['url']?.toString()),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: _ink.withValues(alpha: 0.08)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 88,
              decoration: BoxDecoration(
                color: _sand,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: _ink.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(2, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: image.isEmpty
                  ? _coverFallback(item['title']?.toString() ?? '', compact: true)
                  : Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _coverFallback(item['title']?.toString() ?? '', compact: true),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${index + 1}'.padLeft(2, '0'),
                        style: GoogleFonts.sourceSans3(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _teal,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        (item['subject'] ?? item['category'] ?? 'Ressource')
                            .toString()
                            .toUpperCase(),
                        style: GoogleFonts.sourceSans3(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _muted,
                          letterSpacing: 0.8,
                        ),
                      ),
                      if (isBook) ...[
                        const Spacer(),
                        Text(
                          'Gratuit',
                          style: GoogleFonts.sourceSans3(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _teal,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item['title']?.toString() ?? 'Sans titre',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.fraunces(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                      height: 1.2,
                    ),
                  ),
                  if ((item['author'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item['author'].toString(),
                      style: GoogleFonts.sourceSans3(
                        fontSize: 13,
                        color: _muted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    item['description']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.sourceSans3(
                      fontSize: 13,
                      color: _muted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'Ouvrir',
                        style: GoogleFonts.sourceSans3(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_outward_rounded, size: 16, color: _teal),
                      const Spacer(),
                      if ((item['format'] ?? '').toString().isNotEmpty)
                        Text(
                          item['format'].toString(),
                          style: GoogleFonts.sourceSans3(fontSize: 11, color: _muted),
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

  Widget _coverFallback(String title, {bool compact = false}) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: _ink,
      padding: EdgeInsets.all(compact ? 6 : 10),
      alignment: Alignment.bottomLeft,
      child: Text(
        title,
        maxLines: compact ? 3 : 4,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.fraunces(
          color: Colors.white,
          fontSize: compact ? 10 : 13,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_outlined, size: 56, color: _ink.withValues(alpha: 0.25)),
            const SizedBox(height: 16),
            Text(
              'Aucun ouvrage',
              style: GoogleFonts.fraunces(fontSize: 22, color: _ink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Modifiez la recherche ou le filtre de matière.',
              textAlign: TextAlign.center,
              style: GoogleFonts.sourceSans3(color: _muted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
