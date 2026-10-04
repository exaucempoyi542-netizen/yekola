import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mobile_app/config/api_config.dart';
import 'database_helper.dart';
import 'auth_service.dart';
import 'firebase_service.dart';

class SyncService {
  final String apiBaseUrl = ApiConfig.apiBaseUrl;
  String get mediaBaseUrl => ApiConfig.host;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  static const Duration _httpTimeout = Duration(seconds: 8);
  static const Duration _cacheTtl = Duration(minutes: 5);

  // Cache en mémoire pour accélérer l'accès immédiat
  static List<Map<String, dynamic>>? _cachedCourses;
  static DateTime? _lastFetch;

  // Cache mémoire des cours téléchargés (utilisé sur Web à la place de SQLite)
  static final List<Map<String, dynamic>> _webDownloadedCourses = [];

  bool get _cacheIsFresh =>
      _cachedCourses != null &&
      _lastFetch != null &&
      DateTime.now().difference(_lastFetch!) < _cacheTtl;

  // Synchronisation descendante (MySQL -> SQLite)
  Future<void> pullCourses({bool forceRefresh = false}) async {
    try {
      // Évite un 2e téléchargement si le cache vient d'être rempli
      if (!forceRefresh && _cacheIsFresh) {
        debugPrint("pullCourses: cache frais, skip réseau.");
        return;
      }

      final token = await AuthService().getToken();
      final headers = {
        'Content-Type': 'application/json',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/courses/'),
            headers: headers,
          )
          .timeout(_httpTimeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        await AuthService().logout();
        debugPrint("Accès non autorisé/expiré — catalogue vidé (connexion Django requise).");
        _cachedCourses = [];
        _lastFetch = DateTime.now();
        return;
      }
      if (response.statusCode == 200) {
        List<dynamic> serverCourses = jsonDecode(response.body);
        
        // Sur le Web, on ignore le cache local car SQLite FFI demande les binaires WASM
        if (kIsWeb) {
             _cachedCourses = List<Map<String, dynamic>>.from(serverCourses);
             _lastFetch = DateTime.now();
             debugPrint("Web détecté, cache mémoire mis à jour (${_cachedCourses!.length} cours), SQLite ignoré.");
             return;
        }

        final db = await _dbHelper.database;
        // Remplacer le catalogue local pour retirer les cours dépubliés / absents
        await db.delete('lessons');
        await db.delete('courses');
        final batch = db.batch();

        for (var course in serverCourses) {
          batch.insert('courses', {
            'id': course['id'],
            'title': course['title'],
            'description': course['description'],
            'teacher_name': course['teacher_name'] ?? 'Inconnu',
            'is_published': course['is_published'] == true ? 1 : 0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);

          if (course['lessons'] != null) {
            for (var lesson in course['lessons']) {
              batch.insert('lessons', {
                'id': lesson['id'],
                'course_id': course['id'],
                'title': lesson['title'],
                'content_type': lesson['content_type'],
                'content_file': lesson['content_file'],
                'content_text': lesson['content_text'],
                'order': lesson['order'],
                'is_locked': lesson['is_locked'] == true ? 1 : 0,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
        }
        await batch.commit(noResult: true);

        // Retirer aussi les téléchargements hors-ligne des cours plus publiés
        final publishedIds = serverCourses.map((c) => c['id']).toSet();
        final downloaded = await db.query('downloaded_courses');
        for (final row in downloaded) {
          if (!publishedIds.contains(row['id'])) {
            await db.delete('downloaded_courses', where: 'id = ?', whereArgs: [row['id']]);
          }
        }
        
        // Mettre à jour le cache mémoire
        _cachedCourses = List<Map<String, dynamic>>.from(serverCourses);
        _lastFetch = DateTime.now();
      }
    } catch (e) {
      debugPrint("Erreur de synchronisation (Pull): $e");
    }
  }

  Future<List<Map<String, dynamic>>> getCourses({bool forceRefresh = false}) async {
    try {
      // Utiliser le cache si récent et qu'on ne force pas le rafraîchissement
      if (!forceRefresh && _cacheIsFresh) {
        return _cachedCourses!;
      }

      final token = await AuthService().getToken();
      final headers = {'Content-Type': 'application/json'};
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final response = await http
          .get(Uri.parse('$apiBaseUrl/courses/'), headers: headers)
          .timeout(_httpTimeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        await AuthService().logout();
        return [];
      } else if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _cachedCourses = List<Map<String, dynamic>>.from(data);
        _lastFetch = DateTime.now();
        return _cachedCourses!;
      } else {
        return _cachedCourses ?? [];
      }
    } catch (e) {
      debugPrint("SyncService.getCourses Error: $e");
      return _cachedCourses ?? [];
    }
  }

  /// Récupère le détail complet d'un cours (leçons + quiz inclus).
  /// La liste catalogue est légère et ne contient PAS les leçons —
  /// il faut donc toujours appeler l'endpoint détail.
  Future<Map<String, dynamic>?> getCourseById(
    String courseId, {
    bool preferCache = false,
  }) async {
    if (preferCache) {
      final cached = _cachedCourses;
      if (cached != null) {
        for (final c in cached) {
          if ('${c['id']}' == courseId && c['lessons'] is List) {
            return Map<String, dynamic>.from(c);
          }
        }
      }
    }

    try {
      final token = await AuthService().getToken();
      if (token == null || token.isEmpty) return null;
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/courses/$courseId/'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final detail = Map<String, dynamic>.from(jsonDecode(response.body));
        // Enrichir le cache catalogue avec le détail (leçons/quiz)
        final cached = _cachedCourses;
        if (cached != null) {
          final idx = cached.indexWhere((c) => '${c['id']}' == courseId);
          if (idx >= 0) {
            cached[idx] = {...cached[idx], ...detail};
          }
        }
        // Persister les leçons en local pour l'offline
        await _persistCourseDetail(detail);
        return detail;
      }
    } catch (e) {
      debugPrint("SyncService.getCourseById Error: $e");
    }

    // Fallback cache (même sans leçons) si le réseau échoue
    final cached = _cachedCourses;
    if (cached != null) {
      for (final c in cached) {
        if ('${c['id']}' == courseId) {
          return Map<String, dynamic>.from(c);
        }
      }
    }
    return null;
  }

  Future<void> _persistCourseDetail(Map<String, dynamic> course) async {
    if (kIsWeb) return;
    try {
      final db = await _dbHelper.database;
      final courseId = course['id'];
      if (courseId == null) return;

      await db.insert(
        'courses',
        {
          'id': courseId,
          'title': course['title'],
          'description': course['description'],
          'teacher_name': course['teacher_name'] ?? 'Inconnu',
          'is_published': course['is_published'] == true ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await db.delete('lessons', where: 'course_id = ?', whereArgs: [courseId]);
      final lessons = course['lessons'];
      if (lessons is List) {
        final batch = db.batch();
        for (final lesson in lessons) {
          if (lesson is! Map) continue;
          batch.insert(
            'lessons',
            {
              'id': lesson['id'],
              'course_id': courseId,
              'title': lesson['title'],
              'content_type': lesson['content_type'],
              'content_file': lesson['content_file'],
              'content_text': lesson['content_text'],
              'order': lesson['order'],
              'is_locked': lesson['is_locked'] == true ? 1 : 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }
    } catch (e) {
      debugPrint('SyncService._persistCourseDetail: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchNotifications() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/notifications/'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data);
      } else {
        throw Exception("Erreur API Notifications ${response.statusCode}");
      }
    } catch (e) {
      print("Erreur SyncService.fetchNotifications: $e");
      rethrow;
    }
  }

  // Synchronisation des notes de l'étudiant
  Future<void> syncGrades() async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$apiBaseUrl/students/grades/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        List<dynamic> serverGrades = jsonDecode(response.body);
        
        if (!kIsWeb) {
          final db = await _dbHelper.database;
          final batch = db.batch();
          
          for (var grade in serverGrades) {
            batch.insert('grades', {
              'id': grade['id'],
              'course_id': grade['course_id'],
              'course_title': grade['course_title'],
              'score': grade['score'],
              'session': grade['session'],
              'date_graded': grade['date_graded'],
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          await batch.commit(noResult: true);
        }
      }
    } catch (e) {
      debugPrint("Erreur SyncService.syncGrades: $e");
    }
  }

  // Synchronisation montante (SQLite -> MySQL)
  Future<void> pushLocalChanges() async {
    // TODO: Implémenter l'envoi des logs de progression hors-ligne
    print("Synchronisation des modifications locales vers MySQL...");
  }

  Future<bool> toggleLike(int courseId) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return false;
      final response = await http.post(
        Uri.parse('$apiBaseUrl/courses/$courseId/toggle_like/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Error liking course: $e');
      return false;
    }
  }

  Future<bool> toggleFavorite(int courseId) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return false;
      final response = await http.post(
        Uri.parse('$apiBaseUrl/courses/$courseId/toggle_favorite/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Error favoriting course: $e');
      return false;
    }
  }

  Future<bool> addComment(int courseId, String content, {int? parentId}) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return false;
      final response = await http.post(
        Uri.parse('$apiBaseUrl/courses/$courseId/add_comment/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'content': content,
          'parent_id': parentId,
        }),
      );
      return response.statusCode == 201;
    } catch (e) {
      print('Error adding comment: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getComments(int courseId) async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/courses/$courseId/comments/'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      print('Error picking comments: $e');
      return [];
    }
  }

  // --- NOUVELLES METHODES POUR LES LECONS (TikTok Style) ---

  Future<bool> toggleLessonLike(int lessonId) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return false;
      final response = await http.post(
        Uri.parse('$apiBaseUrl/lessons/$lessonId/toggle_like/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Error liking lesson: $e');
      return false;
    }
  }

  Future<bool> addLessonComment(int lessonId, String content, {int? parentId}) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return false;
      final response = await http.post(
        Uri.parse('$apiBaseUrl/lessons/$lessonId/add_comment/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'content': content,
          'parent_id': parentId,
        }),
      );
      return response.statusCode == 201;
    } catch (e) {
      print('Error adding lesson comment: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getLessonComments(int lessonId) async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/lessons/$lessonId/comments/'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      print('Error picking lesson comments: $e');
      return [];
    }
  }

