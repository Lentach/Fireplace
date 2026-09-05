import 'package:flutter/foundation.dart';

/// Grants the single app-wide inline video playback slot.
///
/// EXACTLY ONE inline session may be live at a time — the cap is mandatory,
/// not a tuning knob: media is whole-file AES-GCM with no streaming, so every
/// live [VideoPlaybackSession] holds a decrypted blob of up to 20 MB in RAM.
///
/// When two eligible bubbles compete, the one with the HIGHER [request]
/// priority wins — bubbles pass the message's send time, so the newest
/// visible clip plays, whatever order the list happened to mount them in.
/// (Owner report 2026-09-06: on chat open the second-to-last video played and
/// the last sat blurred, because "latest requester wins" was mount order.)
/// A lower-priority request against a live holder is DENIED, not queued; the
/// arbiter notifies listeners on every release so denied bubbles can ask
/// again the moment the slot frees.
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
  int _holderPriority = 0;

  /// Claims the slot for [owner] at [priority]. Returns true when [owner]
  /// now holds it. A live holder with a strictly higher priority keeps the
  /// slot and this returns false; otherwise the previous holder's revoke
  /// callback fires (it must dispose its session) AFTER the slot has already
  /// moved, so a revoked holder calling [release] is a no-op.
  /// Re-requesting while already the holder just refreshes the callback.
  bool request(Object owner, VoidCallback onRevoke, {required int priority}) {
    if (identical(_holder, owner)) {
      _onRevoke = onRevoke;
      _holderPriority = priority;
      return true;
    }
    if (_holder != null && _holderPriority > priority) return false;
    final previousRevoke = _onRevoke;
    _holder = owner;
    _onRevoke = onRevoke;
    _holderPriority = priority;
    previousRevoke?.call();
    notifyListeners();
    return true;
  }

  /// True while [owner] holds the slot.
  bool holds(Object owner) => identical(_holder, owner);

  /// Voluntarily gives the slot up. A non-holder calling this is a no-op —
  /// load-bearing, because a revoked holder's teardown path also releases.
  void release(Object owner) {
    if (!identical(_holder, owner)) return;
    _holder = null;
    _onRevoke = null;
    _holderPriority = 0;
    notifyListeners();
  }
}
