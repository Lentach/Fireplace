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
import 'recording_waveform.dart';

/// Thrown by [_checkMicPermission] after showing the permission snackbar so
/// [startRecording] does not show a second generic error.
class MicRecordingPermissionDenied implements Exception {
  const MicRecordingPermissionDenied();
}

/// Tap-to-toggle voice recording. Owns the `AudioRecorder` lifecycle and the
/// recording bar (trash + pulsing dot + timer + decorative waveform).
///
/// No gestures: the mic is a plain tap (the parent wires [onMicTap] so it can do
/// iOS-WebKit keyboard housekeeping before calling [startRecording]). Recording
/// ends only via [stopAndSend] / [cancelRecording] / the 120 s cap.
class RecordingController extends StatefulWidget {
  const RecordingController({
    super.key,
    required this.onVoiceSent,
    required this.onRecordingStateChanged,
    required this.onMicTap,
    required this.isSendingVoice,
  });

  /// Called when a voice message has been recorded and is ready to send.
  final Future<void> Function({
    required int duration,
    String? localAudioPath,
    Uint8List? audioBytes,
  }) onVoiceSent;

  /// Notifies parent of [isRecording] changes so it can toggle the composer UI.
  final void Function(bool isRecording) onRecordingStateChanged;

  /// Idle mic tapped. Parent does iOS keyboard housekeeping, then calls
  /// [RecordingControllerState.startRecording]. Kept in the parent so this
  /// widget stays `FocusNode`-agnostic.
  final VoidCallback onMicTap;

  /// Whether a voice message is currently being uploaded/sent.
  final bool isSendingVoice;

  @override
  State<RecordingController> createState() => RecordingControllerState();
}

