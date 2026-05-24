import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'web_ios_webkit.dart';

Future<void> showSoftKeyboardIfHidden({
  required BuildContext context,
  required bool hasFocus,
}) async {
  if (!hasFocus || !isIOSWebKit()) return;
  if (MediaQuery.viewInsetsOf(context).bottom > 0) return;
  try {
    await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  } catch (_) {
    // Best-effort on WebKit PWA.
  }
}
