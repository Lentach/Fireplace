import 'dart:io';

import 'package:flutter/services.dart';

import '../services/device_link/pending_link_code.dart';
import 'anti_quantum_note_link.dart';

/// (lxxvii) clause 4: on Android the /link intent-filter's URL fragment
/// reaches Dart over this channel (MainActivity parks it; `consumeLinkFragment`
/// on the Kotlin side returns it ONCE).
const MethodChannel _linkChannel = MethodChannel('fireplace/link');

bool _warmDeliveryWired = false;

/// Native builds: Android reads the VIEW-intent fragment from the platform
/// channel; other native platforms have no URL to carry a link code.
///
/// The channel read is async while this boot-time call is sync (the web impl
/// reads `Uri.base` synchronously), so the Android path arms
/// [PendingLinkCode] directly when the read lands — same terminal state as
/// `main.dart`'s `arm(...)` on web — and this function still returns null.
String? consumeLinkFragment() {
  if (!Platform.isAndroid) return null;
  _wireWarmDelivery();
  _linkChannel
      .invokeMethod<String>('consumeLinkFragment')
      .then((fragment) {
        if (fragment != null && fragment.startsWith('fp-link.')) {
          PendingLinkCode.arm(fragment);
        }
      })
      // MissingPluginException: an embedding without the channel (tests,
      // add-to-app) simply has no deep link to consume.
      .catchError((Object _) {});
  return null;
}

/// A warm start (launchMode singleTop) delivers the fragment while the app is
/// already running: MainActivity.onNewIntent pushes it here as a method call.
void _wireWarmDelivery() {
  if (_warmDeliveryWired) return;
  _warmDeliveryWired = true;
  _linkChannel.setMethodCallHandler((call) async {
    if (call.method == 'linkFragment') {
      final fragment = call.arguments;
      if (fragment is String && fragment.startsWith('fp-link.')) {
        PendingLinkCode.arm(fragment);
      }
    }
    return null;
  });
}

/// No-op on native — there is no address bar to scrub.
void stripLinkFragment() {}

/// A native install's QR points at the production web origin: the scanning
/// phone opens the PWA (or the native app via its intent filter) there.
Uri linkDeepLinkOrigin() => Uri.parse(kFireplaceProductionOrigin);
