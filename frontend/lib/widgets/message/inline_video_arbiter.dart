import 'package:flutter/foundation.dart';

/// Grants the single app-wide inline video playback slot.
///
/// EXACTLY ONE inline session may be live at a time — the cap is mandatory,
/// not a tuning knob: media is whole-file AES-GCM with no streaming, so every
/// live [VideoPlaybackSession] holds a decrypted blob of up to 20 MB in RAM.
/// The most recent requester wins; the previous holder is told to release
/// (its [request] callback fires) before the new grant is observable.
///
/// The holder is identified by object identity, so a `State` can pass `this`
/// and never collide with another bubble showing the same message.
class InlineVideoArbiter extends ChangeNotifier {
  InlineVideoArbiter._();

  /// The app-wide instance every bubble shares by default.
  static final InlineVideoArbiter instance = InlineVideoArbiter._();

  /// A private arbiter for tests; production code uses [instance].
  @visibleForTesting
  InlineVideoArbiter.forTest();

  Object? _holder;
  VoidCallback? _onRevoke;

  /// Claims the slot for [owner]. If another owner holds it, that owner's
  /// revoke callback fires (it must dispose its session) AFTER the slot has
  /// already moved, so a revoked holder calling [release] is a no-op.
  /// Re-requesting while already the holder just refreshes the callback.
  void request(Object owner, VoidCallback onRevoke) {
    if (identical(_holder, owner)) {
      _onRevoke = onRevoke;
      return;
    }
    final previousRevoke = _onRevoke;
    _holder = owner;
    _onRevoke = onRevoke;
    previousRevoke?.call();
    notifyListeners();
  }

  /// True while [owner] holds the slot.
  bool holds(Object owner) => identical(_holder, owner);

  /// Voluntarily gives the slot up. A non-holder calling this is a no-op —
  /// load-bearing, because a revoked holder's teardown path also releases.
  void release(Object owner) {
    if (!identical(_holder, owner)) return;
    _holder = null;
    _onRevoke = null;
    notifyListeners();
  }
}
