import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'dart:typed_data';

import '../../l10n/app_localizations.dart';
import '../../providers/connection_provider.dart';
import '../../providers/conversations_provider.dart';
import '../../providers/messaging_provider.dart';
import '../../theme/rpg_theme.dart';
import '../../utils/secure_context_stub.dart'
    if (dart.library.html) '../../utils/secure_context_web.dart'
    as secure_context;
import '../top_snackbar.dart';

/// CRITICAL (CLAUDE.md): Voice recording mic MUST stay in the widget tree.
/// GestureDetector unmounts -> no events. This widget always renders the mic
/// GestureDetector. It shows a newline helper or spinner instead when
/// [hasText] / [isSendingVoice] override the display.
///
/// Owns all recording state: AudioRecorder lifecycle, drag-to-cancel logic,
/// and the pulse animation for the red recording dot.
class RecordingController extends StatefulWidget {
  const RecordingController({
    super.key,
    required this.onVoiceSent,
    required this.onRecordingStateChanged,
    required this.hasText,
    required this.isSendingVoice,
    required this.onInsertNewline,
  });

  /// Called when a voice message has been recorded and is ready to send.
  final Future<void> Function({
    required int duration,
    String? localAudioPath,
    Uint8List? audioBytes,
  }) onVoiceSent;

  /// Notifies parent of [isRecording] changes so the parent can toggle UI.
  final void Function(bool isRecording) onRecordingStateChanged;

  /// Whether the text field has text — used to show the send button instead of mic.
  final bool hasText;

  /// Whether a voice message is currently being uploaded/sent.
  final bool isSendingVoice;

  /// Inserts a newline in the composer (when [hasText] shows the trailing control).
  final VoidCallback onInsertNewline;

  @override
  State<RecordingController> createState() => RecordingControllerState();
}

