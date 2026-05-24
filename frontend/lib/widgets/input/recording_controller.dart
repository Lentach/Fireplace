import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/connection_provider.dart';
import '../../providers/conversations_provider.dart';
import '../../providers/messaging_provider.dart';
import '../../theme/rpg_theme.dart';
import '../../utils/secure_context_stub.dart'
    if (dart.library.html) '../../utils/secure_context_web.dart'
    as secure_context;
import '../top_snackbar.dart';

/// Thrown by [_RecordingControllerState._checkMicPermission] after showing the
/// permission snackbar so [_startRecording] does not show a second generic error.
class MicRecordingPermissionDenied implements Exception {
  const MicRecordingPermissionDenied();
}

/// CRITICAL (CLAUDE.md): Voice recording mic MUST stay in the widget tree.
/// GestureDetector unmounts -> no events. This widget always renders the mic
/// GestureDetector when idle; a spinner replaces it while [isSendingVoice].
///
/// Owns all recording state: AudioRecorder lifecycle, drag-to-cancel logic,
/// and the pulse animation for the red recording dot.
class RecordingController extends StatefulWidget {
  const RecordingController({
    super.key,
    required this.onVoiceSent,
    required this.onRecordingStateChanged,
    this.onRecordingLockChanged,
    required this.isSendingVoice,
  });

  /// Called when a voice message has been recorded and is ready to send.
  final Future<void> Function({
    required int duration,
    String? localAudioPath,
    Uint8List? audioBytes,
  }) onVoiceSent;

  /// Notifies parent of [isRecording] changes so the parent can toggle UI.
  final void Function(bool isRecording) onRecordingStateChanged;

  /// Notifies parent when slide-up lock is entered or cleared (recording bar variant).
  final void Function(bool isLocked)? onRecordingLockChanged;

  /// Whether a voice message is currently being uploaded/sent.
  final bool isSendingVoice;

  @override
  State<RecordingController> createState() => RecordingControllerState();
}

