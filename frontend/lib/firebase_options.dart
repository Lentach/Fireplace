// Firebase options per platform.
// API keys live in firebase_secrets.dart (gitignored — never committed).
// To set up: copy firebase_secrets.dart.example → firebase_secrets.dart and fill in values.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'firebase_secrets.dart' as secrets;

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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: secrets.kFirebaseWebApiKey,
    appId: secrets.kFirebaseWebAppId,
    messagingSenderId: secrets.kFirebaseMessagingSenderId,
    projectId: secrets.kFirebaseProjectId,
    authDomain: secrets.kFirebaseAuthDomain,
    storageBucket: secrets.kFirebaseStorageBucket,
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: secrets.kFirebaseAndroidApiKey,
    appId: secrets.kFirebaseAndroidAppId,
    messagingSenderId: secrets.kFirebaseMessagingSenderId,
    projectId: secrets.kFirebaseProjectId,
    storageBucket: secrets.kFirebaseStorageBucket,
  );

  // TODO: Add iOS app in Firebase Console → download GoogleService-Info.plist
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: secrets.kFirebaseWebApiKey,
    appId: 'TODO_REPLACE_WITH_IOS_APP_ID',
    messagingSenderId: secrets.kFirebaseMessagingSenderId,
    projectId: secrets.kFirebaseProjectId,
    storageBucket: secrets.kFirebaseStorageBucket,
    iosBundleId: 'com.fireplace.app',
  );
}
