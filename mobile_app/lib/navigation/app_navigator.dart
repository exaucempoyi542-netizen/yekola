import 'package:flutter/material.dart';
import 'package:mobile_app/services/sync_service.dart';
import 'package:mobile_app/screens/course_details_screen.dart';
import 'package:mobile_app/screens/quiz_screen.dart';

/// Clé globale pour naviguer depuis les notifications FCM.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> openCourseFromNotification({
  required String courseId,
  String? lessonId,
  String? quizId,
}) async {
  final nav = appNavigatorKey.currentState;
  if (nav == null) return;

  final sync = SyncService();
  Map<String, dynamic>? course = await sync.getCourseById(courseId);

  if (course == null) {
    // Forcer un refresh catalogue (affiliation) puis réessayer
    await sync.pullCourses();
    course = await sync.getCourseById(courseId);
  }

  if (course == null) {
    final ctx = nav.context;
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
        content: Text(
          'Ce contenu n’est pas accessible. Vérifiez que vous êtes affilié à la bonne promotion.',
        ),
      ),
    );
    return;
  }

  if (quizId != null && quizId.isNotEmpty) {
    final quizzes = List<Map<String, dynamic>>.from(course['quizzes'] ?? []);
    Map<String, dynamic>? quiz;
    for (final q in quizzes) {
      if ('${q['id']}' == quizId) {
        quiz = Map<String, dynamic>.from(q);
        break;
      }
    }
    if (quiz != null) {
      await nav.push(
        MaterialPageRoute(builder: (_) => QuizScreen(quiz: quiz!)),
      );
      return;
    }
  }

  await nav.push(
    MaterialPageRoute(
      builder: (_) => CourseDetailsScreen(
        course: course!,
        initialLessonId: lessonId,
      ),
    ),
  );
}