class RecordingControllerState extends State<RecordingController>
    with SingleTickerProviderStateMixin {
  // ── recording state ──────────────────────────────────────────────────────
  bool _isRecording = false;
  AudioRecorder? _audioRecorder;
  String? _recordingPath;
  Timer? _recordingTimer;
  DateTime? _recordingStartTime;

  // ── drag-to-cancel ───────────────────────────────────────────────────────
  static const double _trashOpenThresholdPx = 60.0;

  double _getCancelThreshold(BuildContext context) =>
      MediaQuery.of(context).size.width * 0.5;

  double _cancelDragOffset = 0.0;
  double _dragStartX = 0.0;
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

  // ── pulse animation ──────────────────────────────────────────────────────
  late final AnimationController _pulseController;

  // ── public getters ───────────────────────────────────────────────────────
  bool get isRecording => _isRecording;
  double get cancelDragOffset => _cancelDragOffset;

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
        throw Exception('Permission denied');
      }
    }
  }

  // ── recording lifecycle ───────────────────────────────────────────────────

  /// Discards clips shorter than this (UX: very short taps are usually accidental).
  static const int _kMinVoiceRecordingMs = 500;

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

  Future<void> _startRecording(double startX) async {
    _isStartingRecording = true;
    _pendingStopAfterStart = false;
    _dragStartX = startX;
    _cancelDragOffset = 0.0;
    // Capture providers before async gaps to avoid BuildContext-across-async-gap lint.
    final messaging = context.read<MessagingProvider>();
    final convs = context.read<ConversationsProvider>();
    final conn = context.read<ConnectionProvider>();
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
      final convId = convs.activeConversationId;
      if (convId != null) {
        final conv = convs.getConversationById(convId);
        if (conv != null) {
          final recipientId = convs.getOtherUserId(conv);
          conn.socketService.emitRecordingVoice(recipientId, convId, true);
        }
      }

      setState(() {
        _isRecording = true;
        _cancelDragOffset = 0.0;
        _showTrashIcon = false;
        _canceledBySlide = false;
      });
      widget.onRecordingStateChanged(true);

      // Auto-stop at 120s. Periodic timer only checks elapsed — display driven by pulse AnimatedBuilder.
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _recordingStartTime == null) return;
        final elapsed =
            DateTime.now().difference(_recordingStartTime!).inSeconds;
        if (elapsed >= 120) _stopRecording();
      });
    } catch (e) {
      await _releaseRecorderSilently();
      if (!mounted) return;
      showTopSnackBar(
          context, AppLocalizations.of(context).snackbarFailedToStartRecording);
      debugPrint('Recording error: $e');
    } finally {
      _isStartingRecording = false;
      if (mounted && _pendingStopAfterStart && _isRecording && !_canceledBySlide) {
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

  Future<void> _stopRecording() async {
    if (_audioRecorder == null || !_isRecording) return;

    final messaging = context.read<MessagingProvider>();
    final convs = context.read<ConversationsProvider>();
    final conn = context.read<ConnectionProvider>();
    messaging.setIsRecordingVoice(false);
    final convId = convs.activeConversationId;
    if (convId != null) {
      final conv = convs.getConversationById(convId);
      if (conv != null) {
        final recipientId = convs.getOtherUserId(conv);
        conn.socketService.emitRecordingVoice(recipientId, convId, false);
      }
    }
    _recordingTimer?.cancel();
    _recordingTimer = null;

    final path = await _audioRecorder!.stop();
    await _audioRecorder!.dispose();
    _audioRecorder = null;

    setState(() {
      _isRecording = false;
      _cancelDragOffset = 0.0;
      _showTrashIcon = false;
    });
    widget.onRecordingStateChanged(false);

    final durationMs = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!).inMilliseconds
        : 0;
    final durationSeconds = (durationMs + 999) ~/ 1000;
    _recordingStartTime = null;

    if (durationMs < _kMinVoiceRecordingMs) {
      if (!kIsWeb && path != null) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      if (!mounted) return;
      showTopSnackBar(
          context, AppLocalizations.of(context).snackbarHoldLongerForVoiceMessage);
      setState(() => _recordingPath = null);
      return;
    }

    if (path != null) {
      if (kIsWeb) {
        try {
          final response = await http.get(Uri.parse(path));
          if (response.statusCode == 200) {
            await widget.onVoiceSent(
              duration: durationSeconds,
              audioBytes: response.bodyBytes,
            );
          } else {
            if (!mounted) return;
            showTopSnackBar(
                context, AppLocalizations.of(context).snackbarFailedToReadRecording);
          }
        } catch (e) {
          if (!mounted) return;
          showTopSnackBar(
              context,
              AppLocalizations.of(context).snackbarFailedToSendVoiceMessage);
          debugPrint('Send voice error: $e');
        }
      } else {
        final file = File(path);
        if (await file.exists()) {
          await widget.onVoiceSent(
            duration: durationSeconds,
            localAudioPath: path,
          );
        }
      }
    }

    setState(() => _recordingPath = null);
  }

  Future<void> _cancelRecording() async {
    if (_audioRecorder == null || !_isRecording) return;

    final messaging = context.read<MessagingProvider>();
    messaging.setIsRecordingVoice(false);
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

    setState(() {
      _isRecording = false;
      _recordingPath = null;
      _cancelDragOffset = 0.0;
      _showTrashIcon = false;
    });
    widget.onRecordingStateChanged(false);
  }

  // ── drag logic ───────────────────────────────────────────────────────────

  void _onRecordingDragUpdate(double currentX) {
    if (!_isRecording) return;
    setState(() {
      _cancelDragOffset = currentX - _dragStartX;
      _showTrashIcon = _cancelDragOffset < -20;
    });
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

  void _onLongPressFinished() {
    if (_canceledBySlide) return;
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
        _isRecording ? _cancelDragOffset.clamp(-cancelThreshold, 0) : 0.0,
        0,
      ),
      child: GestureDetector(
        onLongPressStart: (details) {
          _abortInFlightStart = false;
          _startRecording(details.globalPosition.dx);
        },
        onLongPressMoveUpdate: (details) =>
            _onRecordingDragUpdate(details.globalPosition.dx),
        onLongPressEnd: (_) => _onLongPressFinished(),
        onLongPressCancel: () {
          if (_isStartingRecording) {
            _abortInFlightStart = true;
            _pendingStopAfterStart = false;
            return;
          }
          _onLongPressFinished();
        },
        child: micVisual,
      ),
    );

    final newlineButton = Tooltip(
      message: AppLocalizations.of(context).chatComposerNewlineTooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          canRequestFocus: false,
          customBorder: const CircleBorder(),
          onTap: widget.onInsertNewline,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.keyboard_return,
              size: 22,
              color: isDark
                  ? RpgTheme.mutedDark
                  : RpgTheme.textSecondaryLight,
            ),
          ),
        ),
      ),
    );

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            ignoring: widget.hasText,
            child: Opacity(
              opacity: widget.hasText ? 0.0 : 1.0,
              child: micHitTarget,
            ),
          ),
          IgnorePointer(
            ignoring: !widget.hasText,
            child: Opacity(
              opacity: widget.hasText ? 1.0 : 0.0,
              child: newlineButton,
            ),
          ),
        ],
      ),
    );
  }

  // ── recording bar (called by parent ChatInputBar) ────────────────────────

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
            AnimatedBuilder(
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
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Opacity(
                opacity: _showTrashIcon ? 0.0 : 1.0,
                child: Text(
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