  Future<bool> toggleLessonFavorite(int lessonId) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return false;
      final response = await http.post(
        Uri.parse('$apiBaseUrl/lessons/$lessonId/toggle_favorite/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Error favoriting lesson: $e');
      return false;
    }
  }

  Future<bool> toggleEnroll(int courseId) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return false;
      final response = await http.post(
        Uri.parse('$apiBaseUrl/courses/$courseId/toggle_enroll/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Error enrolling in course: $e');
      return false;
    }
  }

  /// Retourne null en cas de problème réseau, sinon {statusCode, body}
  Future<Map<String, dynamic>?> toggleEnrollWithDetails(int courseId) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) {
        return {'statusCode': 401, 'body': <String, dynamic>{'error': 'Non connecté. Veuillez vous reconnecter.'}};
      }
      debugPrint('[Enrollment] Calling: $apiBaseUrl/courses/$courseId/toggle_enroll/');
      final response = await http.post(
        Uri.parse('$apiBaseUrl/courses/$courseId/toggle_enroll/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      debugPrint('[Enrollment] Response: ${response.statusCode} — ${response.body}');
      Map<String, dynamic> body = {};
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      return {'statusCode': response.statusCode, 'body': body};
    } catch (e) {
      debugPrint('[Enrollment] Network error: $e');
      return null; // Signale une erreur réseau
    }
  }

  Future<bool> updateEnrollmentProgress(int courseId, double progress) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return false;
      final response = await http.post(
        Uri.parse('$apiBaseUrl/courses/$courseId/update_progress/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'progress': progress,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error updating course progress: $e');
      return false;
    }
  }

  Future<bool> toggleFollow(int teacherId) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return false;
      final response = await http.post(
        Uri.parse('$apiBaseUrl/users/$teacherId/toggle_follow/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Error following teacher: $e');
      return false;
    }
  }

  // --- CHAT METHODS ---

  Future<List<Map<String, dynamic>>> getChatRooms() async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return [];
      final response = await http.get(
        Uri.parse('$apiBaseUrl/chat-rooms/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      print('Error fetching chat rooms: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getChatMessages(int roomId) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return [];
      final response = await http.get(
        Uri.parse('$apiBaseUrl/chat-messages/?room_id=$roomId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      print('Error fetching chat messages: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> sendChatMessage(int roomId, String content) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return null;
      final response = await http.post(
        Uri.parse('$apiBaseUrl/chat-messages/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'room': roomId,
          'content': content,
        }),
      );
      if (response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Error sending message: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getOrCreateDirectRoom(int userId) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return null;
      final response = await http.post(
        Uri.parse('$apiBaseUrl/chat-rooms/get_or_create_direct_room/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'user_id': userId}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Error getting/creating room: $e');
      return null;
    }
  }

  /// Recherche enseignants / étudiants pour le chat.
  /// Lève [StateError] si le JWT Django est absent.
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) {
        throw StateError('NO_DJANGO_TOKEN');
      }
      final encoded = Uri.encodeQueryComponent(query.trim());
      final response = await http.get(
        Uri.parse('$apiBaseUrl/users/?search=$encoded&chat=1&roles=TEACHER,STUDENT'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      debugPrint('[searchUsers] ${response.statusCode} ${response.body.length} bytes');
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> data = decoded is Map && decoded['results'] is List
            ? decoded['results'] as List
            : (decoded is List ? decoded : []);
        return data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((u) {
              final role = (u['role'] ?? '').toString().toUpperCase();
              return role == 'TEACHER' || role == 'STUDENT';
            })
            .toList();
      }
      if (response.statusCode == 401) {
        throw StateError('NO_DJANGO_TOKEN');
      }
      return [];
    } on StateError {
      rethrow;
    } catch (e) {
      print('Error searching users: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> submitQuiz(int quizId, List<Map<String, dynamic>> answers) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return null;
      final response = await http.post(
        Uri.parse('$apiBaseUrl/quizzes/$quizId/submit/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'answers': answers}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Error submitting quiz: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getQuizzes() async {
    try {
      final token = await AuthService().getToken();
      final response = await http.get(
        Uri.parse('$apiBaseUrl/quizzes/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('Error fetching quizzes: $e');
    }
    return [];
  }

  /// Ressources externes désactivées (plus exposées aux étudiants).
  Future<List<Map<String, dynamic>>> getExternalResources() async {
    return [];
  }

  Future<Map<String, dynamic>?> fetchStudentStats() async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return null;
      final response = await http.get(
        Uri.parse('$apiBaseUrl/users/student_stats/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final stats = jsonDecode(response.body) as Map<String, dynamic>;
        
        // Sauvegarder les stats clés en local pour consultation hors-ligne
        if (!kIsWeb) {
           await _dbHelper.insertGrade({
             'id': 1, // On garde une seule entrée pour les stats globales
             'course_title': 'Statistiques Globales',
             'score': stats['average_quiz_score'] ?? 0.0,
             'date_graded': DateTime.now().toIso8601String(),
           });
        }
        
        return stats;
      }
      return null;
    } catch (e) {
      print('Error fetching student stats: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> loadLocalStats() async {
    if (kIsWeb) return null;
    final grades = await _dbHelper.getGrades();
    if (grades.isNotEmpty) {
      // Pour l'instant on simule le format attendu par StatisticsScreen
      final latest = grades.first;
      return {
        'average_quiz_score': latest['score'],
        'is_offline': true,
      };
    }
    return null;
  }

  // ─── API TRAVAUX PRATIQUES (TP) ─────────────────────────────────────────

  /// Récupère les TPs d'un cours (ou tous les TPs accessibles si course_id est null)
  Future<List<Map<String, dynamic>>> getAssignments({int? courseId}) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return [];
      final uri = courseId != null
          ? Uri.parse('$apiBaseUrl/assignments/?course_id=$courseId')
          : Uri.parse('$apiBaseUrl/assignments/');
      final response = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      debugPrint('SyncService.getAssignments Error: $e');
      return [];
    }
  }

  /// Soumet un fichier TP pour un étudiant
  Future<Map<String, dynamic>?> submitAssignment(int assignmentId, dynamic file) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return null;
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiBaseUrl/assignments/$assignmentId/submit/'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      
      if (kIsWeb || file.path == null) {
        request.files.add(http.MultipartFile.fromBytes(
          'file', 
          file.bytes as List<int>, 
          filename: file.name
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath('file', file.path as String));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      debugPrint('submitAssignment error ${response.statusCode}: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('SyncService.submitAssignment Error: $e');
      return null;
    }
  }

  /// Récupère toutes les soumissions de TP de l'étudiant connecté
  Future<List<Map<String, dynamic>>> getMySubmissions() async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return [];
      final response = await http.get(
        Uri.parse('$apiBaseUrl/assignments/my-submissions/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      debugPrint('SyncService.getMySubmissions Error: $e');
      return [];
    }
  }

  /// L'enseignant attribue une cote à une soumission TP
  Future<Map<String, dynamic>?> gradeSubmission(int assignmentId, int submissionId, double grade, String comment) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) return null;
      final response = await http.post(
        Uri.parse('$apiBaseUrl/assignments/$assignmentId/grade/$submissionId/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'grade': grade, 'grade_comment': comment}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      debugPrint('gradeSubmission error ${response.statusCode}: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('SyncService.gradeSubmission Error: $e');
      return null;
    }
  }

  // ─── TÉLÉCHARGEMENT DE COURS HORS-LIGNE ─────────────────────────────────

  /// Télécharge les métadonnées d'un cours (leçons, description) pour accès hors-ligne.
  Future<bool> downloadCourse(Map<String, dynamic> course) async {
    try {
      // Le cours passé en paramètre contient déjà _unifiedContent grâce à course_details_screen
      // On l'enrichit quand même avec les données fraîches de l'API
      Map<String, dynamic> courseData = Map<String, dynamic>.from(course);

      try {
        final token = await AuthService().getToken();
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (token != null) headers['Authorization'] = 'Bearer $token';
        final response = await http.get(
          Uri.parse('$apiBaseUrl/courses/${course['id']}/'),
          headers: headers,
        ).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final fromApi = jsonDecode(response.body) as Map<String, dynamic>;
          // On garde les leçons passées en paramètre si l'API n'en retourne pas
          if ((fromApi['lessons'] as List?)?.isNotEmpty == true) {
            courseData = fromApi;
          } else {
            courseData.addAll(fromApi);
          }
        }
      } catch (netErr) {
        debugPrint('downloadCourse: API non disponible, utilisation des données locales ($netErr)');
      }

      if (kIsWeb) {
        // Sur Web : stockage en cache mémoire (sans téléchargement local de fichiers)
        final courseId = courseData['id'];
        _webDownloadedCourses.removeWhere((c) => c['id'] == courseId);
        _webDownloadedCourses.add(courseData);
      } else {
        // --- REAL FILE DOWNLOAD LOGIC FOR MOBILE ---
        if (courseData['lessons'] != null) {
          final dir = await getApplicationDocumentsDirectory();
          final List<dynamic> lessons = courseData['lessons'];
          
          for (var i = 0; i < lessons.length; i++) {
            final lesson = lessons[i] as Map<String, dynamic>;
            final type = lesson['content_type'];
            final fileUrlRaw = lesson['content_file'];
            
            if (fileUrlRaw != null && fileUrlRaw.toString().isNotEmpty) {
              if (type == 'VIDEO' || type == 'PDF' || type == 'PPT') {
                final fileUrl = fileUrlRaw.toString().startsWith('http') 
                                ? fileUrlRaw.toString() 
                                : '$mediaBaseUrl$fileUrlRaw';
                                
                try {
                  // Crée une extension basée sur le type
                  String ext = 'bin';
                  if (type == 'VIDEO') ext = 'mp4';
                  if (type == 'PDF') ext = 'pdf';
                  if (type == 'PPT') ext = 'pptx';
                  
                  final localFile = File('${dir.path}/course_${courseData['id']}_lesson_${lesson['id']}.$ext');
                  
                  // Télécharger uniquement si le fichier n'existe pas déjà
                  if (!(await localFile.exists())) {
                    final bytesResponse = await http.get(Uri.parse(fileUrl));
                    if (bytesResponse.statusCode == 200) {
                      await localFile.writeAsBytes(bytesResponse.bodyBytes);
                    }
                  }
                  
                  // Ajouter le chemin local à l'objet leçon pour l'enregistrement SQLite
                  if (await localFile.exists()) {
                    lesson['local_path'] = localFile.path;
                    lessons[i] = lesson;
                  }
                } catch (dlErr) {
                  debugPrint('Failed to download file for lesson ${lesson['id']}: $dlErr');
                }
              }
            }
          }
          courseData['lessons'] = lessons;
        }
        
        await _dbHelper.downloadCourse(courseData);
      }
      return true;
    } catch (e) {
      debugPrint('SyncService.downloadCourse Error: $e');
      return false;
    }
  }

  /// Récupère la liste des cours téléchargés localement
  Future<List<Map<String, dynamic>>> getDownloadedCourses() async {
    if (kIsWeb) {
      return List<Map<String, dynamic>>.from(_webDownloadedCourses);
    }
    try {
      return await _dbHelper.getDownloadedCourses();
    } catch (e) {
      debugPrint('SyncService.getDownloadedCourses Error: $e');
      return [];
    }
  }

  /// Supprime un cours téléchargé du stockage local
  Future<void> deleteCourseDownload(int courseId) async {
    if (kIsWeb) {
      _webDownloadedCourses.removeWhere((c) => c['id'] == courseId);
      return;
    }
    try {
      await _dbHelper.deleteCourseDownload(courseId);
    } catch (e) {
      debugPrint('SyncService.deleteCourseDownload Error: $e');
    }
  }
}
