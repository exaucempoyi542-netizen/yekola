// File manually generated for Yekola - Firebase configuration.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD8-zpr3SlfY-T5OKZHRVSFJKnqOYgr41g',
    appId: '1:1019671203810:web:c7fe7840778ac0a63eb3bb',
    messagingSenderId: '1019671203810',
    projectId: 'edurdc-a0d8a',
    authDomain: 'edurdc-a0d8a.firebaseapp.com',
    storageBucket: 'edurdc-a0d8a.firebasestorage.app',
    measurementId: 'G-LQ403WLZ4F',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB8wU8mbW7lRC6N62UhCA49PJco4KI_a1A',
    appId: '1:1019671203810:android:26696201d818d2e83eb3bb',
    messagingSenderId: '1019671203810',
    projectId: 'edurdc-a0d8a',
    storageBucket: 'edurdc-a0d8a.firebasestorage.app',
  );
}