class RecordingControllerState extends State<RecordingController>
    with SingleTickerProviderStateMixin {
  MessagingProvider? _messagingProvider;
  ConnectionProvider? _connectionProvider;
  ConversationsProvider? _conversationsProvider;

  /// Widget tests: drive [stopAndSend] / [cancelRecording] without hardware.
  @visibleForTesting
  bool testSkipHardware = false;

  /// Session cache: once the OS mic permission is granted we never re-request
  /// it (native). Reduces the re-prompt churn the user reported.
  static bool _micPermissionGranted = false;

  // ── recording state ──
  bool _isRecording = false;
  AudioRecorder? _audioRecorder;
  String? _recordingPath;
  Timer? _recordingTimer;
  DateTime? _recordingStartTime;

  /// Re-entrancy: true from the first line of [startRecording] until start
  /// resolves/fails. A second tap during the async start window is a no-op —
  /// this is the load-bearing half of the double-start guard (the parent's
  /// `IgnorePointer` covers only the post-start window).
  bool _isStarting = false;

  /// Re-entrancy across [stopAndSend] / [cancelRecording] / the 120 s timer,
  /// all reachable as discrete taps in the same frame.
  bool _isStopping = false;

  // ── decorative animation (dot pulse + timer rebuild + waveform sweep) ──
  late final AnimationController _waveformController;

  // ── public getters ──
  bool get isRecording => _isRecording;
  @visibleForTesting
  bool get isStarting => _isStarting;

  /// Discards clips shorter than this (silent — accidental fast taps).
  static const int kMinVoiceRecordingMs = 500;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cacheProvidersFromContext();
  }

  void _cacheProvidersFromContext() {
    try {
      _messagingProvider ??= context.read<MessagingProvider>();
      _connectionProvider ??= context.read<ConnectionProvider>();
      _conversationsProvider ??= context.read<ConversationsProvider>();
    } on ProviderNotFoundException {
      // RecordingController unit tests may omit the provider tree.
    }
  }

  @override
  void initState() {
    super.initState();
    // Do NOT repeat() here — only while recording (idle spin wastes frames on web).
    _waveformController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _waveformController.dispose();
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (_isRecording || _isStarting) {
      _messagingProvider?.setIsRecordingVoice(false);
      _emitRecordingVoiceToRecipient(false);
      unawaited(_releaseRecorderSilently());
    } else {
      final recorder = _audioRecorder;
      _audioRecorder = null;
      recorder?.dispose();
    }
    super.dispose();
  }

  // ── permission ──
  Future<void> _checkMicPermission() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    if (_micPermissionGranted) return;
    final current = await Permission.microphone.status;
    if (current.isGranted) {
      _micPermissionGranted = true;
      return;
    }
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      _micPermissionGranted = true;
      return;
    }
    if (status.isDenied || status.isPermanentlyDenied) {
      if (!mounted) return;
      showTopSnackBar(
        context,
        AppLocalizations.of(context).snackbarMicrophonePermissionRequired,
      );
      throw const MicRecordingPermissionDenied();
    }
  }

  // ── recording lifecycle ──
  Future<void> _releaseRecorderSilently() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingStartTime = null;
    if (_waveformController.isAnimating) _waveformController.stop();
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

  void _emitRecordingVoiceToRecipient(bool isRecording) {
    final convs = _conversationsProvider;
    final conn = _connectionProvider;
    if (convs == null || conn == null) return;
    final convId = convs.activeConversationId;
    if (convId == null) return;
    final conv = convs.getConversationById(convId);
    if (conv == null) return;
    final recipientId = convs.getOtherUserId(conv);
    conn.socketService.emitRecordingVoice(recipientId, convId, isRecording);
  }

  /// Public: idle mic tapped. Parent ([ChatInputBar._onMicTap]) calls this after
  /// iOS keyboard housekeeping.
  Future<void> startRecording() async {
    if (_isRecording || _isStarting || widget.isSendingVoice) return;
    _isStarting = true;
    final messaging = context.read<MessagingProvider>();
    try {
      await _checkMicPermission();
      if (!mounted) return;

      _audioRecorder = AudioRecorder();
      if (kIsWeb) {
        _recordingPath = 'voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      } else {
        final tempDir = await getTemporaryDirectory();
        _recordingPath =
            '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      if (!mounted) {
        await _releaseRecorderSilently();
        return;
      }

      if (kIsWeb && !secure_context.isWebSecureContext()) {
        if (mounted) {
          showTopSnackBar(
            context,
            AppLocalizations.of(context)
                .snackbarVoiceRecordingRequiresSecureContext,
          );
        }
        await _releaseRecorderSilently();
        return;
      }

      // Native is already gated by _checkMicPermission; only probe on web.
      if (kIsWeb) {
        final hasPermission = await _audioRecorder!.hasPermission();
        if (!mounted) {
          await _releaseRecorderSilently();
          return;
        }
        if (!hasPermission) {
          showTopSnackBar(
            context,
            AppLocalizations.of(context).snackbarMicrophonePermissionDenied,
          );
          await _releaseRecorderSilently();
          return;
        }
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
      if (!mounted) {
        await _releaseRecorderSilently();
        return;
      }

      _recordingStartTime = DateTime.now();
      messaging.setIsRecordingVoice(true);
      _emitRecordingVoiceToRecipient(true);
      _waveformController.repeat();

      setState(() => _isRecording = true);
      widget.onRecordingStateChanged(true);
      if (!kIsWeb) HapticFeedback.lightImpact();

      // Auto-stop at 120 s. Display driven by _waveformController, not this timer.
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _recordingStartTime == null) return;
        final elapsed =
            DateTime.now().difference(_recordingStartTime!).inSeconds;
        if (elapsed >= 120) stopAndSend();
      });
    } on MicRecordingPermissionDenied {
      await _releaseRecorderSilently();
    } catch (e) {
      await _releaseRecorderSilently();
      if (mounted) {
        showTopSnackBar(
          context,
          AppLocalizations.of(context).snackbarFailedToStartRecording,
        );
        debugPrint('Recording error: $e');
      }
    } finally {
      _isStarting = false;
    }
  }

  /// Public: tap send. Stops, applies the 500 ms min (silent), uploads.
  Future<void> stopAndSend() async {
    if (!_isRecording || _isStopping) return;
    if (_audioRecorder == null && !testSkipHardware) return;
    _isStopping = true;

    final l10n = AppLocalizations.of(context);
    final messaging = _messagingProvider ?? context.read<MessagingProvider>();
    messaging.setIsRecordingVoice(false);
    _emitRecordingVoiceToRecipient(false);
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (_waveformController.isAnimating) _waveformController.stop();

    String? path;
    final recorder = _audioRecorder;
    if (recorder != null) {
      path = await recorder.stop();
      await recorder.dispose();
    }
    _audioRecorder = null;

    setState(() => _isRecording = false);
    widget.onRecordingStateChanged(false);

    final durationMs = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!).inMilliseconds
        : 0;
    final durationSeconds = (durationMs + 999) ~/ 1000;
    _recordingStartTime = null;

    try {
      if (durationMs < kMinVoiceRecordingMs) {
        // Silent discard — too-short clips are accidental double-taps.
        if (!kIsWeb && path != null) {
          try {
            final file = File(path);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
        setState(() => _recordingPath = null);
        return;
      }

      if (testSkipHardware) {
        await widget.onVoiceSent(duration: durationSeconds);
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

  /// Public: tap trash. Discards the in-progress recording.
  Future<void> cancelRecording() async {
    if (!_isRecording || _isStopping) return;
    if (_audioRecorder == null && !testSkipHardware) return;
    _isStopping = true;

    final canceledMessage =
        AppLocalizations.of(context).snackbarVoiceRecordingCanceled;
    final messaging = _messagingProvider ?? context.read<MessagingProvider>();
    messaging.setIsRecordingVoice(false);
    _emitRecordingVoiceToRecipient(false);
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingStartTime = null;
    if (_waveformController.isAnimating) _waveformController.stop();

    final recorder = _audioRecorder;
    if (recorder != null) {
      await recorder.stop();
      await recorder.dispose();
    }
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
    });
    widget.onRecordingStateChanged(false);
    _showNotSentSnackBar(canceledMessage);
    _isStopping = false;
  }

  // ── helpers ──
  String _formatRecordingDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  // ── build (trailing-slot mic) ──
  @override
  Widget build(BuildContext context) {
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
    return SizedBox(
      width: 48,
      height: 48,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onMicTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            Icons.mic_none,
            size: 22,
            color: isDark ? RpgTheme.mutedDark : RpgTheme.textSecondaryLight,
          ),
        ),
      ),
    );
  }

  // ── recording bar (called by ChatInputBar's Expanded slot) ──
  Widget buildRecordingBar(BuildContext context) {
    final isDark = RpgTheme.isDark(context);
    final fc = FireplaceColors.of(context);
    final l10n = AppLocalizations.of(context);

    return AnimatedBuilder(
      animation: _waveformController,
      builder: (context, _) {
        final sec = _recordingStartTime != null
            ? DateTime.now().difference(_recordingStartTime!).inSeconds
            : 0;
        return Semantics(
          label: l10n.voiceRecordingSemanticsLabel(
            _formatRecordingDuration(sec),
          ),
          child: Container(
            height: 48,
            padding: const EdgeInsets.only(left: 4, right: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: fc.tabBorder),
              color: fc.inputBg,
            ),
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: l10n.voiceRecordingDiscard,
                  child: IconButton(
                    onPressed: cancelRecording,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 24,
                    ),
                  ),
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.withValues(
                      alpha: 0.7 + (_waveformController.value * 0.3),
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
                const SizedBox(width: 12),
                Expanded(
                  child: RecordingWaveform(
                    progress: _waveformController.value,
                    color: (isDark ? Colors.white : Colors.black87)
                        .withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── test hooks ──

  /// Widget tests: enter active recording without mic hardware.
  @visibleForTesting
  void simulateRecordingForTest({Duration elapsed = Duration.zero}) {
    _recordingStartTime = DateTime.now().subtract(elapsed);
    setState(() => _isRecording = true);
    widget.onRecordingStateChanged(true);
  }

  /// Widget tests: force the re-entrancy flag to assert the no-op guard.
  @visibleForTesting
  void debugSetStartingForTest(bool value) {
    _isStarting = value;
  }
}
