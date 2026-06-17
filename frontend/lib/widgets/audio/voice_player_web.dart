import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'voice_player.dart';

// One AudioContext shared by every voice bubble — iOS caps the number of live
// AudioContexts, and the coordinator already guarantees only one plays at a
// time. Lazily created.
web.AudioContext? _sharedCtx;
JSFunction? _unlockListener;

web.AudioContext _context() => _sharedCtx ??= web.AudioContext();

// iOS starts an AudioContext `suspended`/`interrupted` and only resumes it from
// inside a user gesture. First voice playback resumes post-await (after fetch +
// decode), which iOS may reject — so, like the ping, resume on every gesture
// (cheap: a no-op when already running) to keep the shared context running.
void _installUnlock() {
  if (_unlockListener != null) return;
  void unlock(web.Event _) {
    final ctx = _context();
    if (ctx.state != 'running') ctx.resume().toDart.ignore();
  }

  final listener = unlock.toJS;
  _unlockListener = listener;
  final opts = web.AddEventListenerOptions(passive: true);
  web.window.addEventListener('pointerdown', listener, opts);
  web.window.addEventListener('touchend', listener, opts);
  web.window.addEventListener('mousedown', listener, opts);
  web.window.addEventListener('keydown', listener, opts);
}

/// Web [VoicePlayer]: plays decoded audio through an `AudioBufferSourceNode`,
/// which registers no MediaSession — so iOS shows no media-control card.
///
/// A source node is one-shot, so play/pause/seek/speed are modelled by stopping
/// the current source and starting a fresh one at the right buffer offset;
/// position is derived from `AudioContext.currentTime` and emitted by a ticker.
class WebVoicePlayer implements VoicePlayer {
  WebVoicePlayer() {
    _installUnlock();
  }

  final _stateCtrl = StreamController<VoicePlayerState>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration?>.broadcast();

  web.AudioBuffer? _buffer;
  web.AudioBufferSourceNode? _source;
  Timer? _ticker;

  bool _playing = false;
  double _speed = 1.0;
  double _offsetSec = 0.0; // buffer offset where the current run began
  double _startCtxTime = 0.0; // ctx.currentTime captured at run start
  bool _disposed = false;

  @override
  Stream<VoicePlayerState> get stateStream => _stateCtrl.stream;
  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;
  @override
  Stream<Duration?> get durationStream => _durationCtrl.stream;

  double get _durationSec => _buffer?.duration ?? 0.0;

  @override
  Duration? get duration {
    final b = _buffer;
    if (b == null) return null;
    return Duration(milliseconds: (b.duration * 1000).round());
  }

  double _currentOffsetSec() {
    if (!_playing) return _offsetSec;
    final elapsed = (_context().currentTime - _startCtxTime) * _speed;
    final pos = _offsetSec + elapsed;
    if (pos <= 0) return 0;
    if (pos >= _durationSec) return _durationSec;
    return pos;
  }

  void _emitState() =>
      _stateCtrl.add(VoicePlayerState(playing: _playing, completed: false));

  void _emitPosition() => _positionCtrl
      .add(Duration(milliseconds: (_currentOffsetSec() * 1000).round()));

  @override
  Future<void> setFilePath(String path) =>
      throw UnsupportedError('setFilePath is native-only');

  @override
  Future<void> setUrl(String url) =>
      throw UnsupportedError('setUrl is native-only');

  @override
  Future<void> setAudioBytes(Uint8List bytes) async {
    final ctx = _context();
    // decodeAudioData consumes the ArrayBuffer; copy into a standalone buffer.
    final copy = Uint8List.fromList(bytes);
    final buffer = await ctx.decodeAudioData(copy.buffer.toJS).toDart;
    if (_disposed) return;
    _buffer = buffer;
    _offsetSec = 0.0;
    _durationCtrl.add(duration);
    _positionCtrl.add(Duration.zero);
  }

  void _startSource(double offsetSec) {
    final ctx = _context();
    final buffer = _buffer;
    if (buffer == null) return;
    final source = web.AudioBufferSourceNode(
      ctx,
      web.AudioBufferSourceOptions(buffer: buffer),
    );
    source.playbackRate.value = _speed;
    source.connect(ctx.destination);
    source.onended = ((web.Event _) => _onSourceEnded(source)).toJS;
    _source = source;
    _startCtxTime = ctx.currentTime;
    _offsetSec = offsetSec;
    source.start(0, offsetSec);
  }

  // Detach + stop the active source. Null `_source` FIRST so a stop-triggered
  // `ended` event is ignored by the identity guard in [_onSourceEnded].
  void _stopSource() {
    final s = _source;
    _source = null;
    if (s != null) {
      s.onended = null;
      try {
        s.stop();
      } catch (_) {}
      try {
        s.disconnect();
      } catch (_) {}
    }
  }

  void _onSourceEnded(web.AudioBufferSourceNode source) {
    // Only the still-active source reaching its natural end counts (deliberate
    // stops null/replace `_source` first).
    if (!identical(_source, source)) return;
    _source = null;
    _playing = false;
    _offsetSec = 0.0;
    _stopTicker();
    _positionCtrl.add(Duration.zero);
    _stateCtrl.add(const VoicePlayerState(playing: false, completed: true));
  }

  @override
  Future<void> play() async {
    if (_buffer == null || _playing) return;
    final ctx = _context();
    if (ctx.state != 'running') {
      try {
        await ctx.resume().toDart;
      } catch (_) {}
    }
    var off = _offsetSec;
    if (off >= _durationSec) off = 0.0; // replay from start after completion
    _playing = true;
    _startSource(off);
    _startTicker();
    _emitState();
    _emitPosition();
  }

  @override
  Future<void> pause() async {
    if (!_playing) return;
    final off = _currentOffsetSec();
    _stopSource();
    _offsetSec = off;
    _playing = false;
    _stopTicker();
    _emitState();
    _emitPosition();
  }

  @override
  Future<void> stop() async {
    _stopSource();
    _offsetSec = 0.0;
    _playing = false;
    _stopTicker();
    _emitState();
    _positionCtrl.add(Duration.zero);
  }

  @override
  Future<void> seek(Duration position) async {
    var off = position.inMilliseconds / 1000.0;
    if (off < 0) off = 0;
    if (off > _durationSec) off = _durationSec;
    if (_playing) {
      _stopSource();
      _startSource(off);
    } else {
      _offsetSec = off;
    }
    _emitPosition();
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (_playing) {
      final off = _currentOffsetSec(); // re-anchor before changing the rate
      _stopSource();
      _speed = speed;
      _startSource(off);
    } else {
      _speed = speed;
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_playing) _emitPosition();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _stopSource();
    _stopTicker();
    _stateCtrl.close();
    _positionCtrl.close();
    _durationCtrl.close();
  }
}

VoicePlayer createVoicePlayer() => WebVoicePlayer();
