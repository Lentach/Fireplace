import 'dart:async';

/// Stub — freeze/bfcache revival is a web-only failure mode; native apps get
/// real lifecycle callbacks instead.
StreamSubscription<dynamic>? registerPageResumeListener(
  void Function() onResume,
) => null;
