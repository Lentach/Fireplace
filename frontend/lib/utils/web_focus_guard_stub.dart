import 'package:flutter/widgets.dart' show Rect;

/// Non-web / VM: focus guard is a no-op.
void ensureFocusGuardListenerInstalled() {}

void registerFocusGuardRect(String id, Rect rect) {}

void unregisterFocusGuardRect(String id) {}
