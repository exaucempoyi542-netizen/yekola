import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebaseChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _roomsCollection = 'chat_rooms';
  static const String _messagesCollection = 'messages';

  User? get _user => _auth.currentUser;

  String? get myEmail {
    final email = _user?.email?.trim().toLowerCase();
    return (email != null && email.isNotEmpty) ? email : null;
  }

  String? get myUid => _user?.uid;

  String? get myChatId => myEmail ?? myUid;

  /// ID de salon 1-to-1 déterministe (même document pour les deux comptes).
  static String directRoomId(String emailA, String emailB) {
    final a = emailA.trim().toLowerCase();
    final b = emailB.trim().toLowerCase();
    final sorted = [a, b]..sort();
    String sanitize(String v) =>
        v.replaceAll('@', '_at_').replaceAll('.', '_').replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    return 'dm_${sanitize(sorted[0])}__${sanitize(sorted[1])}';
  }

  /// Ajoute mon UID aux salles où mon e-mail figure (pour les règles Firestore basées sur uid).
  Future<void> claimMyRooms() async {
    final email = myEmail;
    final uid = myUid;
    if (email == null || uid == null) return;

    try {
      final snap = await _db
          .collection(_roomsCollection)
          .where('participants', arrayContains: email)
          .get();
      for (final doc in snap.docs) {
        final participants = List<String>.from(
          (doc.data()['participants'] as List?)?.map((e) => e.toString()) ?? [],
        );
        if (!participants.contains(uid)) {
          await doc.reference.update({
            'participants': FieldValue.arrayUnion([uid, email]),
          });
        }
      }
    } catch (e) {
      debugPrint('[Chat] claimMyRooms error: $e');
    }
  }

  /// Flux des salons : fusion e-mail + UID.
  Stream<List<Map<String, dynamic>>> streamChatRooms() {
    final email = myEmail;
    final uid = myUid;
    if (email == null && uid == null) return Stream.value([]);

    // Ignore future — sync identité en arrière-plan
    unawaited(claimMyRooms());

    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    final byId = <String, Map<String, dynamic>>{};
    final subs = <StreamSubscription>[];

    void emit() {
      final rooms = byId.values.toList();
      rooms.sort((a, b) {
        final aTs = _toDateTime(a['last_message']?['created_at']) ??
            _toDateTime(a['updated_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bTs = _toDateTime(b['last_message']?['created_at']) ??
            _toDateTime(b['updated_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bTs.compareTo(aTs);
      });
      if (!controller.isClosed) controller.add(List<Map<String, dynamic>>.from(rooms));
    }

    void listenFor(String participantKey) {
      final sub = _db
          .collection(_roomsCollection)
          .where('participants', arrayContains: participantKey)
          .snapshots()
          .listen((snapshot) {
        for (final doc in snapshot.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          byId[doc.id] = data;
        }
        // Retirer les docs disparus de cette requête uniquement si absents des deux :
        // on se contente d'un refresh complet des docs présents.
        emit();
      }, onError: (e, _) {
        debugPrint('[Chat] streamChatRooms($participantKey) error: $e');
        if (!controller.isClosed) {
          controller.addError(e);
        }
      });
      subs.add(sub);
    }

    if (email != null) listenFor(email);
    if (uid != null && uid != email) listenFor(uid);

    controller.onListen = () {};
    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
      if (!controller.isClosed) await controller.close();
    };

    return controller.stream;
  }

  Stream<List<Map<String, dynamic>>> streamMessages(String roomId) {
    return _db
        .collection(_roomsCollection)
        .doc(roomId)
        .collection(_messagesCollection)
        .orderBy('created_at', descending: false)
        .snapshots()
        .handleError((e) => debugPrint('[Chat] streamMessages error: $e'))
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  Future<void> sendMessage(String roomId, String content) async {
    final currentUser = _user;
    final email = myEmail;
    final uid = myUid;
    if (currentUser == null || (email == null && uid == null)) {
      throw Exception('Non authentifié');
    }

    final senderId = email ?? uid!;
    final messageData = {
      'sender_id': senderId,
      'sender_uid': uid,
      'sender_email': email,
      'sender_name': currentUser.displayName ?? senderId.split('@').first,
      'content': content,
      'created_at': FieldValue.serverTimestamp(),
      'is_read': false,
    };

    final roomRef = _db.collection(_roomsCollection).doc(roomId);

    final identity = <String>{
      if (email != null) email,
      if (uid != null) uid,
    };

    await roomRef.set({
      'participants': FieldValue.arrayUnion(identity.toList()),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await roomRef.collection(_messagesCollection).add(messageData);

    await roomRef.set({
      'last_message': {
        'sender_id': senderId,
        'sender_uid': uid,
        'sender_name': messageData['sender_name'],
        'content': content,
        'created_at': FieldValue.serverTimestamp(),
        'is_read': false,
      },
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> getOrCreateDirectRoom(
    String otherUserEmail,
    String otherUserName, {
    String? otherFirebaseUid,
  }) async {
    final currentUser = _user;
    final myMail = myEmail;
    final uid = myUid;
    if (currentUser == null || myMail == null) {
      throw Exception('Non authentifié (e-mail Firebase requis)');
    }

    final otherId = otherUserEmail.trim().toLowerCase();
    if (otherId.isEmpty) throw Exception('Adresse e-mail du contact manquante');
    if (otherId == myMail) throw Exception('Vous ne pouvez pas discuter avec vous-même');

    final roomId = directRoomId(myMail, otherId);
    final roomRef = _db.collection(_roomsCollection).doc(roomId);

    final participants = <String>{
      myMail,
      otherId,
      if (uid != null) uid,
      if (otherFirebaseUid != null && otherFirebaseUid.trim().isNotEmpty)
        otherFirebaseUid.trim(),
    };

    final existing = await roomRef.get();
    final names = <String, dynamic>{
      myMail: currentUser.displayName ?? myMail.split('@').first,
      otherId: otherUserName,
    };
    if (existing.exists) {
      final prev = Map<String, dynamic>.from(
        (existing.data()?['participant_names'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v),
            ) ??
            {},
      );
      names.addAll(prev);
      names[myMail] = currentUser.displayName ?? myMail.split('@').first;
      names[otherId] = otherUserName;
    }

    await roomRef.set({
      'is_group': false,
      'participants': FieldValue.arrayUnion(participants.toList()),
      'participant_emails': [myMail, otherId]..sort(),
      'participant_names': names,
      'updated_at': FieldValue.serverTimestamp(),
      if (!existing.exists) 'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return roomId;
  }

  Future<Map<String, dynamic>?> getRoomById(String roomId) async {
    final doc = await _db.collection(_roomsCollection).doc(roomId).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    data['id'] = doc.id;
    return data;
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return value.toDate();
    } catch (_) {
      return null;
    }
  }
}