class RecordingControllerState extends State<RecordingController>
    with SingleTickerProviderStateMixin {
  /// Negative: nudge mic left within the hit target so it sits away from the screen’s
  /// right edge (OS / PWA edge-back gestures). Drag-to-cancel still uses global coords.
  static const double _kMicRestingOffsetX = -6.0;

  // ── recording state ──────────────────────────────────────────────────────
  bool _isRecording = false;
  AudioRecorder? _audioRecorder;
  String? _recordingPath;
  Timer? _recordingTimer;
  DateTime? _recordingStartTime;

  // ── drag-to-cancel ───────────────────────────────────────────────────────
  static const double _trashOpenThresholdPx = 60.0;

  // ── slide-up lock (Phase 1) ──────────────────────────────────────────────
  static const double lockUpThresholdPx = 72.0;
  static const double lockUpHintShowPx = 36.0;

  double _getCancelThreshold(BuildContext context) =>
      MediaQuery.of(context).size.width * 0.5;

  double _cancelDragOffset = 0.0;
  double _dragStartX = 0.0;
  double _dragStartY = 0.0;
  double _lockDragOffset = 0.0;
  bool _isLocked = false;
  bool _showTrashIcon = false;
  bool _canceledBySlide = false;

  /// True from first line of [_startRecording] until recording UI is active or start failed.
  /// If the user releases during async mic startup, [onLongPressEnd] must not drop the stop.
  bool _isStartingRecording = false;

  /// User lifted finger while [_isStartingRecording] — stop as soon as [_isRecording] is true.
  bool _pendingStopAfterStart = false;

  /// Set when [onLongPressCancel] fires during async [_startRecording] (e.g. scroll away).
  /// Checked after awaits so recording does not become active after the gesture was canceled.
  bool _abortInFlightStart = false;

  /// Prevents [onLongPressEnd] and [Listener] pointer release from both finishing the gesture.
  bool _gestureFinishHandled = false;

  /// Guards parallel [_stopRecording] (120s timer + finger release).
  bool _isStopping = false;

  // ── pulse animation ──────────────────────────────────────────────────────
  late final AnimationController _pulseController;

  // ── public getters ───────────────────────────────────────────────────────
  bool get isRecording => _isRecording;
  bool get isLocked => _isLocked;
  double get cancelDragOffset => _cancelDragOffset;
  double get lockDragOffset => _lockDragOffset;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _recordingTimer?.cancel();
    _audioRecorder?.dispose();
    super.dispose();
  }

  // ── permission ───────────────────────────────────────────────────────────

  Future<void> _checkMicPermission() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.microphone.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        if (!mounted) return;
        showTopSnackBar(
            context, AppLocalizations.of(context).snackbarMicrophonePermissionRequired);
        throw const MicRecordingPermissionDenied();
      }
    }
  }

  // ── recording lifecycle ───────────────────────────────────────────────────

  /// Discards clips shorter than this (UX: very short taps are usually accidental).
  /// Duration is measured from [_recordingStartTime] (when the recorder actually started),
  /// not from the long-press down event.
  static const int kMinVoiceRecordingMs = 500;

  Future<void> _releaseRecorderSilently() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingStartTime = null;
    final recorder = _audioRecorder;
    _audioRecorder = null;
    if (recorder != null) {
      try {
        await recorder.stop();
      } catch (_) {}
      try {
        await recorder.dispose();
      } catch (_) {}
    }
    final path = _recordingPath;
    _recordingPath = null;
    if (!kIsWeb && path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  void _showNotSentSnackBar(String message) {
    if (!mounted) return;
    showTopSnackBar(context, message);
  }

  Future<void> _startRecording(double startX, double startY) async {
    _gestureFinishHandled = false;
    _isStartingRecording = true;
    _pendingStopAfterStart = false;
    _dragStartX = startX;
    _dragStartY = startY;
    _cancelDragOffset = 0.0;
    _lockDragOffset = 0.0;
    _isLocked = false;
    // Capture providers before async gaps to avoid BuildContext-across-async-gap lint.
    final messaging = context.read<MessagingProvider>();
    try {
      await _checkMicPermission();
      if (_abortInFlightStart || !mounted) return;

      _audioRecorder = AudioRecorder();
      if (kIsWeb) {
        _recordingPath = 'voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      } else {
        final tempDir = await getTemporaryDirectory();
        _recordingPath =
            '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }

      if (_abortInFlightStart || !mounted) {
        await _releaseRecorderSilently();
        return;
      }

      if (kIsWeb && !secure_context.isWebSecureContext()) {
        if (!mounted) {
          await _releaseRecorderSilently();
          return;
        }
        showTopSnackBar(
          context,
          AppLocalizations.of(context).snackbarVoiceRecordingRequiresSecureContext,
        );
        await _releaseRecorderSilently();
        return;
      }

      final hasPermission = await _audioRecorder!.hasPermission();
      if (_abortInFlightStart || !mounted) {
        await _releaseRecorderSilently();
        return;
      }
      if (!hasPermission) {
        if (!mounted) {
          await _releaseRecorderSilently();
          return;
        }
        showTopSnackBar(
            context, AppLocalizations.of(context).snackbarMicrophonePermissionDenied);
        await _releaseRecorderSilently();
        return;
      }

      await _audioRecorder!.start(
        RecordConfig(
          encoder: kIsWeb ? AudioEncoder.wav : AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _recordingPath!,
      );

      if (_abortInFlightStart || !mounted) {
        await _releaseRecorderSilently();
        return;
      }

      _recordingStartTime = DateTime.now();
      messaging.setIsRecordingVoice(true);
      _emitRecordingVoiceToRecipient(true);

      setState(() {
        _isRecording = true;
        _cancelDragOffset = 0.0;
        _lockDragOffset = 0.0;
        _isLocked = false;
        _showTrashIcon = false;
        _canceledBySlide = false;
      });
      widget.onRecordingStateChanged(true);
      if (!kIsWeb) {
        HapticFeedback.lightImpact();
      }

      // Auto-stop at 120s. Periodic timer only checks elapsed — display driven by pulse AnimatedBuilder.
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _recordingStartTime == null) return;
        final elapsed =
            DateTime.now().difference(_recordingStartTime!).inSeconds;
        if (elapsed >= 120) _stopRecording();
      });
    } on MicRecordingPermissionDenied {
      await _releaseRecorderSilently();
    } catch (e) {
      await _releaseRecorderSilently();
      if (!mounted) return;
      showTopSnackBar(
          context, AppLocalizations.of(context).snackbarFailedToStartRecording);
      debugPrint('Recording error: $e');
    } finally {
      _isStartingRecording = false;
      if (mounted &&
          _pendingStopAfterStart &&
          _isRecording &&
          !_canceledBySlide &&
          !_isLocked) {
        _pendingStopAfterStart = false;
        if (_isOverTrash(context)) {
          _cancelRecording();
        } else {
          _stopRecording();
        }
      } else {
        _pendingStopAfterStart = false;
      }
    }
  }

  void _emitRecordingVoiceToRecipient(bool isRecording) {
    final convs = context.read<ConversationsProvider>();
    final conn = context.read<ConnectionProvider>();
    final convId = convs.activeConversationId;
    if (convId == null) return;
    final conv = convs.getConversationById(convId);
    if (conv == null) return;
    final recipientId = convs.getOtherUserId(conv);
    conn.socketService.emitRecordingVoice(recipientId, convId, isRecording);
  }

  Future<void> _stopRecording() async {
    if (_audioRecorder == null || !_isRecording || _isStopping) return;
    _isStopping = true;

    final l10n = AppLocalizations.of(context);
    final messaging = context.read<MessagingProvider>();
    messaging.setIsRecordingVoice(false);
    _emitRecordingVoiceToRecipient(false);
    _recordingTimer?.cancel();
    _recordingTimer = null;

    final path = await _audioRecorder!.stop();
    await _audioRecorder!.dispose();
    _audioRecorder = null;

    final wasLocked = _isLocked;
    setState(() {
      _isRecording = false;
      _cancelDragOffset = 0.0;
      _lockDragOffset = 0.0;
      _isLocked = false;
      _showTrashIcon = false;
    });
    widget.onRecordingStateChanged(false);
    if (wasLocked) {
      _notifyLockChanged(false);
    }

    final durationMs = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!).inMilliseconds
        : 0;
    final durationSeconds = (durationMs + 999) ~/ 1000;
    _recordingStartTime = null;

    try {
      if (durationMs < kMinVoiceRecordingMs) {
        if (!kIsWeb && path != null) {
          try {
            final file = File(path);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
        _showNotSentSnackBar(l10n.snackbarHoldLongerForVoiceMessage);
        setState(() => _recordingPath = null);
        return;
      }

      if (path == null) {
        _showNotSentSnackBar(l10n.snackbarFailedToReadRecording);
        setState(() => _recordingPath = null);
        return;
      }

      if (kIsWeb) {
        try {
          final response = await http.get(Uri.parse(path));
          if (response.statusCode == 200) {
            // Send errors: snackbar in ChatInputBar._handleVoiceSent only.
            await widget.onVoiceSent(
              duration: durationSeconds,
              audioBytes: response.bodyBytes,
            );
          } else {
            _showNotSentSnackBar(l10n.snackbarFailedToReadRecording);
          }
        } catch (e) {
          _showNotSentSnackBar(l10n.snackbarFailedToReadRecording);
          debugPrint('Read voice blob error: $e');
        }
      } else {
        final file = File(path);
        if (await file.exists()) {
          await widget.onVoiceSent(
            duration: durationSeconds,
            localAudioPath: path,
          );
        } else {
          _showNotSentSnackBar(l10n.snackbarFailedToReadRecording);
        }
      }

      setState(() => _recordingPath = null);
    } finally {
      _isStopping = false;
    }
  }

  Future<void> _cancelRecording() async {
    if (_audioRecorder == null || !_isRecording) return;

    final canceledMessage =
        AppLocalizations.of(context).snackbarVoiceRecordingCanceled;
    final messaging = context.read<MessagingProvider>();
    messaging.setIsRecordingVoice(false);
    _emitRecordingVoiceToRecipient(false);
    _canceledBySlide = true;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingStartTime = null;

    await _audioRecorder!.stop();
    await _audioRecorder!.dispose();
    _audioRecorder = null;

    if (!kIsWeb && _recordingPath != null) {
      try {
        final file = File(_recordingPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    final wasLocked = _isLocked;
    setState(() {
      _isRecording = false;
      _recordingPath = null;
      _cancelDragOffset = 0.0;
      _lockDragOffset = 0.0;
      _isLocked = false;
      _showTrashIcon = false;
    });
    widget.onRecordingStateChanged(false);
    if (wasLocked) {
      _notifyLockChanged(false);
    }
    _showNotSentSnackBar(canceledMessage);
  }

  // ── drag logic ───────────────────────────────────────────────────────────

  void _notifyLockChanged(bool locked) {
    widget.onRecordingLockChanged?.call(locked);
  }

  void _enterLockedMode() {
    if (_isLocked || !_isRecording) return;
    setState(() {
      _isLocked = true;
      _cancelDragOffset = 0.0;
      _showTrashIcon = false;
      _lockDragOffset = lockUpThresholdPx;
    });
    _notifyLockChanged(true);
    if (!kIsWeb) {
      HapticFeedback.mediumImpact();
    }
  }

  void _onRecordingDragUpdate(double currentX, double currentY) {
    if (!_isRecording || _isLocked) return;
    final upwardPx = (_dragStartY - currentY).clamp(0.0, double.infinity);
    setState(() {
      _cancelDragOffset = currentX - _dragStartX;
      _showTrashIcon = _cancelDragOffset < -20;
      _lockDragOffset = upwardPx;
    });
    if (upwardPx >= lockUpThresholdPx) {
      _enterLockedMode();
    }
  }

  bool _isOverTrash(BuildContext context) =>
      _cancelDragOffset < -_getCancelThreshold(context);

  // ── helpers ──────────────────────────────────────────────────────────────

  String _formatRecordingDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  // ── build ────────────────────────────────────────────────────────────────

  void _finishRecordingGesture() {
    if (_gestureFinishHandled) return;
    _gestureFinishHandled = true;
    _onLongPressFinished();
  }

  void _onPointerRelease() {
    if (!_isRecording && !_isStartingRecording) return;
    if (_isLocked) return;
    _finishRecordingGesture();
  }

  void _onLongPressFinished() {
    if (_canceledBySlide) return;
    if (_isLocked) return;
    if (_isRecording) {
      if (_isOverTrash(context)) {
        _cancelRecording();
      } else {
        _stopRecording();
      }
    } else if (_isStartingRecording) {
      _pendingStopAfterStart = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Single GestureDetector for hold-to-record: swapping detectors when
    // [_isRecording] flips used to dispose the long-press recognizer mid-gesture,
    // so release often never called [_stopRecording].
    if (widget.isSendingVoice) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final isDark = RpgTheme.isDark(context);
    final cancelThreshold = _getCancelThreshold(context);

    final micVisual = AnimatedScale(
      scale: _isRecording ? 1.15 : 1.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          _isRecording ? Icons.mic : Icons.mic_none,
          size: 22,
          color: _isRecording
              ? Colors.red
              : (isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight),
        ),
      ),
    );

    final micHitTarget = Transform.translate(
      offset: Offset(
        (_isRecording && !_isLocked
                ? _cancelDragOffset.clamp(-cancelThreshold, 0)
                : 0.0) +
            _kMicRestingOffsetX,
        0,
      ),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerUp: (_) => _onPointerRelease(),
        onPointerCancel: (_) => _onPointerRelease(),
        child: GestureDetector(
          onLongPressStart: (details) {
            if (_isRecording || _isStartingRecording || _isLocked) return;
            _abortInFlightStart = false;
            _startRecording(
              details.globalPosition.dx,
              details.globalPosition.dy,
            );
          },
          onLongPressMoveUpdate: (details) => _onRecordingDragUpdate(
            details.globalPosition.dx,
            details.globalPosition.dy,
          ),
          onLongPressEnd: (_) => _finishRecordingGesture(),
          onLongPressCancel: () {
            if (_isStartingRecording) {
              _abortInFlightStart = true;
              _pendingStopAfterStart = false;
              return;
            }
            _finishRecordingGesture();
          },
          child: micVisual,
        ),
      ),
    );

    return SizedBox(
      width: 48,
      height: 48,
      child: micHitTarget,
    );
  }

  /// Widget tests: active recording without mic permission / hardware.
  @visibleForTesting
  void simulateActiveRecordingForTest({
    double startX = 100,
    double startY = 200,
  }) {
    _dragStartX = startX;
    _dragStartY = startY;
    _recordingStartTime = DateTime.now();
    setState(() {
      _isRecording = true;
      _isLocked = false;
      _cancelDragOffset = 0.0;
      _lockDragOffset = 0.0;
      _showTrashIcon = false;
      _canceledBySlide = false;
    });
    widget.onRecordingStateChanged(true);
  }

  /// Widget tests: drive slide-up / slide-left gesture math.
  @visibleForTesting
  void simulateDragUpdateForTest(double globalX, double globalY) {
    _onRecordingDragUpdate(globalX, globalY);
  }

  /// Widget tests: finish gesture as if finger released (unlocked path only).
  @visibleForTesting
  void simulateGestureFinishForTest() {
    _gestureFinishHandled = false;
    _onLongPressFinished();
  }

  /// Widget tests: [Listener] pointer release path while locked.
  @visibleForTesting
  void simulatePointerReleaseForTest() {
    _onPointerRelease();
  }

  /// Widget tests: long-press start guard (mirrors [GestureDetector.onLongPressStart]).
  @visibleForTesting
  void simulateLongPressStartForTest(double globalX, double globalY) {
    if (_isRecording || _isStartingRecording || _isLocked) return;
    _abortInFlightStart = false;
    _startRecording(globalX, globalY);
  }

  /// Discards the current locked recording session (locked bar Cancel).
  void cancelLockedRecording() {
    if (_isRecording && _isLocked) {
      _cancelRecording();
    }
  }

  // ── recording bar (called by parent ChatInputBar) ────────────────────────

  Widget _buildRecordingTimerRow(BuildContext context) {
    final isDark = RpgTheme.isDark(context);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final sec = _recordingStartTime != null
            ? DateTime.now().difference(_recordingStartTime!).inSeconds
            : 0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withValues(
                  alpha: 0.7 + (_pulseController.value * 0.3),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _formatRecordingDuration(sec),
              style: RpgTheme.bodyFont(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget buildRecordingBarLocked(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final fc = FireplaceColors.of(context);
    final l10n = AppLocalizations.of(context);
    final elapsedSec = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!).inSeconds
        : 0;
    final timeLabel = _formatRecordingDuration(elapsedSec);

    return Semantics(
      label: l10n.voiceRecordingLockedSemantics(timeLabel),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: fc.tabBorder),
          color: fc.inputBg,
        ),
        child: Row(
          children: [
            Semantics(
              button: true,
              label: l10n.voiceRecordingCancelLocked,
              child: IconButton(
                onPressed: cancelLockedRecording,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                icon: const Icon(
                  Icons.close,
                  color: Colors.red,
                  size: 24,
                ),
              ),
            ),
            Icon(
              Icons.lock,
              size: 16,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            const SizedBox(width: 8),
            _buildRecordingTimerRow(context),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.voiceRecordingLocked,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildRecordingBar(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final fc = FireplaceColors.of(context);
    final l10n = AppLocalizations.of(context);

    return Semantics(
      label: () {
        final elapsedSec = _recordingStartTime != null
            ? DateTime.now().difference(_recordingStartTime!).inSeconds
            : 0;
        return l10n.voiceRecordingSemanticsLabel(
          _formatRecordingDuration(elapsedSec),
        );
      }(),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: fc.tabBorder),
          color: fc.inputBg,
        ),
        child: Row(
          children: [
            if (_showTrashIcon)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: AnimatedScale(
                  scale:
                      _cancelDragOffset < -_trashOpenThresholdPx ? 1.25 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  child: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 24,
                  ),
                ),
              ),

            // Pulsing red dot + timer (both driven by pulse animation)
            _buildRecordingTimerRow(context),

            const SizedBox(width: 16),

            Expanded(
              child: Opacity(
                opacity: _showTrashIcon ? 0.0 : 1.0,
                child: _lockDragOffset >= lockUpHintShowPx
                    ? Opacity(
                        opacity: ((_lockDragOffset - lockUpHintShowPx) /
                                (lockUpThresholdPx - lockUpHintShowPx))
                            .clamp(0.0, 1.0),
                        child: Text(
                          l10n.voiceRecordingSlideUpToLock,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RpgTheme.bodyFont(
                            fontSize: 14,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      )
                    : Text(
                        l10n.voiceRecordingSlideToCancel,
                        style: RpgTheme.bodyFont(
                          fontSize: 14,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
