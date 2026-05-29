import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'web_ios_webkit.dart';

Future<void> showSoftKeyboardIfHidden({
  required BuildContext context,
  required bool hasFocus,
}) async {
  if (!hasFocus || !isIOSWebKit()) return;
  // No viewInsets guard: call is idempotent when keyboard is already visible,
  // and omitting the check ensures we fire even mid-dismiss-animation.
  try {
    await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  } catch (_) {
    // Best-effort on WebKit PWA.
  }
}
