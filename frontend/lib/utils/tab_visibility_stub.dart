import 'dart:async';

/// No-op on non-web platforms.
StreamSubscription<dynamic>? registerTabVisibilityListener(
  void Function(bool isVisible) onChanged,
) =>
    null;
