import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Shows the on-screen keyboard when the field still has focus but [viewInsets]
/// report zero height (common on Android emulator / after composer layout shifts).
Future<void> showSoftKeyboardIfHidden({
  required BuildContext context,
  required bool hasFocus,
}) async {
  if (kIsWeb || !hasFocus) return;
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }
  if (MediaQuery.viewInsetsOf(context).bottom > 0) return;
  try {
    await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  } catch (_) {
    // Best-effort; some platforms may not implement the channel method.
  }
}
