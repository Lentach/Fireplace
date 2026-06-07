import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Returns the browser mic permission state: 'granted' | 'prompt' | 'denied',
/// or 'unsupported' when the Permissions API can't answer (e.g. iOS Safari
/// commonly rejects a 'microphone' query). Never throws.
Future<String> queryMicPermissionState() async {
  try {
    final desc = JSObject();
    desc.setProperty('name'.toJS, 'microphone'.toJS);
    final status = await web.window.navigator.permissions.query(desc).toDart;
    return status.state;
  } catch (_) {
    return 'unsupported';
  }
}
