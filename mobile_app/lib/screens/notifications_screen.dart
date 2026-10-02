import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final FirebaseNotificationService _notificationService = FirebaseNotificationService();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.cardColor,
        foregroundColor: const Color(0xFF152A45),
        elevation: 0.5,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _notificationService.streamNotifications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF152A45)));
          }

          if (snapshot.hasError) {
            return Center(child: Text('Erreur: ${snapshot.error}', style: const TextStyle(color: Colors.grey)));
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final note = notifications[index];
              return _buildNotificationCard(note);
            },
          );
        },
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> note) {
    final theme = Theme.of(context);
    final bool isRead = note['is_read'] ?? false;
    final String type = note['type'] ?? 'system';
    final bool isLive = type == 'LIVE_MEET';

    return InkWell(
      onTap: () async {
        if (!isRead) {
          _notificationService.markAsRead(note['id']);
        }
        await _notificationService.openFromNotificationData(note);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: isRead ? Colors.transparent : const Color(0xFFE8F0FE), // Facebook light blue for unread
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIcon(type),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                      ),
                      children: [
                        TextSpan(
                          text: '${note['title'] ?? ''} ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: note['message'] ?? ''),
                        if (isLive) ...[
                          const TextSpan(text: '\nAppuyez pour rejoindre.', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
                        ] else if (type == 'COURSE_PUBLISHED' || type == 'LESSON_NEW' || type == 'QUIZ_PUBLISHED') ...[
                          const TextSpan(text: '\nAppuyez pour consulter.', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
                        ]
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTimestamp(note['created_at']),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            if (!isRead)
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      DateTime dt;
      if (timestamp is Timestamp) {
        dt = timestamp.toDate();
      } else if (timestamp is DateTime) {
        dt = timestamp;
      } else {
        return '';
      }

      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
      return 'Il y a ${diff.inDays} jour(s)';
    } catch (e) {
      return '';
    }
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_outlined, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text('Aucune notification pour le moment.', style: TextStyle(color: Colors.grey)),
          SizedBox(height: 8),
          Text("Vos alertes s'afficheront ici en temps réel.",
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildIcon(String type) {
    IconData icon;
    Color color;
    switch (type) {
      case 'LIVE_MEET':
        icon = Icons.live_tv;
        color = Colors.red;
        break;
      case 'COURSE_PUBLISHED':
      case 'LESSON_NEW':
      case 'course':
        icon = Icons.menu_book;
        color = Colors.blue;
        break;
      case 'QUIZ_PUBLISHED':
        icon = Icons.quiz;
        color = Colors.indigo;
        break;
      case 'TP_NEW':
        icon = Icons.assignment;
        color = Colors.orange;
        break;
      case 'TP_GRADED':
        icon = Icons.assignment_turned_in;
        color = Colors.green;
        break;
      case 'grade':
        icon = Icons.star;
        color = Colors.amber;
        break;
      case 'chat':
        icon = Icons.chat;
        color = Colors.purple;
        break;
      default:
        icon = Icons.info;
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}
