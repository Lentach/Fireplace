import 'dart:async';

/// Stubs — freeze/bfcache revival is a web-only failure mode; native apps get
/// real lifecycle callbacks instead.
StreamSubscription<dynamic>? registerPageShowRecoveryListener(
  void Function() onRevived,
) => null;

StreamSubscription<dynamic>? installFreezeReloadGuard({
  required void Function() onFallbackRecover,
  bool Function()? suppressReload,
}) => null;

bool consumeFrozenReloadMarker() => false;

bool frozenPageReloadImminent() => false;
