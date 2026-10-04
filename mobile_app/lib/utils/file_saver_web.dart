import 'dart:html' as html;
import 'dart:typed_data';

/// Déclenche un vrai téléchargement navigateur (dossier Téléchargements).
Future<void> triggerBrowserDownload(Uint8List bytes, String filename) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  // Laisse le navigateur démarrer le téléchargement avant le suivant
  await Future<void>.delayed(const Duration(milliseconds: 350));
}

/// Sur le web, le « stockage local » = téléchargement navigateur.
Future<String?> saveBytes(Uint8List bytes, String filename) async {
  await triggerBrowserDownload(bytes, filename);
  return 'browser:$filename';
}

Future<void> deleteLocalFile(String? path) async {
  // Fichiers déjà dans le dossier Téléchargements du navigateur — rien à effacer.
}
