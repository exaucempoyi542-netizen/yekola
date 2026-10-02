import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_chat_service.dart';
import '../services/sync_service.dart';
import '../widgets/profile_avatar.dart';
import 'quiz_screen.dart';
import 'user_profile_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  final Map<String, dynamic> room;
  const ChatDetailScreen({super.key, required this.room});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final FirebaseChatService _chatService = FirebaseChatService();
  final SyncService _syncService = SyncService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _lastMessageCount = 0;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool instant = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (instant) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    try {
      await _chatService.sendMessage(widget.room['id'], text);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  bool _isMine(Map<String, dynamic> message, String myEmail, String? myUid) {
    final sender = (message['sender_id'] ?? '').toString().toLowerCase();
    final senderUid = (message['sender_uid'] ?? '').toString();
    final senderEmail = (message['sender_email'] ?? '').toString().toLowerCase();
    if (myEmail.isNotEmpty && (sender == myEmail || senderEmail == myEmail)) return true;
    if (myUid != null && myUid.isNotEmpty && (sender == myUid || senderUid == myUid)) return true;
    return false;
  }

  String _formatTime(dynamic value) {
    try {
      final DateTime dt = value is DateTime ? value : value.toDate();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  String _formatDayLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) return "Aujourd'hui";
    if (day == today.subtract(const Duration(days: 1))) return 'Hier';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  DateTime? _messageDate(Map<String, dynamic> message) {
    final value = message['created_at'];
    if (value == null) return null;
    try {
      return value is DateTime ? value : value.toDate();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final myEmail = (_chatService.myChatId ?? authProvider.userEmail).trim().toLowerCase();

    String roomName = widget.room['name'] ?? 'Discussion';
    String? otherEmail;
    if (widget.room['is_group'] != true) {
      final names = widget.room['participant_names'] as Map<String, dynamic>?;
      final emails = (widget.room['participant_emails'] as List?)
              ?.map((e) => e.toString().toLowerCase())
              .toList() ??
          [];
      for (final e in emails) {
        if (e.contains('@') && e != myEmail) {
          otherEmail = e;
          break;
        }
      }
      if (otherEmail == null) {
        final participants = (widget.room['participants'] as List?)?.map((e) => e.toString()).toList() ?? [];
        for (final p in participants) {
          final low = p.toLowerCase();
          if (low.contains('@') && low != myEmail) {
            otherEmail = low;
            break;
          }
        }
      }
      if (otherEmail != null && names != null) {
        roomName = (names[otherEmail] ?? names[otherEmail.toLowerCase()] ?? roomName).toString();
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFEEF2F7),
      appBar: AppBar(
        title: InkWell(
          onTap: otherEmail == null
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(
                        email: otherEmail!,
                        initialName: roomName,
                      ),
                    ),
                  );
                },
          child: Row(
            children: [
              otherEmail != null
                  ? ProfileAvatar.fromEmail(otherEmail, radius: 18)
                  : CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF152A45).withValues(alpha: 0.12),
                      child: Text(
                        roomName.isNotEmpty ? roomName[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 14, color: Color(0xFF152A45), fontWeight: FontWeight.bold),
                      ),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    if (otherEmail != null)
                      Text(
                        'Voir le profil',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _chatService.streamMessages(widget.room['id']),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data ?? [];
                if (messages.isEmpty) return _buildEmptyState();

                if (messages.length != _lastMessageCount) {
                  _lastMessageCount = messages.length;
                  _scrollToBottom(instant: _lastMessageCount <= 1);
                }

                final myUid = _chatService.myUid;

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = _isMine(message, myEmail, myUid);
                    final dt = _messageDate(message);
                    final prevDt = index > 0 ? _messageDate(messages[index - 1]) : null;
                    final showDay = dt != null &&
                        (prevDt == null ||
                            dt.year != prevDt.year ||
                            dt.month != prevDt.month ||
                            dt.day != prevDt.day);

                    return Column(
                      children: [
                        if (showDay) _buildDayChip(_formatDayLabel(dt)),
                        _buildMessageBubble(message, isMe),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildDayChip(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'Début de la conversation',
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Envoyez un message pour commencer.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
    final String content = (message['content'] ?? '').toString();
    final bool isQuizLink = content.contains('/quiz/') || content.contains('edurdc://quiz/');
    final time = _formatTime(message['created_at']);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Container(
          margin: EdgeInsets.only(
            top: 2,
            bottom: 6,
            left: isMe ? 40 : 0,
            right: isMe ? 0 : 40,
          ),
          decoration: BoxDecoration(
            color: isQuizLink
                ? const Color(0xFFE3F2FD)
                : (isMe ? const Color(0xFF152A45) : Colors.white),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
            border: isQuizLink ? Border.all(color: Colors.blue.shade200) : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isQuizLink
                  ? () {
                      final regExp = RegExp(
                        r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
                        caseSensitive: false,
                      );
                      final match = regExp.firstMatch(content);
                      if (match != null) _fetchAndStartQuiz(match.group(0)!);
                    }
                  : null,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isQuizLink) ...[
                      Row(
                        children: [
                          Icon(Icons.assignment, color: Colors.blue[700], size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'TP / Quiz partagé',
                            style: TextStyle(
                              color: Colors.blue[700],
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      content,
                      style: TextStyle(
                        color: isMe && !isQuizLink ? Colors.white : const Color(0xFF0F172A),
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                    if (isQuizLink) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final regExp = RegExp(
                              r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
                              caseSensitive: false,
                            );
                            final match = regExp.firstMatch(content);
                            if (match != null) _fetchAndStartQuiz(match.group(0)!);
                          },
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('Commencer le Quiz'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                    if (time.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Text(
                          time,
                          style: TextStyle(
                            fontSize: 10,
                            color: isMe && !isQuizLink
                                ? Colors.white.withValues(alpha: 0.75)
                                : Colors.grey[500],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _fetchAndStartQuiz(String code) async {
    showDialog(context: context, builder: (_) => const Center(child: CircularProgressIndicator()));

    try {
      final response = await http.get(
        Uri.parse('${_syncService.apiBaseUrl}/quizzes/?id_code=$code'),
      );

      if (mounted) Navigator.pop(context);

      if (response.statusCode == 200) {
        final List<dynamic> results = jsonDecode(response.body);
        if (results.isNotEmpty) {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => QuizScreen(quiz: results[0])),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Quiz non trouvé.')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur réseau.')),
        );
      }
    }
  }

  Widget _buildMessageInput() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isTeacher = authProvider.userRole == 'TEACHER';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (isTeacher)
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Color(0xFF152A45)),
                onPressed: _showQuizPicker,
              ),
            Expanded(
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Écrire un message…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: const Color(0xFF152A45),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _sendMessage,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuizPicker() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Partager un TP / Quiz', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text(
              'Sélectionnez un quiz pour l\'envoyer aux étudiants.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _syncService.getQuizzes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('Aucun quiz disponible.'));
                }

                return SizedBox(
                  height: 300,
                  child: ListView.builder(
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, index) {
                      final quiz = snapshot.data![index];
                      return ListTile(
                        leading: const Icon(Icons.assignment, color: Colors.blue),
                        title: Text(quiz['title']),
                        subtitle: Text('${quiz['time_limit']} minutes'),
                        onTap: () {
                          Navigator.pop(context);
                          final quizLink = 'edurdc://quiz/${quiz['id_code']}';
                          _messageController.text = 'Voici votre TP : ${quiz['title']}\n$quizLink';
                          _sendMessage();
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
