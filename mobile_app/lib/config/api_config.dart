/// Configuration API centrale — pointe vers Railway en production.
class ApiConfig {
  /// Backend Yekola déployé sur Railway.
  static const String host = 'https://yekola-production-753a.up.railway.app';

  static const String apiBaseUrl = '$host/api';

  /// Préfixe pour médias / chemins relatifs renvoyés par l'API.
  static String resolveMediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path
          .replaceFirst('http://localhost:', 'http://127.0.0.1:')
          .replaceFirst('https://localhost:', 'https://127.0.0.1:');
    }
    if (path.startsWith('/')) return '$host$path';
    return '$host/$path';
  }
}
