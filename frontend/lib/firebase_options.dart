// THIS FILE IS A PLACEHOLDER — replace it by running FlutterFire CLI:
//
//   npm install -g firebase-tools
//   dart pub global activate flutterfire_cli
//   cd frontend
//   flutterfire configure --project=<your-firebase-project-id>
//
// The CLI will overwrite this file with real credentials for each platform.
// Do NOT commit real Firebase credentials to version control.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // Filled from Firebase Console → Web app config
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REMOVED',
    appId: '1:650276507312:web:a3d4c73e91ac8d7b79b575',
    messagingSenderId: '650276507312',
    projectId: 'fireplace-android',
    authDomain: 'fireplace-android.firebaseapp.com',
    storageBucket: 'fireplace-android.firebasestorage.app',
  );

  // Filled from google-services.json
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REMOVED',
    appId: '1:650276507312:android:1ff894f0a7d940a079b575',
    messagingSenderId: '650276507312',
    projectId: 'fireplace-android',
    storageBucket: 'fireplace-android.firebasestorage.app',
  );

  // TODO: Add iOS app in Firebase Console → add app → iOS → download GoogleService-Info.plist
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'TODO_REPLACE_WITH_IOS_API_KEY',
    appId: 'TODO_REPLACE_WITH_IOS_APP_ID',
    messagingSenderId: '650276507312',
    projectId: 'fireplace-android',
    storageBucket: 'fireplace-android.firebasestorage.app',
    iosBundleId: 'com.fireplace.app',
  );
}
