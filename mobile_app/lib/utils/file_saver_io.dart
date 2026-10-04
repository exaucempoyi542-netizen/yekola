import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<void> triggerBrowserDownload(Uint8List bytes, String filename) async {
  // Pas de navigateur sur mobile/desktop natif — écriture fichier.
  await saveBytes(bytes, filename);
}

/// Enregistre les octets dans le dossier documents de l'app (hors-ligne).
Future<String?> saveBytes(Uint8List bytes, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final offlineDir = Directory('${dir.path}/offline_courses');
  if (!await offlineDir.exists()) {
    await offlineDir.create(recursive: true);
  }
  final file = File('${offlineDir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Supprime un fichier local s'il existe.
Future<void> deleteLocalFile(String? path) async {
  if (path == null || path.isEmpty) return;
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}
