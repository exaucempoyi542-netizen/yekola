import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobile_app/navigation/app_navigator.dart';

class FirebaseNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _notificationsCollection = 'notifications';

  /// Initialisation des notifications
  Future<void> initialize() async {
    // 1. Demander les permissions
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted notification permissions');
      
      // 2. Récupérer le token
      String? token = await _fcm.getToken();
      if (token != null) {
        _saveTokenToFirestore(token);
      }

      // 3. Écouter les messages au premier plan
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        if (message.notification != null) {
          _saveNotificationToHistory(
            message.notification!.title ?? 'Notification',
            message.notification!.body ?? '',
            message.data['type'] ?? 'system',
            extra: message.data,
          );
        }
      });

      // 4. Écouter les appuis sur une notification quand l'app est en arrière-plan
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleNotificationTap(message.data);
      });

      // 5. Gérer le tap initial si l'application était totalement fermée
      FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
        if (message != null) {
          _handleNotificationTap(message.data);
        }
      });
    }
  }

  /// Gestion des taps sur la notification (FCM data payload)
  Future<void> _handleNotificationTap(Map<String, dynamic> data) async {
    final type = data['type']?.toString() ?? '';

    if (type == 'LIVE_MEET' && data.containsKey('meet_url')) {
      final meetUrl = data['meet_url']?.toString();
      if (meetUrl != null && meetUrl.isNotEmpty) {
        final uri = Uri.parse(meetUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          debugPrint('Could not launch $meetUrl');
        }
      }
      return;
    }

    if (type == 'COURSE_PUBLISHED' ||
        type == 'LESSON_NEW' ||
        type == 'QUIZ_PUBLISHED' ||
        type == 'course') {
      final courseId = data['course_id']?.toString();
      if (courseId == null || courseId.isEmpty) return;
      // Petit délai pour laisser le navigator monter si l'app démarre à froid
      await Future.delayed(const Duration(milliseconds: 600));
      await openCourseFromNotification(
        courseId: courseId,
        lessonId: data['lesson_id']?.toString(),
        quizId: data['quiz_id']?.toString(),
      );
    }
  }

  /// Sauvegarder le token FCM dans Firestore
  Future<void> _saveTokenToFirestore(String token) async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('[FCM] Pas de session Firebase — token non enregistré');
      return;
    }

    final email = (user.email ?? '').trim().toLowerCase();
    await _db.collection('user_tokens').doc(user.uid).set({
      'token': token,
      'updated_at': FieldValue.serverTimestamp(),
      'email': email,
      'uid': user.uid,
    }, SetOptions(merge: true));
    debugPrint('[FCM] Token enregistré pour $email / ${user.uid}');
  }

  /// Sauvegarder une notification dans l'historique Firestore
  Future<void> _saveNotificationToHistory(
    String title,
    String message,
    String type, {
    Map<String, dynamic>? extra,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final data = <String, dynamic>{
      'user_uid': user.uid,
      'email': user.email,
      'title': title,
      'message': message,
      'type': type,
      'created_at': FieldValue.serverTimestamp(),
      'is_read': false,
    };
    if (extra != null) {
      for (final entry in extra.entries) {
        if (entry.key == 'type') continue;
        data[entry.key] = entry.value?.toString();
      }
    }

    await _db.collection(_notificationsCollection).add(data);
  }

  /// Flux de notifications en temps réel
  Stream<List<Map<String, dynamic>>> streamNotifications() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _db
        .collection(_notificationsCollection)
        .where(
          Filter.or(
            Filter('user_uid', isEqualTo: user.uid),
            Filter('email', isEqualTo: user.email),
          ),
        )
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Tri local côté mobile pour éviter de demander un index composé côté Firestore
      list.sort((a, b) {
        final timestampA = a['created_at'] as Timestamp?;
        final timestampB = b['created_at'] as Timestamp?;
        if (timestampA == null && timestampB == null) return 0;
        if (timestampA == null) return 1;
        if (timestampB == null) return -1;
        return timestampB.compareTo(timestampA); // Décroissant (plus récent en premier)
      });

      return list;
    });
  }

  /// Marquer une notification comme lue
  Future<void> markAsRead(String notificationId) async {
    await _db.collection(_notificationsCollection).doc(notificationId).update({
      'is_read': true,
    });
  }

  /// Navigation depuis l'écran Notifications (données Firestore)
  Future<void> openFromNotificationData(Map<String, dynamic> note) async {
    await _handleNotificationTap(note);
  }
}
