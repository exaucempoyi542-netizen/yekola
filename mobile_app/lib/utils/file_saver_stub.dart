import 'dart:typed_data';

/// Stub (plateformes non supportées).
Future<String?> saveBytes(Uint8List bytes, String filename) async => null;

/// Stub : pas de téléchargement navigateur.
Future<void> triggerBrowserDownload(Uint8List bytes, String filename) async {}

Future<void> deleteLocalFile(String? path) async {}
