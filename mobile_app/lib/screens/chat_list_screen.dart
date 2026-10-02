import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_chat_service.dart';
import '../services/sync_service.dart';
import '../widgets/profile_avatar.dart';
import 'chat_detail_screen.dart';
import 'user_profile_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final FirebaseChatService _chatService = FirebaseChatService();

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final role = authProvider.userRole.toUpperCase();
    final canChat = role == 'TEACHER' || role == 'STUDENT';
    final myId = (_chatService.myChatId ?? authProvider.userEmail).trim().toLowerCase();

    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Messages',
          style: TextStyle(fontWeight: FontWeight.bold, color: theme.textTheme.titleLarge?.color),
        ),
        backgroundColor: theme.cardColor,
        elevation: 0,
        centerTitle: false,
      ),
      body: !canChat
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Le chat est réservé aux enseignants et aux étudiants.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _chatService.streamChatRooms(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Erreur: ${snapshot.error}'));
                }
                final rooms = snapshot.data ?? [];
                if (rooms.isEmpty) return _buildEmptyState();
                return ListView.separated(
                  itemCount: rooms.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                  itemBuilder: (context, index) => _buildRoomTile(rooms[index], myId),
                );
              },
            ),
      floatingActionButton: canChat
          ? FloatingActionButton(
              onPressed: () => _showSearchDialog(context),
              backgroundColor: const Color(0xFF152A45),
              child: const Icon(Icons.add_comment, color: Colors.white),
            )
          : null,
    );
  }

  void _showSearchDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _UserSearchSheet(),
    );
  }

  String? _otherEmail(Map<String, dynamic> room, String myId) {
    final emails = (room['participant_emails'] as List?)?.map((e) => e.toString().toLowerCase()).toList();
    if (emails != null) {
      for (final e in emails) {
        if (e.contains('@') && e != myId) return e;
      }
    }
    final participants = (room['participants'] as List?)?.map((e) => e.toString()).toList() ?? [];
    for (final p in participants) {
      final low = p.toLowerCase();
      if (low.contains('@') && low != myId) return low;
    }
    return null;
  }

  Widget _buildRoomTile(Map<String, dynamic> room, String myId) {
    String roomName = room['name'] ?? 'Discussion';
    final lastMsg = room['last_message'] as Map<String, dynamic>?;
    String lastContent = (lastMsg?['content'] ?? 'Aucun message').toString();
    String time = '';
    final otherEmail = _otherEmail(room, myId);

    if (lastMsg != null && lastMsg['created_at'] != null) {
      try {
        final timestamp = lastMsg['created_at'];
        final DateTime dt = timestamp is DateTime ? timestamp : timestamp.toDate();
        time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        time = '';
      }
    }

    if (room['is_group'] != true) {
      final names = room['participant_names'] as Map<String, dynamic>?;
      if (otherEmail != null && names != null) {
        roomName = (names[otherEmail] ?? names[otherEmail.toLowerCase()] ?? roomName).toString();
      }
    }

    final theme = Theme.of(context);
    final unread = lastMsg != null &&
        lastMsg['is_read'] == false &&
        (lastMsg['sender_id']?.toString().toLowerCase() ?? '') != myId;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatDetailScreen(room: room)),
        );
      },
      leading: GestureDetector(
        onTap: otherEmail == null
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfileScreen(
                      email: otherEmail,
                      initialName: roomName,
                    ),
                  ),
                );
              },
        child: otherEmail != null
            ? ProfileAvatar.fromEmail(otherEmail, radius: 26)
            : CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFF152A45).withValues(alpha: 0.12),
                child: Text(
                  roomName.isNotEmpty ? roomName[0].toUpperCase() : '?',
                  style: const TextStyle(color: Color(0xFF152A45), fontWeight: FontWeight.bold),
                ),
              ),
      ),
      title: Text(
        roomName,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: theme.textTheme.titleMedium?.color,
        ),
      ),
      subtitle: Text(
        lastContent,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: unread ? theme.textTheme.bodyMedium?.color : Colors.grey[600],
          fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
          fontSize: 14,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(time, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          const SizedBox(height: 6),
          if (unread)
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: Color(0xFF152A45), shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[200]),
          const SizedBox(height: 16),
          const Text(
            'Pas encore de messages',
            style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Discutez avec un enseignant ou un étudiant.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _UserSearchSheet extends StatefulWidget {
  const _UserSearchSheet();

  @override
  State<_UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends State<_UserSearchSheet> {
  final SyncService _syncService = SyncService();
  final FirebaseChatService _chatService = FirebaseChatService();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _isSearching = false;
  String? _error;

  void _onSearch(String query) async {
    if (query.trim().length < 2) {
      setState(() {
        _users = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _error = null;
    });
    try {
      final results = await _syncService.searchUsers(query);
      if (!mounted) return;
      setState(() {
        _users = results;
        _isSearching = false;
        if (results.isEmpty) {
          _error = 'Aucun enseignant ou étudiant trouvé.';
        }
      });
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _users = [];
        _isSearching = false;
        _error = e.message == 'NO_DJANGO_TOKEN'
            ? 'Session API expirée. Déconnectez-vous puis reconnectez-vous pour rechercher.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _users = [];
        _isSearching = false;
        _error = 'Erreur de recherche. Réessayez.';
      });
    }
  }

  String _displayName(Map<String, dynamic> user) {
    final first = (user['first_name'] ?? '').toString().trim();
    final last = (user['last_name'] ?? '').toString().trim();
    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    return (user['username'] ?? user['email'] ?? 'Utilisateur').toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nouvelle discussion',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Recherche limitée aux enseignants et étudiants',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Nom, e-mail ou identifiant…',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: theme.brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  onChanged: _onSearch,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _users.isEmpty
                    ? Center(
                        child: Text(
                          _error ?? 'Tapez au moins 2 caractères.',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          final user = _users[index];
                          final role = (user['role'] ?? '').toString().toUpperCase();
                          final name = _displayName(user);
                          final email = (user['email'] ?? '').toString();
                          return ListTile(
                            leading: GestureDetector(
                              onTap: email.isEmpty
                                  ? null
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => UserProfileScreen(
                                            email: email,
                                            initialName: name,
                                            initialRole: role,
                                          ),
                                        ),
                                      );
                                    },
                              child: email.isNotEmpty
                                  ? ProfileAvatar.fromEmail(email, radius: 24)
                                  : CircleAvatar(
                                      backgroundColor: role == 'TEACHER'
                                          ? const Color(0xFF152A45).withValues(alpha: 0.12)
                                          : Colors.teal.withValues(alpha: 0.12),
                                      child: Icon(
                                        role == 'TEACHER' ? Icons.school_rounded : Icons.person_rounded,
                                        color: role == 'TEACHER' ? const Color(0xFF152A45) : Colors.teal,
                                      ),
                                    ),
                            ),
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${role == 'TEACHER' ? 'Enseignant' : 'Étudiant'}${email.isNotEmpty ? ' · $email' : ''}',
                            ),
                            trailing: IconButton(
                              tooltip: 'Voir le profil',
                              icon: const Icon(Icons.info_outline),
                              onPressed: email.isEmpty
                                  ? null
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => UserProfileScreen(
                                            email: email,
                                            initialName: name,
                                            initialRole: role,
                                          ),
                                        ),
                                      );
                                    },
                            ),
                            onTap: () async {
                              if (email.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Ce compte n\'a pas d\'e-mail — impossible d\'ouvrir le chat.'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                              try {
                                final roomId = await _chatService.getOrCreateDirectRoom(
                                  email,
                                  name,
                                  otherFirebaseUid: (user['firebase_uid'] ?? '').toString(),
                                );
                                final roomData = await _chatService.getRoomById(roomId);
                                if (roomData != null && context.mounted) {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => ChatDetailScreen(room: roomData)),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Impossible d\'ouvrir la discussion: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
