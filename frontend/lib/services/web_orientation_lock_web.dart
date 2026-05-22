import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

Future<void> lockPortraitPrimaryIfSupported() async {
  if (!web.window.isSecureContext) return;
  final orientation = web.window.screen.orientation;
  final orientationObject = orientation as JSObject;
  if (!orientationObject.hasProperty('lock'.toJS).toDart) return;
  try {
    await orientation.lock('portrait-primary').toDart;
  } catch (_) {
    // Unsupported, denied, or not installed PWA — overlay handles UX.
  }
}
