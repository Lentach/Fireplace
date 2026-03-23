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
/// GestureDetector. It shows the send button or spinner instead when
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
    required this.onSend,
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

  /// Callback to send the text message (used by send button).
  final VoidCallback onSend;

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

  Future<void> _startRecording(double startX) async {
    _dragStartX = startX;
    _cancelDragOffset = 0.0;
    // Capture providers before async gaps to avoid BuildContext-across-async-gap lint.
    final messaging = context.read<MessagingProvider>();
    final convs = context.read<ConversationsProvider>();
    final conn = context.read<ConnectionProvider>();
    try {
      await _checkMicPermission();

      _audioRecorder = AudioRecorder();
      if (kIsWeb) {
        _recordingPath = 'voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      } else {
        final tempDir = await getTemporaryDirectory();
        _recordingPath =
            '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }

      if (kIsWeb && !secure_context.isWebSecureContext()) {
        if (!mounted) return;
        showTopSnackBar(
          context,
          AppLocalizations.of(context).snackbarVoiceRecordingRequiresSecureContext,
        );
        return;
      }

      final hasPermission = await _audioRecorder!.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        showTopSnackBar(
            context, AppLocalizations.of(context).snackbarMicrophonePermissionDenied);
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
      if (!mounted) return;
      showTopSnackBar(
          context, AppLocalizations.of(context).snackbarFailedToStartRecording);
      debugPrint('Recording error: $e');
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

    final durationSeconds = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!).inSeconds
        : 0;
    _recordingStartTime = null;

    if (durationSeconds < 1) {
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

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);

    // Sending spinner
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

    // Send button (text entered, not recording)
    if (widget.hasText && !_isRecording) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: RpgTheme.primaryColor(context),
        ),
        child: Focus(
          canRequestFocus: false,
          child: IconButton(
            icon: const Icon(Icons.send_rounded, size: 22),
            color: Colors.white,
            onPressed: widget.onSend,
          ),
        ),
      );
    }

    // Mic button — always rendered so GestureDetector stays in tree.
    // When recording, it moves with the drag offset.
    final cancelThreshold = _getCancelThreshold(context);
    return Transform.translate(
      offset: Offset(
        _isRecording ? _cancelDragOffset.clamp(-cancelThreshold, 0) : 0,
        0,
      ),
      child: GestureDetector(
        onLongPressStart: (details) =>
            _startRecording(details.globalPosition.dx),
        onLongPressMoveUpdate: (details) =>
            _onRecordingDragUpdate(details.globalPosition.dx),
        onLongPressEnd: (_) {
          if (_isRecording && !_canceledBySlide) {
            if (_isOverTrash(context)) {
              _cancelRecording();
            } else {
              _stopRecording();
            }
          }
        },
        onLongPressCancel: () {
          if (_isRecording && !_canceledBySlide) {
            if (_isOverTrash(context)) {
              _cancelRecording();
            } else {
              _stopRecording();
            }
          }
        },
        child: AnimatedScale(
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
                  : (isDark
                      ? RpgTheme.mutedDark
                      : RpgTheme.textSecondaryLight),
            ),
          ),
        ),
      ),
    );
  }

  // ── recording bar (called by parent ChatInputBar) ────────────────────────

  Widget buildRecordingBar(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final fc = FireplaceColors.of(context);

    return Semantics(
      label: () {
        final elapsedSec = _recordingStartTime != null
            ? DateTime.now().difference(_recordingStartTime!).inSeconds
            : 0;
        return 'Recording voice message, ${_formatRecordingDuration(elapsedSec)}. Swipe left to cancel.';
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
                  '⬅ Slide to cancel',
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
