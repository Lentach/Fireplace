import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:web/web.dart' as web;

const String _kPingAsset = 'assets/sounds/ping_alert.mp3';

web.AudioContext? _ctx;
web.AudioBuffer? _buffer;
JSFunction? _unlockListener;
bool _unlocked = false;

web.AudioContext _context() => _ctx ??= web.AudioContext();

/// Installs a one-shot gesture-unlock for the [web.AudioContext].
///
/// On iOS the context starts `suspended` and only produces sound once it has
/// been `resume()`d from inside a real user gesture. Pings fire on message
/// receipt (no gesture), so we resume on the first gesture after this is
/// installed — by which point an actively-chatting user has tapped/scrolled.
/// Idempotent; the listener stays installed (a `resume()` on an already-running
/// context is a harmless no-op, and a later OS-driven suspend re-unlocks).
void primePingSound() {
  if (_unlockListener != null) return;
  void unlock(web.Event _) {
    if (_unlocked) return;
    final ctx = _context();
    if (ctx.state == 'running') {
      _unlocked = true;
      return;
    }
    ctx.resume().toDart.then((_) => _unlocked = true).ignore();
  }

  final listener = unlock.toJS;
  _unlockListener = listener;
  final opts = web.AddEventListenerOptions(passive: true);
  web.window.addEventListener('pointerdown', listener, opts);
  web.window.addEventListener('touchend', listener, opts);
  web.window.addEventListener('mousedown', listener, opts);
  web.window.addEventListener('keydown', listener, opts);
}

/// Plays the ping alert once via the Web Audio API.
///
/// An `AudioBufferSourceNode` registers no MediaSession (unlike an HTML
/// `<audio>` element), so iOS Safari shows no media-control card for the ping.
Future<void> playPingSound() async {
  try {
    primePingSound();
    final ctx = _context();
    if (ctx.state != 'running') {
      try {
        await ctx.resume().toDart;
      } catch (_) {
        // May stay suspended until a user gesture — best effort.
      }
    }
    final buffer = _buffer ??= await _decodePing(ctx);
    final source = web.AudioBufferSourceNode(
      ctx,
      web.AudioBufferSourceOptions(buffer: buffer),
    );
    source.connect(ctx.destination);
    source.start();
  } catch (_) {
    // Best-effort sound effect — never surface playback failures.
  }
}

Future<web.AudioBuffer> _decodePing(web.AudioContext ctx) async {
  final data = await rootBundle.load(_kPingAsset);
  // Copy into a standalone buffer: rootBundle may return a view into a larger
  // backing store, and decodeAudioData consumes the whole ArrayBuffer.
  final bytes = Uint8List.fromList(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  return await ctx.decodeAudioData(bytes.buffer.toJS).toDart;
}
