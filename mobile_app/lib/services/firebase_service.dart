import 'package:cloud_firestore/cloud_firestore.dart';

/// Modèle de données pour une ressource externe (YouTube, sites, etc.)
class ExternalResource {
  final String id;
  final String title;
  final String description;
  final String url;
  final String thumbnailUrl;
  final String category;
  final String? createdAt;

  const ExternalResource({
    required this.id,
    required this.title,
    required this.description,
    required this.url,
    required this.thumbnailUrl,
    required this.category,
    this.createdAt,
  });

  factory ExternalResource.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ExternalResource(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      url: data['url'] ?? '',
      thumbnailUrl: data['thumbnail_url'] ?? '',
      category: data['category'] ?? 'Formation en ligne',
      createdAt: data['created_at'],
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'url': url,
        'thumbnail_url': thumbnailUrl,
        'category': category,
        'created_at': createdAt,
      };
}

/// Service d'accès aux ressources externes stockées sur Firebase Firestore.
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  static const String _collection = 'external_resources';
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Récupère toutes les ressources externes depuis Firestore.
  Future<List<ExternalResource>> getExternalResources() async {
    try {
      final snapshot = await _db
          .collection(_collection)
          .orderBy('created_at', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ExternalResource.fromFirestore(doc))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Stream temps-réel des ressources externes.
  Stream<List<ExternalResource>> streamExternalResources() {
    return _db
        .collection(_collection)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => ExternalResource.fromFirestore(doc)).toList());
  }

  /// Ajoute une nouvelle ressource.
  Future<void> addResource(Map<String, dynamic> data) async {
    await _db.collection(_collection).add({
      ...data,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Met à jour une ressource existante.
  Future<void> updateResource(String id, Map<String, dynamic> data) async {
    await _db.collection(_collection).doc(id).update(data);
  }

  /// Supprime une ressource.
  Future<void> deleteResource(String id) async {
    await _db.collection(_collection).doc(id).delete();
  }
}
