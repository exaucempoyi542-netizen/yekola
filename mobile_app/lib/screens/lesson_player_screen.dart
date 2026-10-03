import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'quiz_screen.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';
import '../services/sync_service.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

class LessonPlayerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> lessons;
  final List<Map<String, dynamic>> quizzes;
  final int initialIndex;

  const LessonPlayerScreen({
    super.key,
    required this.lessons,
    this.quizzes = const [],
    required this.initialIndex,
  });

  @override
  State<LessonPlayerScreen> createState() => _LessonPlayerScreenState();
}

class _LessonPlayerScreenState extends State<LessonPlayerScreen>
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  WebViewController? _webViewController;
  String? _localPdfPath;
  bool _isDownloading = false;
  bool _showLessonList = false;

  final SyncService _syncService = SyncService();
  final String _baseUrl = ApiConfig.host;

  static const Color _primary = Color(0xFF152A45);
  static const Color _dark = Color(0xFF0A0F1E);

  String? _mediaError;
  bool _isMediaLoading = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _initializeLesson();
  }

  String _resolveMediaUrl(String path) => ApiConfig.resolveMediaUrl(path);

  String? _mediaSourceForLesson(Map<String, dynamic> lesson) {
    // Sur le web, jamais de chemin fichier local (dart:io non supporté)
    if (kIsWeb) {
      final remote = lesson['content_file'] ?? lesson['url'];
      return remote?.toString();
    }
    final local = lesson['local_path']?.toString();
    if (local != null && local.isNotEmpty) return local;
    return lesson['content_file']?.toString() ?? lesson['url']?.toString();
  }

  void _initializeLesson() {
    final lesson = widget.lessons[_currentIndex];
    final type = lesson['content_type'];
    final sourcePath = _mediaSourceForLesson(lesson);

    _disposeContent();
    _mediaError = null;
    _isMediaLoading = false;

    if (type == 'VIDEO') {
      _initVideo(sourcePath);
    } else if (type == 'PDF') {
      _initPdf(sourcePath);
    } else if (type == 'PPT') {
      _initPpt(sourcePath);
    } else if (type == 'EXTERNAL') {
      _initWebView(lesson['url']?.toString() ?? sourcePath ?? '');
    }

    // Synchroniser la progression avec le backend en arrière-plan
    if (widget.lessons.isNotEmpty) {
      final firstLesson = widget.lessons.first;
      final courseId = firstLesson['course'] ?? firstLesson['course_id'];
      if (courseId != null) {
        final progressPercent =
            ((_currentIndex + 1) / widget.lessons.length) * 100.0;
        _syncService.updateEnrollmentProgress(
          courseId is int ? courseId : int.tryParse(courseId.toString()) ?? 0,
          progressPercent,
        );
      }
    }
  }

  void _initWebView(String url) {
    if (kIsWeb) return;
    if (url.isEmpty) return;
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (_) => NavigationDecision.navigate,
        ),
      )
      ..loadRequest(Uri.parse(_resolveMediaUrl(url)));
  }

  void _disposeContent() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    _videoPlayerController = null;
    _chewieController = null;
    _webViewController = null;
    _localPdfPath = null;
    _isDownloading = false;
  }

  Future<void> _initVideo(String? filePath) async {
    if (filePath == null || filePath.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _mediaError = 'Aucun fichier vidéo pour ce module.';
          _isMediaLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _mediaError = null;
        _isMediaLoading = true;
      });
    }

    try {
      final isLocalFile = !kIsWeb && File(filePath).existsSync();
      if (isLocalFile) {
        _videoPlayerController = VideoPlayerController.file(File(filePath));
      } else {
        final url = _resolveMediaUrl(filePath);
        _videoPlayerController = VideoPlayerController.networkUrl(
          Uri.parse(url),
          httpHeaders: const {
            'Accept': '*/*',
          },
        );
      }

      await _videoPlayerController!.initialize();
      final ratio = _videoPlayerController!.value.aspectRatio;
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        aspectRatio: ratio > 0 ? ratio : (16 / 9),
        placeholder: const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, errorMessage) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Lecture impossible : $errorMessage',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
      if (mounted) {
        setState(() {
          _isMediaLoading = false;
          _mediaError = null;
        });
      }
    } catch (e) {
      debugPrint('Erreur lecture vidéo: $e');
      if (mounted) {
        setState(() {
          _isMediaLoading = false;
          _mediaError =
              'Impossible de lire la vidéo. Vérifiez que le serveur Django tourne et que le fichier est accessible.\n$e';
        });
      }
    }
  }

  Future<void> _initPdf(String? filePath) async {
    if (filePath == null || filePath.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _mediaError = 'Aucun document pour ce module.';
        });
      }
      return;
    }

    // Check if offline (mobile/desktop only)
    if (!kIsWeb && File(filePath).existsSync()) {
      setState(() {
        _localPdfPath = filePath;
        _isDownloading = false;
      });
      return;
    }

    final url = _resolveMediaUrl(filePath);

    if (kIsWeb) {
      // Sur le web, ouvrir le PDF dans un nouvel onglet (iframe plus fiable)
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
      } catch (e) {
        if (mounted) {
          setState(() {
            _mediaError = 'Impossible d\'ouvrir le document : $e';
          });
        }
      }
      return;
    }

    setState(() => _isDownloading = true);
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/lesson_$_currentIndex.pdf');
      await file.writeAsBytes(response.bodyBytes);
      setState(() {
        _localPdfPath = file.path;
        _isDownloading = false;
        _mediaError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _mediaError = 'Impossible de charger le PDF.\n$e';
        });
      }
    }
  }

  /// PowerPoint : visionneuse Office Online (nécessite une URL HTTPS publique).
  Future<void> _initPpt(String? filePath) async {
    if (filePath == null || filePath.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _mediaError = 'Aucun fichier PowerPoint pour ce module.';
          _isDownloading = false;
        });
      }
      return;
    }

    final url = _resolveMediaUrl(filePath);
    if (kIsWeb) {
      if (mounted) setState(() => _isDownloading = false);
      return;
    }

    setState(() {
      _isDownloading = true;
      _mediaError = null;
    });

    final viewerUrl =
        'https://view.officeapps.live.com/op/embed.aspx?src=${Uri.encodeComponent(url)}';
    try {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (_) => NavigationDecision.navigate,
            onWebResourceError: (error) {
              debugPrint('PPT WebView error: ${error.description}');
            },
          ),
        )
        ..loadRequest(Uri.parse(viewerUrl));
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _mediaError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _mediaError =
              'Impossible d\'afficher le PowerPoint. Ouvrez-le via le bouton externe.\n$e';
        });
      }
    }
  }

  @override
  void dispose() {
    _disposeContent();
    super.dispose();
  }

  void _goToLesson(int index) {
    setState(() {
      _currentIndex = index;
      _showLessonList = false;
      _initializeLesson();
    });
  }

  void _nextLesson() async {
    if (_currentIndex < widget.lessons.length - 1) {
      final nextLesson = widget.lessons[_currentIndex + 1];
      final bool isLocked = nextLesson['is_locked'] == true || 
                            nextLesson['is_locked'] == 1 || 
                            nextLesson['is_locked'] == 'true' || 
                            nextLesson['is_locked'] == '1';
      if (isLocked) {
        final passed = await _redirectToQuizOrShowLock();
        if (passed == true) {
          setState(() {
            nextLesson['is_locked'] = false;
          });
          _goToLesson(_currentIndex + 1);
        }
        return;
      }
      _goToLesson(_currentIndex + 1);
    }
  }

  Future<bool?> _redirectToQuizOrShowLock() async {
    final blockingQuiz = widget.quizzes.firstWhere(
      (q) =>
          q['quiz_type'] == 'EVALUATION' &&
          (q['my_score'] == null || q['my_score'] < 50),
      orElse: () => {},
    );

    if (blockingQuiz.isNotEmpty) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuizScreen(quiz: blockingQuiz),
        ),
      );
      if (result == true) {
        blockingQuiz['my_score'] = 100; // Local optimist update
      }
      return result;
    } else {
      return await _showLockedDialog();
    }
  }

  Future<bool?> _showLockedDialog() {
    // Trouver le quiz bloquant (le premier quiz d'évaluation non réussi)
    final blockingQuiz = widget.quizzes.firstWhere(
      (q) =>
          q['quiz_type'] == 'EVALUATION' &&
          (q['my_score'] == null || q['my_score'] < 50),
      orElse: () => {},
    );

    return showDialog<bool>(
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
          'Vous devez réussir le quiz de validation de ce module avec au moins 50% de réussite pour passer à la leçon suivante.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Compris'),
          ),
          if (blockingQuiz.isNotEmpty)
            ElevatedButton(
              onPressed: () async {
                // Remplacer le dialog par l'écran du quiz
                final result = await Navigator.pushReplacement<bool?, void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuizScreen(quiz: blockingQuiz),
                  ),
                );
                
                if (result == true) {
                  setState(() {
                    blockingQuiz['my_score'] = 100; // optimistic local update
                  });
                  // L'écran est revenu à LessonPlayerScreen. Notifier la réussite.
                  // Note : comme showDialog a été remplacé, il faut s'assurer que le caller
                  // reçoit bien ce "result". pushReplacement résout le future de showDialog !
                }
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

  void _prevLesson() {
    if (_currentIndex > 0) _goToLesson(_currentIndex - 1);
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lessons[_currentIndex];
    final type = lesson['content_type'] ?? 'TEXT';
    final isVideoOrPdf = type == 'VIDEO' || type == 'PDF' || type == 'EXTERNAL';
    final isDark = isVideoOrPdf;

    return Scaffold(
      backgroundColor: isDark ? _dark : const Color(0xFFF8FAFD),
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(lesson, isDark),
              if (!isDark) _buildProgressBar(),
              Expanded(child: _buildContent(lesson)),
              _buildBottomNav(isDark),
            ],
          ),
          if (_showLessonList) _buildLessonDrawer(),
        ],
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> lesson, bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.of(context).padding.top + 4,
        8,
        12,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A0F1E) : Colors.white,
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back_ios,
              color: isDark ? Colors.white : _dark,
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Leçon ${_currentIndex + 1} / ${widget.lessons.length}',
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  lesson['title'] ?? '',
                  style: TextStyle(
                    color: isDark ? Colors.white : _dark,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Lesson list toggle
          GestureDetector(
            onTap: () => setState(() => _showLessonList = !_showLessonList),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.list_rounded,
                    color: isDark ? Colors.white : _primary,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Leçons',
                    style: TextStyle(
                      color: isDark ? Colors.white : _primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final progress = (_currentIndex + 1) / widget.lessons.length;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFFE8EEFF),
              valueColor: const AlwaysStoppedAnimation<Color>(_primary),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(progress * 100).toInt()}% complété',
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> lesson) {
    final type = lesson['content_type'];

    if (type == 'VIDEO') {
      if (_mediaError != null) {
        return Container(
          color: Colors.black,
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                const SizedBox(height: 16),
                Text(
                  _mediaError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: () => _initializeLesson(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: _primary,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      if (_chewieController != null &&
          _chewieController!.videoPlayerController.value.isInitialized) {
        return Container(
          color: Colors.black,
          child: Center(child: Chewie(controller: _chewieController!)),
        );
      }
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Chargement de la vidéo…', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (type == 'PDF') {
      if (_isDownloading) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Chargement du document...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        );
      }
      if (kIsWeb) {
        final url = lesson['content_file']?.startsWith('http') == true
            ? lesson['content_file']
            : '$_baseUrl${lesson['content_file']}';
        return HtmlWidget(
          '<iframe src="$url" style="width:100%; height:100%; border:none;"></iframe>',
        );
      }
      if (_webViewController != null) {
        return WebViewWidget(controller: _webViewController!);
      }
      if (_localPdfPath != null) {
        return PDFView(filePath: _localPdfPath);
      }
      return const Center(
        child: Text(
          'Impossible de charger le PDF',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }

    if (type == 'PPT') {
      final fileUrl = lesson['content_file']?.startsWith('http') == true
          ? lesson['content_file'].toString()
          : _resolveMediaUrl(lesson['content_file']?.toString() ?? '');

      if (_mediaError != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.slideshow_outlined, color: Colors.white54, size: 48),
                const SizedBox(height: 12),
                Text(
                  _mediaError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.4),
                ),
                if (fileUrl.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(fileUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Ouvrir le PowerPoint'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: _primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }

      if (_isDownloading) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Chargement de la présentation...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        );
      }

      if (kIsWeb) {
        return HtmlWidget(
          '<iframe src="https://view.officeapps.live.com/op/embed.aspx?src=${Uri.encodeComponent(fileUrl)}" '
          'style="width:100%; height:100%; border:none;"></iframe>',
        );
      }

      if (_webViewController != null) {
        return Column(
          children: [
            Expanded(child: WebViewWidget(controller: _webViewController!)),
            SafeArea(
              top: false,
              child: TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(fileUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Ouvrir dans une autre app'),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
            ),
          ],
        );
      }

      return Center(
        child: TextButton.icon(
          onPressed: () => launchUrl(
            Uri.parse(fileUrl),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.slideshow),
          label: const Text('Ouvrir le PowerPoint'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: _primary,
          ),
        ),
      );
    }

    if (type == 'EXTERNAL') {
      if (kIsWeb) {
        final url = lesson['url'] ?? lesson['content_file'] ?? '';
        return HtmlWidget(
          '<iframe src="$url" style="width:100%; height:100%; border:none;"></iframe>',
        );
      }
      if (_webViewController != null) {
        return WebViewWidget(controller: _webViewController!);
      }
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (type == 'QUIZ' || lesson['is_quiz'] == true) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_primary, _primary.withOpacity(0.8)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.quiz_rounded,
                color: Colors.white,
                size: 80,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Module d\'Évaluation',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Vous devez réussir ce quiz pour passer à la suite du cours.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuizScreen(quiz: lesson),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: const Text(
                'COMMENCER LE QUIZ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    // TEXT content
    String cleanText =
        lesson['content_text'] ?? '<p>Pas de contenu disponible.</p>';
    cleanText = cleanText.replaceAll(
      RegExp(
        r'<[vo]:[^>]*>.*?</[vo]:[^>]*>',
        dotAll: true,
        caseSensitive: false,
      ),
      '',
    );
    cleanText = cleanText.replaceAll(
      RegExp(r'class="Mso[^"]*"', caseSensitive: false),
      '',
    );
    cleanText = cleanText.replaceAll(
      RegExp(r'style="[^"]*mso-[^"]*"', caseSensitive: false),
      '',
    );

    return Container(
      color: const Color(0xFFF8FAFD),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Content header card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.description_rounded,
                      color: _primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Support de cours',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: _dark,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Contenu textuel de la leçon',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Text content
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: HtmlWidget(
                cleanText,
                textStyle: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Color(0xFF374151),
                ),
                customStylesBuilder: (element) {
                  // Force a clean base font size for standard text elements
                  if (element.localName == 'p' ||
                      element.localName == 'span' ||
                      element.localName == 'li' ||
                      element.localName == 'div') {
                    return {'font-size': '14px', 'line-height': '1.6'};
                  }
                  if (element.localName == 'h1') {
                    return {
                      'color': '#0D47A1',
                      'font-weight': '800',
                      'font-size': '22px',
                      'margin-top': '16px',
                      'margin-bottom': '12px',
                    };
                  }
                  if (element.localName == 'h2') {
                    return {
                      'color': '#0D47A1',
                      'font-weight': '700',
                      'font-size': '18px',
                      'margin-top': '14px',
                      'margin-bottom': '10px',
                    };
                  }
                  if (element.localName == 'h3') {
                    return {
                      'color': '#1565C0',
                      'font-weight': '600',
                      'font-size': '16px',
                      'margin-top': '12px',
                      'margin-bottom': '8px',
                    };
                  }
                  if (element.localName == 'blockquote') {
                    return {
                      'background-color': '#F0F4FF',
                      'border-left': '4px solid #0D47A1',
                      'padding': '12px 16px',
                      'border-radius': '4px',
                      'font-style': 'italic',
                      'font-size': '14px',
                    };
                  }
                  if (element.localName == 'code' ||
                      element.localName == 'pre') {
                    return {
                      'background-color': '#1E293B',
                      'color': '#E2E8F0',
                      'padding': '12px',
                      'border-radius': '8px',
                      'font-size': '13px',
                      'font-family': 'monospace',
                    };
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(bool isDark) {
    final isFirst = _currentIndex == 0;
    final isLast = _currentIndex == widget.lessons.length - 1;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).padding.bottom + 14,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1B2E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(isDark ? 0.06 : 0.0),
            width: 1,
          ),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
      ),
      child: Row(
        children: [
          // Prev button
          GestureDetector(
            onTap: isFirst ? null : _prevLesson,
            child: AnimatedOpacity(
              opacity: isFirst ? 0.3 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.arrow_back_ios_rounded,
                  color: isDark ? Colors.white : _primary,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Progress indicator
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.lessons.length > 7 ? 7 : widget.lessons.length,
                    (i) {
                      final actual = widget.lessons.length > 7
                          ? (i * widget.lessons.length ~/ 7)
                          : i;
                      final isActive = _currentIndex == actual;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: isActive ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isActive
                              ? (isDark ? Colors.white : _primary)
                              : (isDark
                                    ? Colors.white30
                                    : const Color(0xFFCBD5E1)),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_currentIndex + 1} / ${widget.lessons.length}',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
        // Next/Finish button
        GestureDetector(
          onTap: isLast
              ? () {
                  final unpassedQuiz = widget.quizzes.firstWhere(
                    (q) => q['has_attempted'] == false,
                    orElse: () => {},
                  );

                  if (unpassedQuiz.isNotEmpty) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => QuizScreen(quiz: unpassedQuiz),
                      ),
                    );
                  } else {
                    Navigator.pop(context);
                  }
                }
              : _nextLesson,
          child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isLast
                      ? [const Color(0xFF059669), const Color(0xFF10B981)]
                      : [_primary, const Color(0xFF1E3A5F)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: (isLast ? Colors.green : _primary).withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isLast ? 'Terminer' : 'Suivant',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isLast
                        ? Icons.check_circle_rounded
                        : Icons.arrow_forward_ios_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonDrawer() {
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width * 0.82,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(-4, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.of(context).padding.top + 16,
                  16,
                  16,
                ),
                decoration: BoxDecoration(
                  color: _primary,
                  boxShadow: [
                    BoxShadow(color: _primary.withOpacity(0.3), blurRadius: 8),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.menu_book_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Contenu du cours',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => setState(() => _showLessonList = false),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: widget.lessons.length,
                  itemBuilder: (context, index) {
                    final l = widget.lessons[index];
                    final isActive = index == _currentIndex;
                    final typeIcon = _getTypeIcon(l['content_type']);

                    final isLocked = l['is_locked'] == true || l['is_locked'] == 1;

                    return GestureDetector(
                      onTap: () {
                        if (isLocked) {
                          _showLockedDialog();
                        } else {
                          _goToLesson(index);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFFEEF2FF)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: isActive
                              ? Border.all(color: _primary.withOpacity(0.3))
                              : null,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? _primary
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: isLocked
                                    ? const Icon(
                                        Icons.lock_rounded,
                                        color: Colors.grey,
                                        size: 16,
                                      )
                                    : isActive
                                        ? const Icon(
                                            Icons.play_arrow_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          )
                                        : Text(
                                            '${index + 1}',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l['title'] ?? '',
                                    style: TextStyle(
                                      fontWeight: isActive
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      fontSize: 13,
                                      color: isActive ? _primary : _dark,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Icon(
                                        typeIcon['icon'],
                                        size: 12,
                                        color: typeIcon['color'],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        typeIcon['label'],
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500],
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
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _getTypeIcon(String? type) {
    switch (type) {
      case 'QUIZ':
        return {
          'icon': Icons.quiz_rounded,
          'color': Colors.amber,
          'label': 'Quiz d\'évaluation',
        };
      case 'VIDEO':
        return {
          'icon': Icons.play_circle_fill_rounded,
          'color': Colors.red,
          'label': 'Vidéo',
        };
      case 'PDF':
        return {
          'icon': Icons.picture_as_pdf_rounded,
          'color': Colors.orange,
          'label': 'PDF',
        };
      case 'PPT':
        return {
          'icon': Icons.slideshow_rounded,
          'color': Colors.purple,
          'label': 'Présentation',
        };
      case 'EXTERNAL':
        return {
          'icon': Icons.public_rounded,
          'color': Colors.blue,
          'label': 'Lien externe',
        };
      default:
        return {
          'icon': Icons.article_rounded,
          'color': Colors.teal,
          'label': 'Texte',
        };
    }
  }
}
